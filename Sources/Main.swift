import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        InheritedEnvironment.scrubCurrentProcess()
        if HeadlessMode.handle(CommandLine.arguments) { return }
        ClaudeManagerApp.main()
    }
}

struct ClaudeManagerApp: App {
    @StateObject private var model = AppModel()
    @AppStorage(Prefs.showMenuBarKey) private var showMenuBar = true

    var body: some Scene {
        Window("Claude Manager", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 880, minHeight: 600)
        }
        .defaultSize(width: 1060, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Profile…") { model.showNewProfile = true }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .appInfo) {
                Button("Update Claude Code…") { model.updateClaudeCode() }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }

        MenuBarExtra("Claude Manager", systemImage: "square.stack.3d.up.fill", isInserted: $showMenuBar) {
            MenuBarContent()
                .environmentObject(model)
        }
    }
}

/// `ClaudeManager --launch-code <profile> [--folder <path>]` and `--launch-desktop <profile>`
/// let Dock launchers and scripts start sessions without opening the manager window.
enum HeadlessMode {
    static func handle(_ args: [String]) -> Bool {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }

        if let dir = value(after: "--render-app-icon") {
            do { try IconRenderer.writeAppIconset(to: URL(fileURLWithPath: dir)) } catch { fail(error.localizedDescription) }
            exit(0)
        }

        if args.contains("--list-running") {
            listRunning()
            exit(0)
        }

        let codeID = value(after: "--launch-code")
        let desktopID = value(after: "--launch-desktop")
        guard let wanted = codeID ?? desktopID else { return false }
        guard let profile = ProfileFile.load().first(where: { $0.id == wanted || $0.slug == wanted }) else {
            fail("No Claude Manager profile named “\(wanted)”.")
        }

        var finished = false
        var failure: Error?
        let done: (Error?) -> Void = { failure = $0; finished = true }
        if codeID != nil {
            let folder = value(after: "--folder").map { URL(fileURLWithPath: Paths.expand($0), isDirectory: true) }
            Launcher.launchCode(profile, folder: folder ?? profile.launchFolderURL,
                                claudePath: Toolchain.claudePath(), completion: done)
        } else {
            Launcher.openDesktop(profile, completion: done)
        }
        let deadline = Date().addingTimeInterval(20)
        while !finished && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        if let failure { fail(failure.localizedDescription) }
        exit(0)
    }

    /// Prints what the manager would show as running, grouped by profile.
    private static func listRunning() {
        let profiles = ProfileFile.load()
        let snap = ProcessScanner.scan()
        func owner(_ dir: String?, _ keyPath: KeyPath<Profile, URL>, _ isDefault: KeyPath<Profile, Bool>) -> String {
            let match = profiles.first { p in
                guard let dir else { return p[keyPath: isDefault] }
                return Paths.normalize(dir) == Paths.normalize(p[keyPath: keyPath].path)
            }
            return match?.name ?? "(unmanaged: \(dir.map(Paths.abbreviate) ?? "?"))"
        }
        print("Claude Desktop:")
        if snap.desktop.isEmpty { print("  none") }
        for d in snap.desktop {
            print("  pid \(d.pid)  \(owner(d.userDataDir, \.desktopDirURL, \.usesDefaultDesktopDir))")
        }
        print("Claude Code:")
        if snap.code.isEmpty { print("  none") }
        for c in snap.code {
            let cwd = c.cwd.map(Paths.abbreviate) ?? "?"
            print("  pid \(c.pid)  \(owner(c.configDir, \.codeDirURL, \.usesDefaultCodeDir))  \(cwd)\(c.viaDesktop ? "  [desktop]" : "")")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        // Dock launchers have no terminal, so surface the problem visibly too.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Claude Manager"
        alert.informativeText = message
        alert.runModal()
        exit(1)
    }
}
