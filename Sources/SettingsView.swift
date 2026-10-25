import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.terminalKey) private var terminal = TerminalChoice.terminal.rawValue
    @AppStorage(Prefs.customTemplateKey) private var customTemplate = ""
    @AppStorage(Prefs.claudePathKey) private var claudeOverride = ""
    @AppStorage(Prefs.desktopAppKey) private var desktopOverride = ""
    @AppStorage(Prefs.commandsDirKey) private var commandsDir = ""
    @AppStorage(Prefs.showMenuBarKey) private var showMenuBar = true

    var body: some View {
        Form {
            Section {
                Picker("Open sessions in", selection: $terminal) {
                    ForEach(TerminalChoice.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                            .disabled(choice == .iterm && Toolchain.itermURL() == nil)
                    }
                }
                if terminal == TerminalChoice.custom.rawValue {
                    LabeledContent("Command") {
                        TextField("", text: $customTemplate, prompt: Text(Prefs.defaultCustomTemplate))
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                    }
                    Hint("Runs with /bin/sh. {script} is a launch script that sets up the profile and starts claude; {dir} is the folder. Warp: open -a Warp {script} · WezTerm: wezterm start -- {script}")
                }
                if terminal == TerminalChoice.iterm.rawValue {
                    Hint("The first launch asks for permission to control iTerm2.")
                }
            } header: {
                Text("Claude Code")
            }

            Section {
                LabeledContent("claude CLI") {
                    Text(model.claudePath.map(Paths.abbreviate) ?? "Not found")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(model.claudePath == nil ? .orange : .secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Custom path") {
                    TextField("", text: $claudeOverride, prompt: Text("Detected automatically"))
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Claude Desktop") {
                    HStack {
                        Text(model.desktopAppURL.map { Paths.abbreviate($0.path) } ?? "Not installed")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(model.desktopAppURL == nil ? .orange : .secondary)
                        Button("Choose…") { chooseDesktopApp() }
                        if !desktopOverride.isEmpty {
                            Button("Reset") { desktopOverride = ""; model.refreshToolchain() }
                        }
                    }
                }
                LabeledContent("Terminal commands folder") {
                    TextField("", text: $commandsDir, prompt: Text(Prefs.defaultCommandsDir))
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                }
                if model.commandsDirInPath == false {
                    Hint("⚠︎ This folder isn't on your shell's PATH, so claude-<profile> commands won't be found until you add it.")
                }
            } header: {
                Text("Locations")
            } footer: {
                Button("Re-detect") { model.refreshToolchain() }
            }

            Section {
                Toggle("Show in menu bar", isOn: $showMenuBar)
                LabeledContent("Claude Code updates") {
                    Button("Update Claude Code…") { model.updateClaudeCode() }
                        .disabled(model.claudePath == nil)
                }
                Hint("All profiles share one Claude Code install, so updating once updates every profile.")
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 600)
        .onChange(of: claudeOverride) { _ in model.refreshToolchain() }
        .onChange(of: commandsDir) { _ in model.refreshToolchain() }
    }

    private func chooseDesktopApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Use This App"
        if panel.runModal() == .OK, let url = panel.url {
            desktopOverride = url.path
            model.refreshToolchain()
        }
    }
}
