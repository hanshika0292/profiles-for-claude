import SwiftUI

struct ProfileEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: Profile?
    @State private var draft: Profile

    private static let emojis = ["💼", "🏠", "🧪", "🚀", "🎓", "🛠️", "🌙", "⚡️", "🔒", "🎨", "🦊", "🌿"]

    let prefill: Profile?
    @State private var copyDefaults: Bool

    init(original: Profile?, prefill: Profile? = nil) {
        self.original = original
        self.prefill = prefill
        _copyDefaults = State(initialValue: prefill == nil)
        _draft = State(initialValue: original ?? prefill ?? Profile(
            name: "", slug: "", emoji: Self.emojis.randomElement() ?? "💼",
            color: ProfileColor.allCases.filter { $0 != .orange }.randomElement() ?? .blue,
            codeConfigDir: "", desktopDataDir: ""))
    }

    private var isNew: Bool { original == nil }
    /// Only fresh folders get starter settings; an adopted folder keeps its own.
    private var canCopyDefaults: Bool {
        isNew && draft.codeConfigDir.trimmingCharacters(in: .whitespaces).isEmpty && model.profile(Profile.defaultID) != nil
    }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var previewSlug: String {
        original?.slug ?? model.uniqueSlug(Profile.slugify(trimmedName.isEmpty ? "profile" : trimmedName))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let prefill {
                    Notice(systemImage: "tray.and.arrow.down.fill", tint: .accentColor,
                           text: "Importing \(Paths.abbreviate(Paths.expand(prefill.codeConfigDir.isEmpty ? prefill.desktopDataDir : prefill.codeConfigDir))). It keeps its existing sign-in, settings and history.")
                }
                Section {
                    HStack(spacing: 14) {
                        Avatar(profile: draft, size: 52)
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Name", text: $draft.name, prompt: Text("Work, Personal, Client…"))
                            TextField("Account", text: $draft.accountLabel, prompt: Text("Email you sign in with (optional)"))
                        }
                    }
                    LabeledContent("Icon") {
                        HStack(spacing: 4) {
                            ForEach(Self.emojis, id: \.self) { e in
                                iconChoice(e) { Text(e).font(.system(size: 17)) }
                            }
                            iconChoice("") {
                                Text(trimmedName.first.map { String($0).uppercased() } ?? "A")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 22)
                            }
                            .help("Use the first letter of the name")
                        }
                    }
                    LabeledContent("Color") {
                        HStack(spacing: 8) {
                            ForEach(ProfileColor.allCases) { c in
                                Circle()
                                    .fill(c.color)
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(draft.color == c ? 0.8 : 0), lineWidth: 2).padding(-3))
                                    .onTapGesture { draft.color = c }
                                    .help(c.rawValue.capitalized)
                            }
                        }
                    }
                }

                if canCopyDefaults {
                    Section {
                        Toggle(isOn: $copyDefaults) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start with my settings from Default")
                                Hint("Copies settings.json, CLAUDE.md, agents, commands, skills and MCP servers for Claude Code and Claude Desktop. Sign-ins and history aren't copied.")
                            }
                        }
                    }
                }

                Section {
                    FolderField(label: "Start sessions in", path: $draft.defaultFolder, placeholder: "Home folder",
                                prompt: "Choose")
                    LabeledContent("Extra arguments") {
                        TextField("", text: $draft.codeArgs, prompt: Text("e.g. --model opus"))
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Extra environment")
                        TextEditor(text: $draft.extraEnv)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(height: 58)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        Hint("KEY=value, one per line. Exported before claude starts, e.g. ANTHROPIC_MODEL=… or ANTHROPIC_API_KEY=… for an API-key profile. Stored in plain text in Claude Manager's profiles.json.")
                    }
                } header: {
                    Text("Claude Code")
                }

                if !draft.isDefault {
                    Section {
                        FolderField(label: "Code config folder", path: $draft.codeConfigDir,
                                    placeholder: "~/.claude-profiles/\(previewSlug)", prompt: "Use Folder")
                        FolderField(label: "Desktop data folder", path: $draft.desktopDataDir,
                                    placeholder: Paths.abbreviate(Paths.profilesDesktopRoot.appendingPathComponent(previewSlug).path),
                                    prompt: "Use Folder")
                    } header: {
                        Text("Storage")
                    } footer: {
                        Hint(isNew
                             ? "Leave these empty to create fresh folders. Pick an existing folder to adopt a login you already set up with CLAUDE_CONFIG_DIR or --user-data-dir."
                             : "Changing a folder points the profile at different data; nothing is moved.")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if isNew {
                    Hint("You'll sign in the first time you open it.")
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create Profile" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 600, height: draft.isDefault ? 520 : 660)
    }

    private func iconChoice<Label: View>(_ value: String, @ViewBuilder label: () -> Label) -> some View {
        Button { draft.emoji = value } label: { label() }
            .buttonStyle(.plain)
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(draft.emoji == value ? Color.accentColor.opacity(0.25) : .clear))
    }

    private func save() {
        var p = draft
        p.name = trimmedName
        p.emoji = p.emoji.trimmingCharacters(in: .whitespaces)
        p.accountLabel = p.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        p.codeArgs = p.codeArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        p.defaultFolder = p.defaultFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        p.codeConfigDir = p.codeConfigDir.trimmingCharacters(in: .whitespacesAndNewlines)
        p.desktopDataDir = p.desktopDataDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if let original {
            if !p.isDefault {
                if p.codeConfigDir.isEmpty { p.codeConfigDir = original.codeConfigDir }
                if p.desktopDataDir.isEmpty { p.desktopDataDir = original.desktopDataDir }
            }
            model.update(p, previous: original)
        } else {
            p.slug = model.uniqueSlug(Profile.slugify(p.name))
            if p.codeConfigDir.isEmpty { p.codeConfigDir = "~/.claude-profiles/\(p.slug)" }
            if p.desktopDataDir.isEmpty {
                p.desktopDataDir = Paths.abbreviate(Paths.profilesDesktopRoot.appendingPathComponent(p.slug).path)
            }
            model.create(p, copySettingsFrom: canCopyDefaults && copyDefaults ? model.profile(Profile.defaultID) : nil)
        }
        dismiss()
    }
}

struct FolderField: View {
    @EnvironmentObject var model: AppModel
    let label: String
    @Binding var path: String
    let placeholder: String
    let prompt: String

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("", text: $path, prompt: Text(placeholder))
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
                Button("Choose…") {
                    let start = path.isEmpty ? Paths.home : URL(fileURLWithPath: Paths.expand(path))
                    if let url = model.chooseFolder(prompt: prompt, start: start) {
                        path = Paths.abbreviate(url.path)
                    }
                }
            }
        }
    }
}
