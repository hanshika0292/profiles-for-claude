import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 360)
        } detail: {
            if let profile = model.profile(model.selection) {
                ProfileDetailView(profile: profile)
                    .id(profile.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Select a profile").font(.title3).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $model.showNewProfile) {
            ProfileEditor(original: nil).environmentObject(model)
        }
        .sheet(item: $model.importDraft) { draft in
            ProfileEditor(original: nil, prefill: draft).environmentObject(model)
        }
        .sheet(item: $model.editing) { profile in
            ProfileEditor(original: profile).environmentObject(model)
        }
        .sheet(item: $model.syncTarget) { profile in
            SyncSheet(target: profile).environmentObject(model)
        }
        .alert(model.alert?.title ?? "",
               isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
               presenting: model.alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.appBecameActive()
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Profiles") {
                ForEach(model.profiles) { profile in
                    ProfileRow(profile: profile)
                        .tag(profile.id)
                        .contextMenu { ProfileQuickActions(profile: profile) }
                }
                .onMove { model.moveProfiles(from: $0, to: $1) }
            }
            let found = model.discovered
            if !found.isEmpty {
                Section("Found on this Mac") {
                    ForEach(found) { DiscoveredRow(item: $0) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { ToolchainFooter() }
        .toolbar {
            ToolbarItem {
                Button { model.showNewProfile = true } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .help("New profile (⌘N)")
            }
        }
    }
}

struct ProfileRow: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile

    var body: some View {
        let desktop = model.desktopInstances(for: profile).count
        let code = model.codeSessions(for: profile).count
        HStack(spacing: 10) {
            Avatar(profile: profile, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).fontWeight(.medium).lineLimit(1)
                Text(model.subtitle(for: profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if desktop > 0 {
                RunningBadge(systemImage: "macwindow", count: desktop).help("Claude Desktop is running")
            }
            if code > 0 {
                RunningBadge(systemImage: "terminal", count: code)
                    .help("\(code) Claude Code session\(code == 1 ? "" : "s") running")
            }
        }
        .padding(.vertical, 3)
    }
}

struct DiscoveredRow: View {
    @EnvironmentObject var model: AppModel
    let item: AppModel.Discovered

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .code ? "terminal" : "macwindow")
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.suggestedName).lineLimit(1)
                Text(Paths.abbreviate(item.path))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button("Import") { model.beginImport(item) }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .help("A running Claude \(item.kind == .code ? "Code session" : "Desktop") uses this folder, but no profile covers it yet.")
        .contextMenu {
            Button("Import as Profile…") { model.beginImport(item) }
            Button("Ignore") { model.ignore(item) }
        }
    }
}

/// Shared by the sidebar context menu and the detail toolbar.
struct ProfileQuickActions: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile

    var body: some View {
        Button(model.desktopInstances(for: profile).isEmpty ? "Open Claude Desktop" : "Show Claude Desktop") {
            model.openDesktop(profile)
        }
        .disabled(model.desktopAppURL == nil)
        Button("New Claude Code Session") { model.launchCode(profile) }
        Button("New Claude Code Session in Folder…") { model.chooseFolderAndLaunch(profile) }
        Divider()
        Button("Edit Profile…") { model.editing = profile }
        Button("Copy Settings From…") { model.syncTarget = profile }
    }
}

struct ToolchainFooter: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "terminal").frame(width: 14)
                if let v = model.claudeVersion {
                    Text("Claude Code \(v)")
                } else if model.claudePath == nil {
                    Text("Claude Code not found").foregroundStyle(.orange)
                } else {
                    Text("Claude Code")
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "macwindow").frame(width: 14)
                if model.desktopAppURL == nil {
                    Text("Claude Desktop not installed")
                    Link("Get", destination: URL(string: "https://claude.ai/download")!)
                } else {
                    Text("Claude Desktop \(model.desktopVersion ?? "")")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
