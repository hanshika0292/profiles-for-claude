import SwiftUI

struct ProfileDetailView: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    @AppStorage("welcomeDismissed") private var welcomeDismissed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if profile.isDefault && model.profiles.count == 1 && !welcomeDismissed {
                    WelcomeCard { welcomeDismissed = true }
                }
                header
                DesktopCard(profile: profile)
                CodeCard(profile: profile)
                MaintenanceCard(profile: profile)
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ProfileQuickActions(profile: profile)
                } label: {
                    Label("Launch", systemImage: "play.circle")
                }
                .help("Quick launch")
                Button { model.editing = profile } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Edit profile")
            }
        }
        .onAppear {
            model.checkAccount(profile)
            model.refreshSizes(profile)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Avatar(profile: profile, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(profile.name).font(.title2.weight(.semibold))
                    if profile.isDefault {
                        Text("Built-in")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(profile.isDefault
                     ? "Your normal Claude login — ~/.claude and Claude Desktop's standard data folder."
                     : "Fully separate sign-in, settings, history and MCP servers.")
                    .foregroundStyle(.secondary)
                if !profile.accountLabel.isEmpty {
                    Label(profile.accountLabel, systemImage: "person.crop.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Edit…") { model.editing = profile }
        }
        .padding(.bottom, 4)
    }
}

struct WelcomeCard: View {
    @EnvironmentObject var model: AppModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "hand.wave.fill").foregroundStyle(.orange)
                Text("Welcome to Claude Manager").font(.headline)
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Hide")
            }
            step(1, "Default is the Claude you already use",
                 "Your current Claude Code and Claude Desktop sign-ins are here. Nothing was moved or changed.")
            step(2, "Add a profile for each extra account",
                 "Click + and name it, for example “Work”. Each profile has its own sign-in, settings and history.")
            step(3, "Open it and sign in once",
                 "Open Claude Desktop or start a Claude Code session from the profile and sign in. It stays signed in after that.")
            HStack(spacing: 12) {
                Button { model.showNewProfile = true } label: {
                    Label("Create a Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Hint("You can also launch any profile from the menu bar icon.")
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.25)))
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Hint(detail)
            }
        }
    }
}

// MARK: - Claude Desktop

