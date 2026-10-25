import AppKit
import Foundation

enum LaunchError: LocalizedError {
    case desktopNotInstalled
    case iTermNotInstalled
    case appleScript(String)
    case wouldOverwrite(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .desktopNotInstalled:
            return "Claude Desktop isn't installed. Download it from claude.ai/download, or choose its location in Settings."
        case .iTermNotInstalled:
            return "iTerm2 isn't installed. Pick another terminal in Settings."
        case .appleScript(let msg):
            return "iTerm2 refused the request: \(msg)\n\nAllow Claude Manager under System Settings → Privacy & Security → Automation."
        case .wouldOverwrite(let path):
            return "\(Paths.abbreviate(path)) already exists and wasn't created by Claude Manager, so it was left alone."
        case .failed(let msg):
            return msg
        }
    }
}

/// Starts Claude Desktop / Claude Code for a profile. Stateless so both the GUI and the
/// headless `--launch-*` mode used by Dock launchers share it.
enum Launcher {
    static let managedMarker = "# managed-by: Claude Manager"

    // MARK: Claude Desktop

    /// Electron keys its single-instance lock on the userData folder, so a separate
    /// --user-data-dir gives a fully separate app instance with its own cookies/login.
    static func openDesktop(_ profile: Profile, completion: @escaping (Error?) -> Void) {
        guard let appURL = Toolchain.desktopAppURL() else { return completion(LaunchError.desktopNotInstalled) }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        if !profile.usesDefaultDesktopDir {
            do {
                try FileManager.default.createDirectory(at: profile.desktopDirURL, withIntermediateDirectories: true)
            } catch { return completion(error) }
            config.arguments = ["--user-data-dir=\(profile.desktopDirURL.path)"]
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: Claude Code

    /// Shell lines that put a shell into the profile and start `claude`.
    /// With `sessionAfter`, a successful first command (e.g. `auth login`) rolls straight into a session.
    static func codeScriptLines(_ profile: Profile, folder: URL, claudePath: String?, arguments: String,
                                sessionAfter: String? = nil) -> [String] {
        var lines = ["cd \(Shell.quote(folder.path)) || exit 1"]
        lines += InheritedEnvironment.scriptLines()
        if profile.usesDefaultCodeDir { lines.append("unset CLAUDE_CONFIG_DIR") }
        for (k, v) in profile.codeEnvironment { lines.append("export \(k)=\(Shell.quote(v))") }
        lines.append("export CLAUDE_MANAGER_PROFILE=\(Shell.quote(profile.name))")
        var command = claudeInvocation(claudePath: claudePath, arguments: arguments)
        if let sessionAfter {
            command += " && { echo; echo 'Signed in. Starting Claude Code…'; echo; "
                + claudeInvocation(claudePath: claudePath, arguments: sessionAfter) + "; }"
        }
        lines.append(command)
        return lines
    }

    /// One-liner suitable for pasting into any terminal.
    static func codeOneLiner(_ profile: Profile, folder: URL?, claudePath: String?, arguments: String? = nil) -> String {
        var parts: [String] = []
        if let folder { parts.append("cd \(Shell.quote(folder.path)) &&") }
        if profile.usesDefaultCodeDir { parts.append("env -u CLAUDE_CONFIG_DIR") }
        for (k, v) in profile.codeEnvironment { parts.append("\(k)=\(Shell.quote(v))") }
        parts.append(claudeInvocation(claudePath: claudePath, arguments: arguments ?? profile.codeArgs))
        return parts.joined(separator: " ")
    }

    private static func claudeInvocation(claudePath: String?, arguments: String) -> String {
        let exe = claudePath.map(Shell.quote) ?? "claude"
        let args = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        return args.isEmpty ? exe : "\(exe) \(args)"
    }

    /// Opens a new terminal window running Claude Code for `profile` in `folder`.
    /// `arguments` replaces the profile's default args (used for `auth login`, `update`…);
    /// `startSessionAfter` then starts a normal session if that command succeeds.
    static func launchCode(_ profile: Profile, folder: URL, claudePath: String?, arguments: String? = nil,
                           startSessionAfter: Bool = false, completion: @escaping (Error?) -> Void) {
        let args = arguments ?? profile.codeArgs
        let title = "Claude Code · \(profile.name)"
        let lines = codeScriptLines(profile, folder: folder, claudePath: claudePath, arguments: args,
                                    sessionAfter: startSessionAfter ? profile.codeArgs : nil)
        let script: URL
        do {
            script = try writeCommandScript(lines: lines, title: title, profileName: profile.name)
        } catch { return completion(error) }
        switch Prefs.terminal {
        case .iterm:
            guard Toolchain.itermURL() != nil else { return completion(LaunchError.iTermNotInstalled) }
            // exec works in any shell (including fish) and leaves a login shell with the profile's env.
            runInITerm("exec \(Shell.quote(script.path))", completion: completion)
        case .terminal:
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([script], withApplicationAt: Toolchain.terminalURL(), configuration: config) { _, error in
                DispatchQueue.main.async { completion(error) }
            }
        case .custom:
            let command = Prefs.customTemplate
                .replacingOccurrences(of: "{script}", with: Shell.quote(script.path))
                .replacingOccurrences(of: "{dir}", with: Shell.quote(folder.path))
            DispatchQueue.global().async {
                let r = Shell.run("/bin/sh", ["-c", command], environment: Toolchain.subprocessEnvironment([]), timeout: 15)
                DispatchQueue.main.async {
                    completion(r.ok ? nil : LaunchError.failed("Custom terminal command failed:\n\(r.stderr.isEmpty ? r.stdout : r.stderr)"))
                }
            }
        }
    }

    /// A self-deleting .command file. Terminal runs these without needing Automation access.
    /// After `claude` exits the window drops into a login shell that still has the profile's env.
    private static func writeCommandScript(lines: [String], title: String, profileName: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.runDir, withIntermediateDirectories: true)
        let url = Paths.runDir.appendingPathComponent("claude-\(UUID().uuidString.prefix(8)).command")
        let body = """
        #!/bin/sh
        rm -f -- "$0"
        clear
        printf '\\033]0;%s\\007' \(Shell.quote(title))
        \(lines.joined(separator: "\n"))
        echo
        echo \(Shell.quote("Claude Code exited. This shell is still using the \"\(profileName)\" profile."))
        exec "${SHELL:-/bin/zsh}" -l

        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private static func runInITerm(_ command: String, completion: @escaping (Error?) -> Void) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application id "\(Toolchain.itermBundleID)"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(escaped)"
            end tell
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            completion(LaunchError.appleScript(error[NSAppleScript.errorMessage] as? String ?? "\(error)"))
        } else {
            completion(nil)
        }
    }

    // MARK: Terminal command (`claude-<slug>`)

    static func shellCommandURL(_ profile: Profile) -> URL {
        Prefs.commandsDir.appendingPathComponent(profile.shellCommandName)
    }

    static func isShellCommandInstalled(_ profile: Profile) -> Bool {
        guard let text = try? String(contentsOf: shellCommandURL(profile)) else { return false }
        return text.contains(managedMarker)
    }

    @discardableResult
    static func installShellCommand(_ profile: Profile, claudePath: String?) throws -> URL {
        let fm = FileManager.default
        let url = shellCommandURL(profile)
        if fm.fileExists(atPath: url.path), !isShellCommandInstalled(profile) {
            throw LaunchError.wouldOverwrite(url.path)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = ["#!/bin/sh", managedMarker, "# Runs Claude Code as the \"\(profile.name)\" profile."]
        if profile.usesDefaultCodeDir { lines.append("unset CLAUDE_CONFIG_DIR") }
        for (k, v) in profile.codeEnvironment { lines.append("export \(k)=\(Shell.quote(v))") }
        lines.append("export CLAUDE_MANAGER_PROFILE=\(Shell.quote(profile.name))")
        // Prefer the resolved binary but fall back to PATH if it moves (e.g. reinstall).
        if let claudePath {
            lines.append("CLAUDE_BIN=\(Shell.quote(claudePath))")
            lines.append("[ -x \"$CLAUDE_BIN\" ] || CLAUDE_BIN=claude")
        } else {
            lines.append("CLAUDE_BIN=claude")
        }
        lines.append("exec \"$CLAUDE_BIN\" \"$@\"")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static func removeShellCommand(_ profile: Profile) {
        if isShellCommandInstalled(profile) { try? FileManager.default.removeItem(at: shellCommandURL(profile)) }
    }

    // MARK: Dock launchers

    enum LauncherKind: String { case desktop, code }

    static func dockLauncherURL(_ profile: Profile, kind: LauncherKind) -> URL {
        let suffix = kind == .desktop ? "" : " Code"
        let safeName = profile.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return Paths.launchersDir.appendingPathComponent("Claude\(suffix) – \(safeName).app", isDirectory: true)
    }

    /// Builds a tiny .app you can pin to the Dock. Desktop launchers start Claude directly;
    /// Code launchers call back into Claude Manager so they honor the terminal preference.
    @discardableResult
    static func createDockLauncher(_ profile: Profile, kind: LauncherKind) throws -> URL {
        let fm = FileManager.default
        let app = dockLauncherURL(profile, kind: kind)
        let script: String
        switch kind {
        case .desktop:
            guard let claudeApp = Toolchain.desktopAppURL() else { throw LaunchError.desktopNotInstalled }
            var cmd = "exec /usr/bin/open -n -a \(Shell.quote(claudeApp.path))"
            if !profile.usesDefaultDesktopDir {
                cmd += " --args \(Shell.quote("--user-data-dir=\(profile.desktopDirURL.path)"))"
            }
            script = "#!/bin/sh\n\(managedMarker)\n\(cmd)\n"
        case .code:
            let manager = Bundle.main.executablePath ?? CommandLine.arguments[0]
            script = "#!/bin/sh\n\(managedMarker)\nexec \(Shell.quote(manager)) --launch-code \(Shell.quote(profile.id))\n"
        }

        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        let exe = macOS.appendingPathComponent("launch")
        try script.write(to: exe, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let plist: [String: Any] = [
            "CFBundleName": app.deletingPathExtension().lastPathComponent,
            "CFBundleDisplayName": app.deletingPathExtension().lastPathComponent,
            "CFBundleIdentifier": "local.claudemanager.launcher.\(kind.rawValue).\(profile.slug)",
            "CFBundleExecutable": "launch",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "LSUIElement": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let icon = IconRenderer.launcherIcon(profile: profile, kind: kind)
        NSWorkspace.shared.setIcon(icon, forFile: app.path, options: [])
        return app
    }

    static func removeDockLaunchers(_ profile: Profile) {
        for kind in [LauncherKind.desktop, .code] {
            let url = dockLauncherURL(profile, kind: kind)
            let exe = url.appendingPathComponent("Contents/MacOS/launch")
            if let text = try? String(contentsOf: exe), text.contains(managedMarker) {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        }
    }
}
