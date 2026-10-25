import Foundation

/// What we know about a profile's Claude Code login.
struct CodeAccount: Equatable {
    var loggedIn: Bool?
    var email: String?
    var organization: String?
    var plan: String?
    var method: String?
    var checkedAt = Date()
    var error: String?

    var summary: String {
        if loggedIn == false { return "Not signed in" }
        if let email { return email }
        if loggedIn == true { return method.map { "Signed in (\($0))" } ?? "Signed in" }
        return "Unknown"
    }
}

enum AccountReader {
    /// Fast path: the account Claude Code cached in .claude.json at last login.
    static func cached(_ profile: Profile) -> CodeAccount? {
        guard let data = try? Data(contentsOf: profile.codeJSONURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let oauth = root["oauthAccount"] as? [String: Any] else {
            return CodeAccount(loggedIn: nil)
        }
        return CodeAccount(loggedIn: true,
                           email: oauth["emailAddress"] as? String,
                           organization: oauth["organizationName"] as? String)
    }

    /// Authoritative: `claude auth status --json` run with the profile's environment.
    static func status(_ profile: Profile, claudePath: String) -> CodeAccount {
        let r = Shell.run(claudePath, ["auth", "status", "--json"],
                          environment: Toolchain.subprocessEnvironment(profile.codeEnvironment), timeout: 25)
        let text = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "{"),
              let data = String(text[start...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            let message = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("not logged in") || message.localizedCaseInsensitiveContains("not signed in") {
                return CodeAccount(loggedIn: false)
            }
            var fallback = cached(profile) ?? CodeAccount()
            fallback.error = message.isEmpty ? "claude auth status exited with \(r.status)" : String(message.prefix(300))
            return fallback
        }
        var account = CodeAccount()
        account.loggedIn = find(json, ["loggedIn", "logged_in", "isLoggedIn", "authenticated"]) as? Bool
        account.email = find(json, ["email", "emailAddress", "email_address"]) as? String
        account.organization = find(json, ["orgName", "organizationName", "organization_name", "organization"]) as? String
        account.plan = find(json, ["subscriptionType", "subscription", "plan", "planType"]) as? String
        account.method = find(json, ["authMethod", "auth_method", "method", "apiKeySource"]) as? String
        if account.loggedIn == nil { account.loggedIn = account.email != nil ? true : (r.ok ? nil : false) }
        return account
    }

    /// Depth-first lookup of the first matching key, so we don't depend on the exact JSON shape.
    private static func find(_ value: Any, _ keys: [String]) -> Any? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let hit = dict.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value,
                   !(hit is [String: Any]), !(hit is NSNull) {
                    return hit
                }
            }
            for nested in dict.values {
                if let hit = find(nested, keys) { return hit }
            }
        } else if let array = value as? [Any] {
            for nested in array { if let hit = find(nested, keys) { return hit } }
        }
        return nil
    }

    static func logout(_ profile: Profile, claudePath: String) -> Shell.Result {
        Shell.run(claudePath, ["auth", "logout"],
                  environment: Toolchain.subprocessEnvironment(profile.codeEnvironment), timeout: 25)
    }
}

enum DiskUsage {
    static func size(of url: URL) -> Int64? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return nil }
        for case let file as URL in e {
            guard let v = try? file.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func format(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
