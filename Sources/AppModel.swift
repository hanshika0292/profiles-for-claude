import AppKit
import SwiftUI

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// profiles.json reader/writer, shared with the headless launcher mode.
enum ProfileFile {
    private struct Format: Codable {
        var version = 1
        var profiles: [Profile]
    }

    static func load() -> [Profile] {
        var profiles: [Profile] = []
        if let data = try? Data(contentsOf: Paths.profilesFile) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let file = try? decoder.decode(Format.self, from: data) {
                profiles = file.profiles
            } else {
                // Keep the unreadable file instead of silently overwriting it on next save.
                let stamp = Int(Date().timeIntervalSince1970)
                try? FileManager.default.copyItem(at: Paths.profilesFile,
                                                  to: Paths.profilesFile.appendingPathExtension("unreadable-\(stamp)"))
            }
        }
        if !profiles.contains(where: \.isDefault) { profiles.insert(.makeDefault(), at: 0) }
        return profiles
    }

    static func save(_ profiles: [Profile]) throws {
        try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Format(profiles: profiles)).write(to: Paths.profilesFile, options: .atomic)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var selection: String? = Profile.defaultID
    @Published private(set) var snapshot = ProcessScanner.Snapshot()
    @Published private var cachedAccounts: [String: CodeAccount] = [:]
    @Published private var verifiedAccounts: [String: CodeAccount] = [:]
    @Published private(set) var checking: Set<String> = []
    /// Bytes per "<id>.code" / "<id>.desktop"; -1 when the folder doesn't exist yet.
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published var alert: AlertMessage?
    @Published var showNewProfile = false
    @Published var editing: Profile?
    @Published var syncTarget: Profile?
    /// A prefilled new profile for a folder found in use by a running Claude.
    @Published var importDraft: Profile?
    @Published private var ignoredFolders: [String] = UserDefaults.standard.stringArray(forKey: "ignoredFolders") ?? []
    @Published private(set) var claudePath: String?
    @Published private(set) var claudeVersion: String?
    @Published private(set) var desktopAppURL: URL?
    @Published private(set) var desktopVersion: String?
    @Published private(set) var commandsDirInPath: Bool?
    /// Bumped to make views re-read on-disk state (installed commands, launchers).
    @Published private(set) var diskRevision = 0

    private var timer: Timer?
    private var scanning = false
    private var observers: [NSObjectProtocol] = []

    init() {
        profiles = ProfileFile.load()
        refreshToolchain()
        refreshProcesses()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshProcesses() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshProcesses() }
            })
        }
    }

    // MARK: Profiles

    func profile(_ id: String?) -> Profile? { profiles.first { $0.id == id } }

    private func save() {
        do { try ProfileFile.save(profiles) } catch { show("Couldn't save profiles", error) }
    }

    func uniqueSlug(_ base: String, excluding id: String? = nil) -> String {
        let taken = Set(profiles.filter { $0.id != id }.map(\.slug))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    func create(_ profile: Profile, copySettingsFrom source: Profile? = nil) {
        try? FileManager.default.createDirectory(at: profile.codeDirURL, withIntermediateDirectories: true)
        profiles.append(profile)
        save()
        selection = profile.id
        refreshCachedAccounts()
        guard let source else { return }
        let items = SettingsSync.items.filter { SettingsSync.starterItemIDs.contains($0.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            let available = items.filter { SettingsSync.exists($0, in: source) }
            let failures = SettingsSync.apply(available, from: source, to: profile, mode: .copy).filter { $0.hasPrefix("✗") }
            Task { @MainActor in
                self.refreshSizes(profile)
                if !failures.isEmpty {
                    self.alert = AlertMessage(title: "Some settings weren't copied", message: failures.joined(separator: "\n"))
                }
            }
        }
    }

    // MARK: Discovery

    struct Discovered: Identifiable, Hashable {
        enum Kind: String { case code, desktop }
        let kind: Kind
        let path: String
        var id: String { "\(kind.rawValue):\(path)" }

        /// "~/.claude-work" → "Work", ".../Claude-Personal" → "Personal".
        var suggestedName: String {
            var name = URL(fileURLWithPath: path).lastPathComponent
            while name.hasPrefix(".") { name.removeFirst() }
            for prefix in ["claude-", "claude_", "claude"] where name.lowercased().hasPrefix(prefix) && name.count > prefix.count {
                name = String(name.dropFirst(prefix.count))
                break
            }
            name = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            return name.isEmpty ? "Imported" : name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    /// Folders a running Claude Code session or Desktop copy is using that no profile covers.
    var discovered: [Discovered] {
        let covered = Set(profiles.flatMap { [Paths.normalize($0.codeDirURL.path), Paths.normalize($0.desktopDirURL.path)] })
        let skip = covered.union(ignoredFolders)
        let temp = Paths.normalize(NSTemporaryDirectory())
        var seen = Set<String>()
        var found: [Discovered] = []
        let candidates = snapshot.code.compactMap { $0.configDir.map { (Discovered.Kind.code, $0) } }
            + snapshot.desktop.compactMap { $0.userDataDir.map { (Discovered.Kind.desktop, $0) } }
        for (kind, dir) in candidates {
            let path = Paths.normalize(dir)
            guard !skip.contains(path), !path.hasPrefix(temp), seen.insert(path).inserted else { continue }
            found.append(Discovered(kind: kind, path: path))
        }
        return found
    }

    func beginImport(_ item: Discovered) {
        let path = Paths.abbreviate(item.path)
        importDraft = Profile(name: item.suggestedName, slug: "", emoji: "📥",
                              color: ProfileColor.allCases.filter { $0 != .orange }.randomElement() ?? .blue,
                              codeConfigDir: item.kind == .code ? path : "",
                              desktopDataDir: item.kind == .desktop ? path : "")
    }

    func ignore(_ item: Discovered) {
        ignoredFolders.append(item.path)
        UserDefaults.standard.set(ignoredFolders, forKey: "ignoredFolders")
    }

    /// Saves edits and regenerates anything that embeds the profile's paths or env.
    func update(_ profile: Profile, previous: Profile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[i] = profile
        save()
        if !profile.usesDefaultCodeDir {
            try? FileManager.default.createDirectory(at: profile.codeDirURL, withIntermediateDirectories: true)
        }
        if Launcher.isShellCommandInstalled(previous) {
            _ = try? Launcher.installShellCommand(profile, claudePath: claudePath)
        }
        let launchers = [Launcher.LauncherKind.desktop, .code].filter { hasDockLauncher(previous, $0) }
        if !launchers.isEmpty {
            Launcher.removeDockLaunchers(previous)
            for kind in launchers { _ = try? Launcher.createDockLauncher(profile, kind: kind) }
        }
        verifiedAccounts[profile.id] = nil
        refreshCachedAccounts()
        diskRevision += 1
    }

    func delete(_ profile: Profile, trashData: Bool) {
        guard !profile.isDefault else { return }
        if !desktopInstances(for: profile).isEmpty || !codeSessions(for: profile).isEmpty {
            alert = AlertMessage(title: "“\(profile.name)” is still running",
                                 message: "Quit its Claude Desktop window and Claude Code sessions first.")
            return
        }
        Launcher.removeShellCommand(profile)
        Launcher.removeDockLaunchers(profile)
        if trashData {
            let protected = [Paths.defaultCodeDir, Paths.defaultDesktopDir, Paths.home].map { Paths.normalize($0.path) }
            let shared = profiles.filter { $0.id != profile.id }
                .flatMap { [Paths.normalize($0.codeDirURL.path), Paths.normalize($0.desktopDirURL.path)] }
            for url in [profile.codeDirURL, profile.desktopDirURL] {
                let p = Paths.normalize(url.path)
                guard !protected.contains(p), !shared.contains(p), FileManager.default.fileExists(atPath: url.path) else { continue }
                do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch {
                    show("Couldn't move \(Paths.abbreviate(url.path)) to the Trash", error)
                }
            }
        }
        profiles.removeAll { $0.id == profile.id }
        save()
        selection = Profile.defaultID
    }

    func moveProfiles(from source: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func modify(_ id: String, _ change: (inout Profile) -> Void) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&profiles[i])
        save()
    }

    func forgetRecentFolder(_ path: String, in profile: Profile) {
        modify(profile.id) { $0.recentFolders.removeAll { $0 == path } }
    }

    // MARK: Running instances

    func refreshProcesses() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let snap = ProcessScanner.scan()
            Task { @MainActor in
                self.scanning = false
                if snap != self.snapshot { self.snapshot = snap }
            }
        }
    }

    func desktopInstances(for profile: Profile) -> [DesktopInstance] {
        let target = Paths.normalize(profile.desktopDirURL.path)
        return snapshot.desktop.filter { inst in
            guard let dir = inst.userDataDir else { return profile.usesDefaultDesktopDir }
            return Paths.normalize(dir) == target
        }
    }

    func codeSessions(for profile: Profile) -> [CodeSession] {
        let target = Paths.normalize(profile.codeDirURL.path)
        return snapshot.code.filter { session in
            guard let dir = session.configDir else { return profile.usesDefaultCodeDir }
            return Paths.normalize(dir) == target
        }
    }

    // MARK: Accounts

    func account(for profile: Profile) -> CodeAccount? {
        verifiedAccounts[profile.id] ?? cachedAccounts[profile.id]
    }

    func subtitle(for profile: Profile) -> String {
        if let email = account(for: profile)?.email { return email }
        if !profile.accountLabel.isEmpty { return profile.accountLabel }
        if account(for: profile)?.loggedIn == false { return "Not signed in" }
        return profile.isDefault ? "Your existing Claude login" : "No account yet"
    }

    func refreshCachedAccounts() {
        let list = profiles
        DispatchQueue.global(qos: .utility).async {
            var found: [String: CodeAccount] = [:]
            for p in list { if let a = AccountReader.cached(p) { found[p.id] = a } }
            let result = found
            Task { @MainActor in self.cachedAccounts = result }
        }
    }

    func checkAccount(_ profile: Profile, force: Bool = false) {
        guard let claude = claudePath, !checking.contains(profile.id) else { return }
        if !force, let v = verifiedAccounts[profile.id], Date().timeIntervalSince(v.checkedAt) < 300 { return }
        checking.insert(profile.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AccountReader.status(profile, claudePath: claude)
            let cached = AccountReader.cached(profile)
            Task { @MainActor in
                self.checking.remove(profile.id)
                self.verifiedAccounts[profile.id] = result
                self.cachedAccounts[profile.id] = cached
            }
        }
    }

    func signIn(_ profile: Profile) {
        launchCode(profile, arguments: "auth login", startSessionAfter: true)
    }

    func signOut(_ profile: Profile) {
        guard let claude = claudePath else { return }
        checking.insert(profile.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountReader.logout(profile, claudePath: claude)
            Task { @MainActor in
                self.checking.remove(profile.id)
                if !r.ok { self.alert = AlertMessage(title: "Sign out failed", message: r.stderr.isEmpty ? r.stdout : r.stderr) }
                self.checkAccount(profile, force: true)
            }
        }
    }

    /// Re-check after the user comes back from a browser/terminal sign-in.
    func appBecameActive() {
        refreshProcesses()
        if let p = profile(selection) {
            let last = verifiedAccounts[p.id]?.checkedAt ?? .distantPast
            if Date().timeIntervalSince(last) > 10 { checkAccount(p, force: true) }
        }
    }

    // MARK: Toolchain & disk

    func refreshToolchain() {
        desktopAppURL = Toolchain.desktopAppURL()
        desktopVersion = desktopAppURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        let commandsDir = Paths.normalize(Prefs.commandsDir.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let path = Toolchain.claudePath()
            let version = path.flatMap(Toolchain.claudeVersion)
            let inPath = Toolchain.loginPATH.split(separator: ":").contains { Paths.normalize(String($0)) == commandsDir }
            Task { @MainActor in
                self.claudePath = path
                self.claudeVersion = version
                self.commandsDirInPath = inPath
                self.refreshCachedAccounts()
                if let p = self.profile(self.selection) { self.checkAccount(p) }
            }
        }
    }

    func refreshSizes(_ profile: Profile) {
        let code = profile.codeDirURL, desktop = profile.desktopDirURL, id = profile.id
        DispatchQueue.global(qos: .utility).async {
            let c = DiskUsage.size(of: code) ?? -1
            let d = DiskUsage.size(of: desktop) ?? -1
            Task { @MainActor in
                self.sizes["\(id).code"] = c
                self.sizes["\(id).desktop"] = d
            }
        }
    }

    func size(_ profile: Profile, _ kind: String) -> String {
        guard let v = sizes["\(profile.id).\(kind)"] else { return "Calculating…" }
        return v < 0 ? "Not created yet" : DiskUsage.format(v)
    }

    func hasDockLauncher(_ profile: Profile, _ kind: Launcher.LauncherKind) -> Bool {
        FileManager.default.fileExists(atPath: Launcher.dockLauncherURL(profile, kind: kind).path)
    }

    // MARK: Claude Desktop actions

    func openDesktop(_ profile: Profile) {
        if let running = desktopInstances(for: profile).first { return activate(running) }
        Launcher.openDesktop(profile) { [weak self] error in
            guard let self else { return }
            if let error { return self.show("Couldn't open Claude Desktop", error) }
            self.modify(profile.id) { $0.lastDesktopLaunch = Date() }
            self.refreshProcesses()
        }
    }

    /// Browser-based sign-in returns through the claude:// URL scheme, which macOS delivers
    /// to an arbitrary running instance. Quitting the others first makes it land here.
    func openDesktopForSignIn(_ profile: Profile) {
        let mine = Set(desktopInstances(for: profile).map(\.pid))
        let others = snapshot.desktop.filter { !mine.contains($0.pid) }
        for inst in others { quit(inst) }
        Task {
            for _ in 0..<40 where others.contains(where: { kill($0.pid, 0) == 0 }) {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            self.openDesktop(profile)
        }
    }

    func activate(_ instance: DesktopInstance) {
        NSRunningApplication(processIdentifier: instance.pid)?.activate(options: [.activateIgnoringOtherApps])
    }

    func quit(_ instance: DesktopInstance) {
        NSRunningApplication(processIdentifier: instance.pid)?.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refreshProcesses() }
    }

    func desktopCommand(_ profile: Profile) -> String {
        let app = desktopAppURL?.path ?? "/Applications/Claude.app"
        var cmd = "open -n -a \(Shell.quote(app))"
        if !profile.usesDefaultDesktopDir { cmd += " --args \(Shell.quote("--user-data-dir=\(profile.desktopDirURL.path)"))" }
        return cmd
    }

    // MARK: Claude Code actions

    func launchCode(_ profile: Profile, folder: URL? = nil, arguments: String? = nil, startSessionAfter: Bool = false) {
        let dir = folder ?? profile.launchFolderURL
        Launcher.launchCode(profile, folder: dir, claudePath: claudePath, arguments: arguments,
                            startSessionAfter: startSessionAfter) { [weak self] error in
            guard let self else { return }
            if let error { return self.show("Couldn't start Claude Code", error) }
            guard arguments == nil else { return }
            self.modify(profile.id) { p in
                p.lastCodeLaunch = Date()
                if dir.path != Paths.home.path {
                    p.recentFolders.removeAll { $0 == dir.path }
                    p.recentFolders.insert(dir.path, at: 0)
                    p.recentFolders = Array(p.recentFolders.prefix(8))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refreshProcesses() }
        }
    }

    func chooseFolderAndLaunch(_ profile: Profile) {
        let start = profile.recentFolders.first.map { URL(fileURLWithPath: $0) } ?? profile.launchFolderURL
        if let url = chooseFolder(prompt: "Start Claude Code", start: start) { launchCode(profile, folder: url) }
    }

    func chooseFolder(prompt: String, start: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        panel.directoryURL = start
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    func stop(_ session: CodeSession) {
        kill(session.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshProcesses() }
    }

    func updateClaudeCode() {
        guard let p = profile(Profile.defaultID) else { return }
        launchCode(p, folder: Paths.home, arguments: "update")
    }

    func installCommand(_ profile: Profile) {
        do {
            try Launcher.installShellCommand(profile, claudePath: claudePath)
            diskRevision += 1
        } catch { show("Couldn't install \(profile.shellCommandName)", error) }
    }

    func removeCommand(_ profile: Profile) {
        Launcher.removeShellCommand(profile)
        diskRevision += 1
    }

    func createDockLauncher(_ profile: Profile, kind: Launcher.LauncherKind) {
        do {
            let url = try Launcher.createDockLauncher(profile, kind: kind)
            diskRevision += 1
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { show("Couldn't create the Dock icon", error) }
    }

    // MARK: Utilities

    func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            alert = AlertMessage(title: "Folder not created yet",
                                 message: "\(Paths.abbreviate(url.path)) is created the first time this profile is used.")
        }
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 14 ignores showSettingsWindow: and SettingsLink needs the macOS 14 SDK,
        // so trigger the app menu's own Settings… item instead.
        if let menu = NSApp.mainMenu?.items.first?.submenu,
           let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) {
            menu.performActionForItem(at: index)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func show(_ title: String, _ error: Error) {
        alert = AlertMessage(title: title, message: error.localizedDescription)
    }
}
