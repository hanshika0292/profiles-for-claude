import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(model.profiles) { profile in
            let desktop = model.desktopInstances(for: profile)
            let code = model.codeSessions(for: profile)
            Menu {
                Button(desktop.isEmpty ? "Open Claude Desktop" : "Show Claude Desktop") { model.openDesktop(profile) }
                    .disabled(model.desktopAppURL == nil)
                Divider()
                Button("New Code Session in \(folderName(profile.launchFolderURL.path))") { model.launchCode(profile) }
                ForEach(Array(profile.recentFolders.prefix(5)), id: \.self) { path in
                    Button("New Code Session in \(folderName(path))") {
                        model.launchCode(profile, folder: URL(fileURLWithPath: path, isDirectory: true))
                    }
                }
                Button("Choose Folder…") { model.chooseFolderAndLaunch(profile) }
                if !desktop.isEmpty {
                    Divider()
                    Button("Quit Claude Desktop") { for inst in desktop { model.quit(inst) } }
                }
                Divider()
                Button("Manage…") { showManager(selecting: profile.id) }
            } label: {
                Text(title(profile, desktop: desktop.count, code: code.count))
            }
        }
        Divider()
        Button("Open Claude Manager") { showManager(selecting: nil) }
        Button("New Profile…") {
            showManager(selecting: nil)
            model.showNewProfile = true
        }
        Button("Settings…") { model.openSettings() }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Claude Manager") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func title(_ p: Profile, desktop: Int, code: Int) -> String {
        var parts: [String] = []
        if desktop > 0 { parts.append("Desktop") }
        if code > 0 { parts.append("Code ×\(code)") }
        let status = parts.isEmpty ? "" : "   ● " + parts.joined(separator: ", ")
        return "\(p.initial)  \(p.name)\(status)"
    }

    private func folderName(_ path: String) -> String {
        path == Paths.home.path ? "Home" : URL(fileURLWithPath: path).lastPathComponent
    }

    private func showManager(selecting id: String?) {
        if let id { model.selection = id }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
