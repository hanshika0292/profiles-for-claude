import SwiftUI

struct SyncSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: Profile
    @State private var sourceID: String = ""
    @State private var mode: SettingsSync.Mode = .copy
    @State private var selected: Set<String> = []
    @State private var report: [String]?

    private var sources: [Profile] { model.profiles.filter { $0.id != target.id } }
    private var source: Profile? { model.profile(sourceID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bring settings into “\(target.name)”").font(.title3.weight(.semibold))
                Hint("Anything this replaces in “\(target.name)” goes to the Trash first. Sign-ins and chat history are never copied.")
            }
            .padding(20)

            Form {
                Picker("From", selection: $sourceID) {
                    ForEach(sources) { p in Text("\(p.initial)  \(p.name)").tag(p.id) }
                }
                Picker("Mode", selection: $mode) {
                    ForEach(SettingsSync.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Hint(mode == .copy
                     ? "Copy makes an independent snapshot. Later edits in one profile don't affect the other."
                     : "Link makes a symlink, so both profiles share one file. Edit it once and every linked profile sees the change.")

                if let source {
                    ForEach([SettingsSync.Scope.code, .desktop], id: \.self) { scope in
                        Section(scope.rawValue) {
                            ForEach(SettingsSync.items.filter { $0.scope == scope }) { item in
                                itemToggle(item, source: source)
                            }
                        }
                    }
                }

                if let report {
                    Section("Result") {
                        ForEach(report, id: \.self) { Text($0).font(.callout) }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !model.codeSessions(for: target).isEmpty || !model.desktopInstances(for: target).isEmpty {
                    Hint("“\(target.name)” is running. Restart it to pick up the changes.")
                }
                Spacer()
                Button(report == nil ? "Cancel" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty || source == nil)
            }
            .padding(16)
        }
        .frame(width: 580, height: 680)
        .onAppear {
            if sourceID.isEmpty {
                sourceID = sources.first(where: \.isDefault)?.id ?? sources.first?.id ?? ""
            }
        }
        .onChange(of: sourceID) { _ in
            selected = []
            report = nil
        }
    }

    @ViewBuilder
    private func itemToggle(_ item: SettingsSync.Item, source: Profile) -> some View {
        let available = SettingsSync.exists(item, in: source)
        Toggle(isOn: Binding(
            get: { selected.contains(item.id) },
            set: { on in if on { selected.insert(item.id) } else { selected.remove(item.id) } }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                Text(available ? item.detail : "\(item.detail) — not found in \(source.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!available)
    }

    private func apply() {
        guard let source else { return }
        let items = SettingsSync.items.filter { selected.contains($0.id) }
        report = SettingsSync.apply(items, from: source, to: target, mode: mode)
        selected = []
        model.refreshSizes(target)
    }
}
