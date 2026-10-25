import Foundation

/// Well-known locations used by Claude Code, Claude Desktop and this app.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Claude Manager's own state (profiles.json, temp launch scripts).
    static let appSupport = home.appendingPathComponent("Library/Application Support/Claude Manager", isDirectory: true)
    static let profilesFile = appSupport.appendingPathComponent("profiles.json")
    static let runDir = appSupport.appendingPathComponent("run", isDirectory: true)

    /// Claude Code defaults: config lives in ~/.claude, account state in ~/.claude.json.
    static let defaultCodeDir = home.appendingPathComponent(".claude", isDirectory: true)
    static let defaultCodeJSON = home.appendingPathComponent(".claude.json")

    /// Claude Desktop (Electron) default userData folder.
    static let defaultDesktopDir = home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)

    /// Where new profiles get their isolated folders. The Code root has no spaces on purpose,
    /// because hooks and plugins sometimes splice CLAUDE_CONFIG_DIR into shell commands unquoted.
    static let profilesCodeRoot = home.appendingPathComponent(".claude-profiles", isDirectory: true)
    static let profilesDesktopRoot = appSupport.appendingPathComponent("Desktop", isDirectory: true)

    /// Generated Dock launcher apps.
    static let launchersDir = home.appendingPathComponent("Applications/Claude Manager", isDirectory: true)

    static func expand(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed as NSString).expandingTildeInPath
    }

    static func abbreviate(_ path: String) -> String {
        let h = home.path
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }

    /// Canonical form used to compare a running process's folder with a profile's folder.
    static func normalize(_ path: String) -> String {
        var p = URL(fileURLWithPath: expand(path)).standardizedFileURL.resolvingSymlinksInPath().path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
