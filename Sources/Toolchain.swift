import AppKit
import Foundation

/// Locates the `claude` CLI, Claude Desktop and terminal apps. GUI apps don't inherit the
/// user's shell PATH, so the CLI is found by probing known install locations first.
enum Toolchain {
    static let desktopBundleID = "com.anthropic.claudefordesktop"
    static let itermBundleID = "com.googlecode.iterm2"
    static let terminalBundleID = "com.apple.Terminal"

    static func claudePath() -> String? {
        let fm = FileManager.default
        let override = Paths.expand(Prefs.claudePathOverride)
        if !override.isEmpty, fm.isExecutableFile(atPath: override) { return override }
        let candidates = [
            "~/.local/bin/claude",
            "~/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "~/.npm-global/bin/claude",
            "~/.bun/bin/claude",
        ].map(Paths.expand)
        return candidates.first { fm.isExecutableFile(atPath: $0) } ?? shellResolvedClaude
    }

    /// Fallback for unusual installs (nvm, volta, asdf…): ask the user's login shell.
    private static let shellResolvedClaude: String? = {
        let r = Shell.run(userShell, ["-l", "-i", "-c", "printf '__CM__%s' \"$(command -v claude)\""], timeout: 8)
        guard let range = r.stdout.range(of: "__CM__", options: .backwards) else { return nil }
        let path = String(r.stdout[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }()

    /// The user's interactive PATH, so npm-installed `claude` can find `node`.
    static let loginPATH: String = {
        let fallback = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            + ":" + ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].map(Paths.expand).joined(separator: ":")
        let r = Shell.run(userShell, ["-l", "-i", "-c", "printf '__CM__%s' \"$PATH\""], timeout: 8)
        guard let range = r.stdout.range(of: "__CM__", options: .backwards) else { return fallback }
        let path = String(r.stdout[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? fallback : path
    }()

    static var userShell: String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            let s = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: s) { return s }
        }
        return "/bin/zsh"
    }

    static func desktopAppURL() -> URL? {
        let fm = FileManager.default
        let override = Paths.expand(Prefs.desktopAppOverride)
        if !override.isEmpty, fm.fileExists(atPath: override) { return URL(fileURLWithPath: override) }
        let candidates = ["/Applications/Claude.app", "~/Applications/Claude.app"].map(Paths.expand)
        if let hit = candidates.first(where: { fm.fileExists(atPath: $0 + "/Contents/MacOS/Claude") }) {
            return URL(fileURLWithPath: hit)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: desktopBundleID),
           !url.path.hasPrefix("/Volumes/") {
            return url
        }
        return nil
    }

    static func itermURL() -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: itermBundleID) }

    static func terminalURL() -> URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleID)
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    }

    static func claudeVersion(at path: String) -> String? {
        let r = Shell.run(path, ["--version"], environment: subprocessEnvironment([]), timeout: 10)
        guard r.ok else { return nil }
        return r.stdout.split(separator: " ").first.map(String.init)
    }

    /// Environment for background `claude` invocations made on a profile's behalf.
    static func subprocessEnvironment(_ profileEnv: [(String, String)]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !InheritedEnvironment.isLeaked($0.key) }
        env.removeValue(forKey: "CLAUDE_CONFIG_DIR")
        env["PATH"] = loginPATH
        for (k, v) in profileEnv { env[k] = v }
        return env
    }
}

/// Variables a parent terminal or Claude Code session leaves behind. When Claude Manager is
/// started from a terminal, macOS hands it that terminal's environment, and from there it flows
/// into every Terminal window and `claude` it launches: the session markers make the new session
/// think it's a subagent (so it stops saving transcripts), and COLORTERM=truecolor garbles
/// colors in Terminal.app, which only supports 256 colors before macOS 26.
enum InheritedEnvironment {
    static let sessionMarkers = [
        "CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_EXECPATH",
        "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_MESSAGING_SOCKET",
        "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_CODE_SSE_PORT", "CLAUDE_PID", "CLAUDE_EFFORT",
    ]
    static let terminalIdentity = [
        "COLORTERM", "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID",
        "ITERM_SESSION_ID", "ITERM_PROFILE", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    ]
    /// Per-pane variables from terminal apps that host agents (Orca).
    static let prefixes = ["ORCA_"]

    static func isLeaked(_ key: String) -> Bool {
        sessionMarkers.contains(key) || terminalIdentity.contains(key) || prefixes.contains { key.hasPrefix($0) }
    }

    /// Run once at startup so nothing launched from here inherits them.
    static func scrubCurrentProcess() {
        for key in ProcessInfo.processInfo.environment.keys where isLeaked(key) { unsetenv(key) }
    }

    /// The terminal window itself may have been started from a polluted environment,
    /// so launch scripts clear the same variables again before running `claude`.
    static func scriptLines() -> [String] {
        var lines = [
            "unset \(sessionMarkers.joined(separator: " "))",
            "for v in $(env | sed -n 's/^\\(\(prefixes.joined(separator: "\\|"))[A-Za-z0-9_]*\\)=.*/\\1/p'); do unset \"$v\"; done",
        ]
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
            lines.append("if [ \"$TERM_PROGRAM\" = Apple_Terminal ]; then unset COLORTERM; fi")
        }
        return lines
    }
}
