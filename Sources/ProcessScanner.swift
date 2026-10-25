import Darwin
import Foundation

struct DesktopInstance: Identifiable, Hashable {
    let pid: pid_t
    /// nil when launched without --user-data-dir (the default profile).
    let userDataDir: String?
    let startedAt: Date?
    var id: pid_t { pid }
}

struct CodeSession: Identifiable, Hashable {
    let pid: pid_t
    /// CLAUDE_CONFIG_DIR from the process environment; nil means the default ~/.claude.
    let configDir: String?
    let cwd: String?
    let startedAt: Date?
    /// Sessions started by Claude Desktop's built-in Code tab rather than a terminal.
    let viaDesktop: Bool
    var id: pid_t { pid }
}

/// Finds running Claude Desktop and Claude Code processes owned by this user, reading each
/// candidate's argv/environment straight from the kernel (no `ps` parsing, exact paths).
enum ProcessScanner {
    struct Snapshot: Equatable {
        var desktop: [DesktopInstance] = []
        var code: [CodeSession] = []
    }

    static func scan() -> Snapshot {
        let uid = getuid()
        var snapshot = Snapshot()
        var codeParents: [pid_t: pid_t] = [:]

        for pid in allPIDs() where pid > 0 {
            guard let path = executablePath(pid) else { continue }
            let isDesktop = path.hasSuffix(".app/Contents/MacOS/Claude")
            let isNode = path.hasSuffix("/node")
            let isCode = !isDesktop && (URL(fileURLWithPath: path).lastPathComponent == "claude"
                                        || path.contains("/claude/versions/"))
            guard isDesktop || isCode || isNode else { continue }
            guard let info = bsdInfo(pid), info.pbi_uid == uid else { continue }
            guard let (args, env) = argumentsAndEnvironment(pid) else { continue }
            let started = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))

            if isDesktop {
                // Electron helpers (renderer, GPU…) carry --type=; only the main process counts.
                if args.contains(where: { $0.hasPrefix("--type=") }) { continue }
                snapshot.desktop.append(DesktopInstance(pid: pid, userDataDir: userDataDir(in: args), startedAt: started))
                continue
            }

            if isNode && !args.contains(where: { $0.contains("claude-code/cli") }) { continue }
            // Skip short-lived housekeeping invocations (including our own status checks).
            // `auth login` stays: once signed in it carries on as a normal interactive session.
            let rest = args.dropFirst(isNode ? 2 : 1)
            let sub = rest.first ?? ""
            if ["--version", "-v", "update", "doctor", "mcp", "config"].contains(sub) { continue }
            if sub == "auth" && rest.dropFirst().first != "login" { continue }

            snapshot.code.append(CodeSession(pid: pid,
                                             configDir: env["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 },
                                             cwd: currentDirectory(pid),
                                             startedAt: started,
                                             viaDesktop: path.contains("/Application Support/Claude/")))
            codeParents[pid] = pid_t(info.pbi_ppid)
        }

        // A claude process spawned by another claude process is a subagent/tool, not a session.
        let codePIDs = Set(snapshot.code.map(\.pid))
        snapshot.code.removeAll { codeParents[$0.pid].map(codePIDs.contains) ?? false }
        snapshot.code.sort { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
        snapshot.desktop.sort { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
        return snapshot
    }

    private static func userDataDir(in args: [String]) -> String? {
        for (i, arg) in args.enumerated() {
            if arg.hasPrefix("--user-data-dir=") { return String(arg.dropFirst("--user-data-dir=".count)) }
            if arg == "--user-data-dir", i + 1 < args.count { return args[i + 1] }
        }
        return nil
    }

    // MARK: libproc / sysctl

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 128)
        let count = pids.withUnsafeMutableBufferPointer { buf in
            proc_listallpids(buf.baseAddress, Int32(buf.count * MemoryLayout<pid_t>.size))
        }
        return count > 0 ? Array(pids.prefix(Int(count))) : []
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func currentDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    /// KERN_PROCARGS2 layout: argc, exec path, padding NULs, argv[argc], envp…, NUL.
    private static func argumentsAndEnvironment(_ pid: pid_t) -> ([String], [String: String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        func next() -> String {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            let s = String(decoding: buf[start..<i], as: UTF8.self)
            i += 1
            return s
        }
        _ = next()
        while i < size && buf[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < argc && i < size { args.append(next()) }
        var env: [String: String] = [:]
        while i < size && buf[i] != 0 {
            let kv = next()
            if let eq = kv.firstIndex(of: "=") {
                env[String(kv[..<eq])] = String(kv[kv.index(after: eq)...])
            }
        }
        return (args, env)
    }
}