struct DesktopCard: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    @State private var confirmSignIn = false

    var body: some View {
        let instances = model.desktopInstances(for: profile)
        let othersRunning = model.snapshot.desktop.count - instances.count
        Card(title: "Claude Desktop", systemImage: "macwindow") {
            if !instances.isEmpty { StatusPill(text: "Running") }
        } content: {
            if model.desktopAppURL == nil {
                Notice(systemImage: "exclamationmark.triangle.fill",
                       text: "Claude Desktop isn't installed on this Mac. Install it, then come back here to open it as this profile.") {
                    Link("Download", destination: URL(string: "https://claude.ai/download")!)
                }
            }

            HStack(spacing: 8) {
                if let running = instances.first {
                    Button { model.activate(running) } label: {
                        Label("Bring to Front", systemImage: "macwindow.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Quit") { for inst in instances { model.quit(inst) } }
                } else {
                    Button { model.openDesktop(profile) } label: {
                        Label("Open Claude Desktop", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(profile.color.color)
                    Button("Open for Sign-In…") {
                        if othersRunning > 0 { confirmSignIn = true } else { model.openDesktop(profile) }
                    }
                    .help("Quits other Claude Desktop windows first so a browser sign-in returns to this profile")
                }
                Spacer()
                Menu {
                    Button("Create Dock Icon") { model.createDockLauncher(profile, kind: .desktop) }
                    Button("Copy Terminal Command") { model.copy(model.desktopCommand(profile)) }
                    Divider()
                    Button("Show Data Folder in Finder") { model.reveal(profile.desktopDirURL) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .disabled(model.desktopAppURL == nil)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                InfoRow(label: "Data folder", value: Paths.abbreviate(profile.desktopDirURL.path), monospaced: true) {
                    Button("Show") { model.reveal(profile.desktopDirURL) }.buttonStyle(.link)
                }
                InfoRow(label: "Size", value: model.size(profile, "desktop"))
                InfoRow(label: "Last opened", value: Format.ago(profile.lastDesktopLaunch))
                if model.hasDockLauncher(profile, .desktop) {
                    InfoRow(label: "Dock icon", value: Paths.abbreviate(Launcher.dockLauncherURL(profile, kind: .desktop).path)) {
                        Button("Show") { model.reveal(Launcher.dockLauncherURL(profile, kind: .desktop)) }.buttonStyle(.link)
                    }
                }
            }

            Hint(profile.isDefault
                 ? "This is the Claude Desktop you'd get from the Dock. Other profiles open as separate copies next to it."
                 : "Opens a separate copy of Claude Desktop with its own sign-in, chats, settings and MCP servers. All copies share one Dock icon — make a Dock icon here to tell them apart. If you sign in with Google or SSO, use “Open for Sign-In” so the browser sends you back to this profile.")
        }
        .confirmationDialog("Quit other Claude Desktop windows?", isPresented: $confirmSignIn) {
            Button("Quit Others and Open “\(profile.name)”") { model.openDesktopForSignIn(profile) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Browser sign-in sends you back through a claude:// link, and macOS gives it to whichever Claude Desktop is running. Quit the other \(othersRunning == 1 ? "copy" : "\(othersRunning) copies") so the sign-in lands in “\(profile.name)”. You can reopen them afterwards.")
        }
    }
}

// MARK: - Claude Code

struct CodeCard: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    @State private var confirmSignOut = false
    @State private var sessionToStop: CodeSession?

    var body: some View {
        let sessions = model.codeSessions(for: profile)
        let account = model.account(for: profile)
        let terminal = Prefs.terminal.title
        Card(title: "Claude Code", systemImage: "terminal") {
            if !sessions.isEmpty { StatusPill(text: "\(sessions.count) running") }
        } content: {
            if model.claudePath == nil {
                Notice(systemImage: "exclamationmark.triangle.fill",
                       text: "The claude command wasn't found. Install Claude Code, or set its path in Settings.") {
                    Link("Install", destination: URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!)
                }
            }

            accountRow(account)

            HStack(spacing: 8) {
                Button { model.launchCode(profile) } label: {
                    Label("New Session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(profile.color.color)
                .help("Opens \(terminal) in \(Paths.abbreviate(profile.launchFolderURL.path))")
                Button { model.chooseFolderAndLaunch(profile) } label: {
                    Label("Choose Folder…", systemImage: "folder")
                }
                Spacer()
                Menu {
                    Button("Create Dock Icon") { model.createDockLauncher(profile, kind: .code) }
                    Button("Copy Launch Command") {
                        model.copy(Launcher.codeOneLiner(profile, folder: nil, claudePath: model.claudePath))
                    }
                    Divider()
                    Button("Show Config Folder in Finder") { model.reveal(profile.codeDirURL) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Hint("New sessions open in \(terminal), starting in \(Paths.abbreviate(profile.launchFolderURL.path)).")

            if !profile.recentFolders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent folders").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(profile.recentFolders, id: \.self) { path in
                            RecentFolderChip(profile: profile, path: path)
                        }
                    }
                }
            }

            if !sessions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Running sessions").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    ForEach(sessions) { session in
                        SessionRow(session: session) { sessionToStop = session }
                    }
                }
            }

            Divider()
            commandRow
            Divider()

            VStack(alignment: .leading, spacing: 7) {
                InfoRow(label: "Config folder", value: Paths.abbreviate(profile.codeDirURL.path), monospaced: true) {
                    Button("Show") { model.reveal(profile.codeDirURL) }.buttonStyle(.link)
                }
                InfoRow(label: "Size", value: model.size(profile, "code"))
                InfoRow(label: "Last session", value: Format.ago(profile.lastCodeLaunch))
                if !profile.codeArgs.isEmpty {
                    InfoRow(label: "Extra arguments", value: profile.codeArgs, monospaced: true)
                }
            }
        }
        .confirmationDialog("Sign out of Claude Code for “\(profile.name)”?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { model.signOut(profile) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only this profile is signed out. Its settings and history stay.")
        }
        .confirmationDialog("Stop this Claude Code session?",
                            isPresented: Binding(get: { sessionToStop != nil }, set: { if !$0 { sessionToStop = nil } }),
                            presenting: sessionToStop) { session in
            Button("Stop Session", role: .destructive) { model.stop(session) }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Claude Code in \(session.cwd.map(Paths.abbreviate) ?? "an unknown folder") will exit. Anything it's in the middle of will be interrupted.")
        }
    }

    @ViewBuilder
    private func accountRow(_ account: CodeAccount?) -> some View {
        let signedIn = account?.loggedIn == true
        HStack(spacing: 10) {
            Image(systemName: signedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.questionmark")
                .font(.system(size: 22))
                .foregroundStyle(signedIn ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(account?.summary ?? (model.claudePath == nil ? "Unknown" : "Checking…"))
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
                let details = [account?.plan.map { $0.capitalized }, account?.organization].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                } else if let error = account?.error {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if account?.loggedIn == false {
                    Text("Sign in once and this profile stays signed in.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.checking.contains(profile.id) {
                ProgressView().controlSize(.small)
            }
            Button { model.checkAccount(profile, force: true) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Check sign-in again")
            .disabled(model.claudePath == nil)
            if signedIn {
                Button("Sign Out…") { confirmSignOut = true }
            } else {
                Button("Sign In…") { model.signIn(profile) }
                    .help("Opens \(Prefs.terminal.title), signs this profile in, then starts Claude Code")
                    .disabled(model.claudePath == nil)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.07)))
    }

    private var commandRow: some View {
        let _ = model.diskRevision
        let installed = Launcher.isShellCommandInstalled(profile)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Terminal command").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Text(profile.shellCommandName)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12)))
                if installed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Installed")
                }
                Spacer()
                if installed {
                    Button("Copy") { model.copy(profile.shellCommandName) }
                    Button("Remove") { model.removeCommand(profile) }
                } else {
                    Button("Install") { model.installCommand(profile) }
                }
            }
            .font(.callout)
            Hint(installed
                 ? "Type \(profile.shellCommandName) in any terminal to run Claude Code as “\(profile.name)”. Arguments pass through, e.g. \(profile.shellCommandName) -c."
                 : "Adds \(profile.shellCommandName) to \(Paths.abbreviate(Prefs.commandsDir.path)) so you can start this profile from any terminal.")
            if model.commandsDirInPath == false {
                Hint("⚠︎ \(Paths.abbreviate(Prefs.commandsDir.path)) isn't on your shell's PATH. Change the folder in Settings or add it to PATH.")
            }
        }
    }
}

struct RecentFolderChip: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    let path: String

    var body: some View {
        Button { model.launchCode(profile, folder: URL(fileURLWithPath: path, isDirectory: true)) } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(profile.color.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1)
                    Text(Paths.abbreviate(URL(fileURLWithPath: path).deletingLastPathComponent().path))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.secondary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New session in \(Paths.abbreviate(path))")
        .contextMenu {
            Button("Show in Finder") { model.reveal(URL(fileURLWithPath: path)) }
            Button("Remove from Recents") { model.forgetRecentFolder(path, in: profile) }
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject var model: AppModel
    let session: CodeSession
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.viaDesktop ? "macwindow" : "terminal.fill")
                .foregroundStyle(.green)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.cwd.map(Paths.abbreviate) ?? "Unknown folder")
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                Text(verbatim: "\(session.viaDesktop ? "From Claude Desktop" : "Terminal") · started \(Format.ago(session.startedAt)) · PID \(session.pid)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let cwd = session.cwd {
                Button { model.reveal(URL(fileURLWithPath: cwd)) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Show folder in Finder")
            }
            Button(action: onStop) { Image(systemName: "stop.circle") }
                .buttonStyle(.borderless).help("Stop this session")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Maintenance

struct MaintenanceCard: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    @State private var confirmDelete = false

    var body: some View {
        let envKeys = profile.codeEnvironment.map(\.0).filter { $0 != "CLAUDE_CONFIG_DIR" }
        Card(title: "Maintenance", systemImage: "wrench.and.screwdriver") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share settings between profiles").font(.callout.weight(.medium))
                    Hint("Copy or link settings.json, CLAUDE.md, agents, commands, skills, plugins, MCP servers and Desktop extensions from another profile. Sign-ins are never copied.")
                }
                Spacer()
                Button("Copy From…") { model.syncTarget = profile }
                    .disabled(model.profiles.count < 2)
            }
            if !envKeys.isEmpty {
                InfoRow(label: "Extra env", value: envKeys.joined(separator: ", "), monospaced: true)
            }
            if !profile.isDefault {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delete profile").font(.callout.weight(.medium))
                        Hint("Removes it from Claude Manager along with its Dock icons and terminal command. You choose whether its data goes to the Trash.")
                    }
                    Spacer()
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .confirmationDialog("Delete “\(profile.name)”?", isPresented: $confirmDelete) {
            Button("Delete Profile, Keep Its Data") { model.delete(profile, trashData: false) }
            Button("Delete Profile and Move Data to Trash", role: .destructive) { model.delete(profile, trashData: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Data folders:\n\(Paths.abbreviate(profile.codeDirURL.path))\n\(Paths.abbreviate(profile.desktopDirURL.path))\n\nTo make Claude Code forget this profile's saved login too, sign out before deleting.")
        }
    }
}
