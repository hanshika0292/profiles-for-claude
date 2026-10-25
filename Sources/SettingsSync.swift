import Foundation

/// Copies or symlinks configuration between profiles without touching login state.
enum SettingsSync {
    enum Scope: String { case code = "Claude Code", desktop = "Claude Desktop" }
    enum Mode: String, CaseIterable, Identifiable {
        case copy = "Copy", link = "Link"
        var id: String { rawValue }
    }

    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let detail: String
        let scope: Scope
        /// Relative to the profile's Code or Desktop folder; nil for the MCP merge.
        let relativePath: String?
        var canLink: Bool { relativePath != nil }
    }

    static let mcpServersID = "code.mcpServers"

    /// Copied into a brand-new profile when "Start with my settings from Default" is on.
    /// Plugins and Desktop extensions are left out; they're larger and can be linked later.
    static let starterItemIDs: Set<String> = [
        "code.settings", "code.claudemd", "code.agents", "code.commands", "code.skills",
        "code.outputstyles", "code.keybindings", mcpServersID, "desktop.config",
    ]

    static let items: [Item] = [
        Item(id: "code.settings", title: "Settings", detail: "settings.json — permissions, hooks, model, statusline",
             scope: .code, relativePath: "settings.json"),
        Item(id: "code.claudemd", title: "Global instructions", detail: "CLAUDE.md", scope: .code, relativePath: "CLAUDE.md"),
        Item(id: "code.agents", title: "Subagents", detail: "agents/", scope: .code, relativePath: "agents"),
        Item(id: "code.commands", title: "Slash commands", detail: "commands/", scope: .code, relativePath: "commands"),
        Item(id: "code.skills", title: "Skills", detail: "skills/", scope: .code, relativePath: "skills"),
        Item(id: "code.outputstyles", title: "Output styles", detail: "output-styles/", scope: .code, relativePath: "output-styles"),
        Item(id: "code.keybindings", title: "Keybindings", detail: "keybindings.json", scope: .code, relativePath: "keybindings.json"),
        Item(id: "code.plugins", title: "Plugins", detail: "plugins/ — linking is recommended", scope: .code, relativePath: "plugins"),
        Item(id: mcpServersID, title: "MCP servers (user scope)", detail: "mcpServers in .claude.json — always merged, never linked",
             scope: .code, relativePath: nil),
        Item(id: "desktop.config", title: "MCP servers & app config", detail: "claude_desktop_config.json",
             scope: .desktop, relativePath: "claude_desktop_config.json"),
        Item(id: "desktop.extensions", title: "Desktop extensions", detail: "Claude Extensions/",
             scope: .desktop, relativePath: "Claude Extensions"),
        Item(id: "desktop.extsettings", title: "Extension settings", detail: "Claude Extensions Settings/",
             scope: .desktop, relativePath: "Claude Extensions Settings"),
        Item(id: "desktop.extregistry", title: "Extension registry", detail: "extensions-installations.json",
             scope: .desktop, relativePath: "extensions-installations.json"),
    ]

    static func root(_ profile: Profile, _ scope: Scope) -> URL {
        scope == .code ? profile.codeDirURL : profile.desktopDirURL
    }

    static func exists(_ item: Item, in profile: Profile) -> Bool {
        if item.id == mcpServersID { return !(mcpServers(profile)?.isEmpty ?? true) }
        guard let rel = item.relativePath else { return false }
        return FileManager.default.fileExists(atPath: root(profile, item.scope).appendingPathComponent(rel).path)
    }

    /// Applies the selection; anything already in the target is moved to the Trash first.
    /// Returns one human-readable line per item.
    static func apply(_ selected: [Item], from source: Profile, to target: Profile, mode: Mode) -> [String] {
        let fm = FileManager.default
        var report: [String] = []
        for item in selected {
            do {
                if item.id == mcpServersID {
                    let n = try mergeMCPServers(from: source, to: target)
                    report.append("✓ \(item.title): merged \(n) server\(n == 1 ? "" : "s")")
                    continue
                }
                guard let rel = item.relativePath else { continue }
                let src = root(source, item.scope).appendingPathComponent(rel)
                let dst = root(target, item.scope).appendingPathComponent(rel)
                guard fm.fileExists(atPath: src.path) else {
                    report.append("– \(item.title): not present in \(source.name)")
                    continue
                }
                if Paths.normalize(src.path) == Paths.normalize(dst.path) {
                    report.append("– \(item.title): already shared")
                    continue
                }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? dst.checkResourceIsReachable()) == true || isSymlink(dst) {
                    do { try fm.trashItem(at: dst, resultingItemURL: nil) } catch { try fm.removeItem(at: dst) }
                }
                if mode == .link {
                    try fm.createSymbolicLink(at: dst, withDestinationURL: src.resolvingSymlinksInPath())
                    report.append("✓ \(item.title): linked to \(source.name)")
                } else {
                    try fm.copyItem(at: src.resolvingSymlinksInPath(), to: dst)
                    report.append("✓ \(item.title): copied")
                }
            } catch {
                report.append("✗ \(item.title): \(error.localizedDescription)")
            }
        }
        return report
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func mcpServers(_ profile: Profile) -> [String: Any]? {
        guard let data = try? Data(contentsOf: profile.codeJSONURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["mcpServers"] as? [String: Any]
    }

    /// Merges only the `mcpServers` key so the target's account and project state are untouched.
    private static func mergeMCPServers(from source: Profile, to target: Profile) throws -> Int {
        guard let incoming = mcpServers(source), !incoming.isEmpty else { return 0 }
        let fm = FileManager.default
        let url = target.codeJSONURL
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LaunchError.failed("\(Paths.abbreviate(url.path)) isn't valid JSON; not modified.")
            }
            root = parsed
            let backup = url.appendingPathExtension("claude-manager-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        for (k, v) in incoming { servers[k] = v }
        root["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return incoming.count
    }
}
