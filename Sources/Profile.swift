import Foundation
import AppKit
import SwiftUI

/// One identity: an isolated Claude Code config folder plus an isolated Claude Desktop data folder.
/// The built-in "default" profile maps to the stock locations so existing logins keep working.
struct Profile: Identifiable, Codable, Hashable {
    static let defaultID = "default"

    var id: String
    var name: String
    var slug: String
    var emoji: String
    var color: ProfileColor
    /// Free-form label, e.g. the email used to sign in to Desktop (Desktop doesn't expose it).
    var accountLabel: String
    /// Empty for the default profile, which means "don't set CLAUDE_CONFIG_DIR".
    var codeConfigDir: String
    /// Empty for the default profile, which means "don't pass --user-data-dir".
    var desktopDataDir: String
    /// KEY=VALUE per line, exported before `claude` runs.
    var extraEnv: String
    /// Shell fragment appended to every `claude` launch, e.g. `--model opus`.
    var codeArgs: String
    var defaultFolder: String
    var recentFolders: [String]
    var lastCodeLaunch: Date?
    var lastDesktopLaunch: Date?

    var isDefault: Bool { id == Profile.defaultID }

    init(id: String = UUID().uuidString, name: String, slug: String, emoji: String, color: ProfileColor,
         accountLabel: String = "", codeConfigDir: String, desktopDataDir: String, extraEnv: String = "",
         codeArgs: String = "", defaultFolder: String = "", recentFolders: [String] = []) {
        self.id = id
        self.name = name
        self.slug = slug
        self.emoji = emoji
        self.color = color
        self.accountLabel = accountLabel
        self.codeConfigDir = codeConfigDir
        self.desktopDataDir = desktopDataDir
        self.extraEnv = extraEnv
        self.codeArgs = codeArgs
        self.defaultFolder = defaultFolder
        self.recentFolders = recentFolders
    }

    static func makeDefault() -> Profile {
        Profile(id: defaultID, name: "Default", slug: "default", emoji: "⭐️", color: .orange,
                codeConfigDir: "", desktopDataDir: "")
    }

    // Tolerant decoding so older profiles.json files keep loading as fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? Profile.slugify(name)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        color = try c.decodeIfPresent(ProfileColor.self, forKey: .color) ?? .blue
        accountLabel = try c.decodeIfPresent(String.self, forKey: .accountLabel) ?? ""
        codeConfigDir = try c.decodeIfPresent(String.self, forKey: .codeConfigDir) ?? ""
        desktopDataDir = try c.decodeIfPresent(String.self, forKey: .desktopDataDir) ?? ""
        extraEnv = try c.decodeIfPresent(String.self, forKey: .extraEnv) ?? ""
        codeArgs = try c.decodeIfPresent(String.self, forKey: .codeArgs) ?? ""
        defaultFolder = try c.decodeIfPresent(String.self, forKey: .defaultFolder) ?? ""
        recentFolders = try c.decodeIfPresent([String].self, forKey: .recentFolders) ?? []
        lastCodeLaunch = try c.decodeIfPresent(Date.self, forKey: .lastCodeLaunch)
        lastDesktopLaunch = try c.decodeIfPresent(Date.self, forKey: .lastDesktopLaunch)
    }

    // MARK: Resolved locations

    var codeDirURL: URL {
        isDefault || codeConfigDir.isEmpty
            ? Paths.defaultCodeDir
            : URL(fileURLWithPath: Paths.expand(codeConfigDir), isDirectory: true)
    }

    /// Claude Code keeps account + user-scoped MCP servers here.
    var codeJSONURL: URL {
        isDefault || codeConfigDir.isEmpty ? Paths.defaultCodeJSON : codeDirURL.appendingPathComponent(".claude.json")
    }

    var desktopDirURL: URL {
        isDefault || desktopDataDir.isEmpty
            ? Paths.defaultDesktopDir
            : URL(fileURLWithPath: Paths.expand(desktopDataDir), isDirectory: true)
    }

    var usesDefaultCodeDir: Bool { isDefault || codeConfigDir.isEmpty }
    var usesDefaultDesktopDir: Bool { isDefault || desktopDataDir.isEmpty }

    var launchFolderURL: URL {
        defaultFolder.isEmpty ? Paths.home : URL(fileURLWithPath: Paths.expand(defaultFolder), isDirectory: true)
    }

    /// Environment for `claude`, in the order it should be exported.
    var codeEnvironment: [(String, String)] {
        var env: [(String, String)] = []
        if !usesDefaultCodeDir { env.append(("CLAUDE_CONFIG_DIR", codeDirURL.path)) }
        for line in extraEnv.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            var key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("export ") { key = String(key.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == value.last, f == "\"" || f == "'" {
                value = String(value.dropFirst().dropLast())
            }
            env.append((key, value))
        }
        return env
    }

    var shellCommandName: String { "claude-\(slug)" }

    var initial: String {
        if !emoji.isEmpty { return emoji }
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    static func slugify(_ name: String) -> String {
        let lowered = name.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        var out = ""
        for ch in lowered {
            if ch.isLetter && ch.isASCII || ch.isNumber && ch.isASCII { out.append(ch) }
            else if !out.hasSuffix("-") { out.append("-") }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "profile" : String(trimmed.prefix(32))
    }
}

enum ProfileColor: String, Codable, CaseIterable, Identifiable {
    case orange, red, pink, purple, indigo, blue, teal, green, yellow, gray

    var id: String { rawValue }

    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        switch self {
        case .orange: return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        case .red: return .systemRed
        case .pink: return .systemPink
        case .purple: return .systemPurple
        case .indigo: return .systemIndigo
        case .blue: return .systemBlue
        case .teal: return .systemTeal
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .gray: return .systemGray
        }
    }
}
