# Claude Manager

*Unofficial. Not made by or affiliated with Anthropic.*

A native macOS app that runs several Claude Code and Claude Desktop accounts side by side, each in its own isolated profile.

## The problem

By default, Claude Code and Claude Desktop each keep one sign-in per macOS user. If you have a personal account, a work account and maybe an API-key setup, you either sign out and back in, or juggle `CLAUDE_CONFIG_DIR` and Electron flags by hand. Claude Manager gives each account its own folders and starts the right copy for you.

## Features

**Profiles**

- Each profile has a name, an emoji or initial, a color, an optional account label, extra `claude` arguments, extra environment variables and a default start folder.
- A built-in Default profile points at your existing `~/.claude`, `~/.claude.json` and Claude Desktop data. Nothing is moved.
- A new profile can start with a copy of Default's `settings.json`, `CLAUDE.md`, agents, commands, skills, output styles, keybindings and MCP servers. Sign-ins and history are never copied.
- A profile can adopt a folder you already use with `CLAUDE_CONFIG_DIR` or `--user-data-dir`, and keeps that folder's sign-in.
- "Found on this Mac": if a running Claude Code session or Desktop copy uses a folder that no profile covers, the sidebar offers to import it or ignore it.
- Profiles can be reordered by dragging in the sidebar.

**Claude Desktop**

- Open, bring to front or quit each profile's copy of Claude Desktop.
- "Open for Sign-In" quits the other copies first. A Google or SSO sign-in returns through a `claude://` link, and macOS hands that link to whichever copy is running.

**Claude Code**

- Start a session in the profile's default folder, a recent folder (the last 8 are kept) or a folder you pick.
- Sessions open in Terminal, iTerm2, or any terminal through a custom command template with `{script}` and `{dir}` placeholders.
- After `claude` exits, the window stays in a login shell that still has the profile's environment.
- Sign-in status comes from the profile's `.claude.json` and from `claude auth status --json`. Sign In runs `claude auth login` in a terminal and then starts a session. Sign Out runs `claude auth logout`.
- "Update Claude Code" runs `claude update` once. All profiles share one install.

**Live status**

- Shows running Desktop copies and Code sessions per profile, with each session's folder, start time and PID, and a Stop button.
- Process data is read from the kernel, so sessions you started by hand are found too. Sessions started from Claude Desktop's built-in Code tab are labelled as such. Child `claude` processes (subagents, tools) are not counted as sessions.
- Shows the disk size of each profile's folders.

**Launching from outside the app**

- Install a `claude-<slug>` command (in `~/.local/bin` by default) to run a profile from any terminal, for example `claude-work -c`. The app warns if that folder isn't on your shell's `PATH`.
- Create a small Dock launcher `.app` per profile, with an icon badged in the profile's color and emoji.
- A menu bar menu with quick launch for every profile.
- A headless command-line mode (see [Command-line use](#command-line-use)).

**Sharing settings between profiles**

- Copy or symlink `settings.json`, `CLAUDE.md`, agents, commands, skills, output styles, keybindings, plugins, the Desktop config file and Desktop extensions from one profile to another.
- User-scope MCP servers are merged into the target's `.claude.json` without touching the login stored there.

## How it works

Isolation uses two switches that the Claude apps already respect:

| | Default profile | Any other profile |
|---|---|---|
| **Claude Code** | `~/.claude` + `~/.claude.json` | `CLAUDE_CONFIG_DIR=~/.claude-profiles/<slug>` |
| **Claude Desktop** | `~/Library/Application Support/Claude` | `--user-data-dir=~/Library/Application Support/Claude Manager/Desktop/<slug>` |

- **Claude Code** reads its login, settings, history, agents, skills, plugins and user MCP servers from `CLAUDE_CONFIG_DIR`. Claude Manager exports it in every launch.
- **Claude Desktop** is an Electron app. Electron ties its single-instance lock and cookies to the user-data folder, so starting `Claude.app` as a new instance with a different `--user-data-dir` gives a separate copy with its own sign-in.

The main pieces:

- **Launcher** writes a short, self-deleting `.command` script for each Code session. The script changes to the folder, clears inherited variables, exports the profile's environment and runs `claude`. Terminal opens it through `NSWorkspace`, so no Automation permission is needed. iTerm2 is driven with AppleScript. The custom option runs your template with `/bin/sh`. Desktop copies are started with `NSWorkspace.openApplication` and `createsNewApplicationInstance`.
- **ProcessScanner** runs every 3 seconds and whenever an app launches or quits. It lists PIDs with libproc, keeps processes owned by the current user that look like Claude Desktop's main process or Claude Code, and reads their arguments and environment with `sysctl(KERN_PROCARGS2)`. `--user-data-dir` and `CLAUDE_CONFIG_DIR` match each process to a profile.
- **Toolchain** finds the `claude` binary (known install paths first, then your login shell) and `Claude.app`. GUI apps don't inherit your shell's `PATH`, so it reads `PATH` from your login shell once.
- **Inherited environment.** If Claude Manager is started from a terminal or a Claude Code session, it drops that terminal's identity variables (`COLORTERM`, `TERM_PROGRAM`, ...) and Claude Code's session markers (`CLAUDECODE`, `CLAUDE_CODE_CHILD_SESSION`, ...). Launch scripts clear them again. Otherwise new sessions would think they are subagents and stop saving transcripts, and Terminal.app before macOS 26 would receive 24-bit color it can't show.
- **SettingsSync** copies or symlinks items between profile folders and merges the `mcpServers` key between `.claude.json` files.
- **Headless mode.** The same binary handles `--launch-code`, `--launch-desktop` and `--list-running`, so Dock launchers and scripts can start profiles without opening the window.

### What it reads and writes on your Mac

| Location | Access | Purpose |
|---|---|---|
| `~/Library/Application Support/Claude Manager/profiles.json` | read/write | The profile list |
| `~/Library/Application Support/Claude Manager/run/` | write | Temporary launch scripts; each deletes itself when it runs |
| `~/.claude-profiles/<slug>/` | create | Claude Code data for new profiles |
| `~/Library/Application Support/Claude Manager/Desktop/<slug>/` | create | Claude Desktop data for new profiles |
| `~/.claude.json` and each profile's `.claude.json` | read; write on MCP merge | Account email and organization, user-scope MCP servers |
| Profile folders | write on request | Share settings, or move to Trash when you delete a profile |
| `~/.local/bin/claude-<slug>` (configurable) | write on request | Terminal commands |
| `~/Applications/Claude Manager/` | write on request | Dock launcher apps |
| Your own Claude processes | read; signal on request | Live status; Stop sends `SIGTERM`, Quit asks the app to quit |

The app makes no network requests of its own. It runs the `claude` CLI for sign-in status, sign-out and version checks.

## Tech stack

- Swift, SwiftUI and AppKit (`NSWorkspace`, `NSOpenPanel`, `NSAppleScript`, `MenuBarExtra`).
- Darwin libproc (`proc_listallpids`, `proc_pidpath`, `proc_pidinfo`) through a one-line bridging header, plus `sysctl(KERN_PROCARGS2)`.
- Foundation `Process` to call the `claude` CLI.
- No third-party dependencies and no Xcode project. `build.sh` calls `swiftc` per architecture, merges the binaries with `lipo`, has the app draw its own icon, converts it with `iconutil` and ad-hoc signs with `codesign`. `make-dmg.sh` packages a DMG with `hdiutil`.
- The app icon and Dock launcher icons are drawn in code. There are no image assets.

## Getting started

### Prerequisites

- macOS 13 or later.
- Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't needed.
- Claude Code and/or Claude Desktop. If either is missing, the app shows a notice with a download link.

### Build and run

```sh
git clone <this-repo-url>
cd <repo-folder>
./build.sh                    # builds build/Claude Manager.app (universal: Intel + Apple Silicon)
open "build/Claude Manager.app"
```

- `./build.sh --install` also copies the app to `~/Applications`, quitting a running copy first.
- `ARCHS=arm64 ./build.sh` (or `ARCHS=x86_64`) builds for one architecture, which is quicker.

On first launch, Default is already there. Click **+** to add a profile, then open Claude Desktop or start a Claude Code session from it and sign in once.

### Package a DMG

```sh
./make-dmg.sh             # builds build/Claude-Manager-<version>.dmg
./make-dmg.sh --install   # same, and installs locally
```

The DMG holds the app and an Applications shortcut. If `dist/Read Me First.txt` exists, it is added too. The app is ad-hoc signed, not notarized, so whoever installs it has to approve it once in System Settings → Privacy & Security.

### Command-line use

```sh
M="$HOME/Applications/Claude Manager.app/Contents/MacOS/ClaudeManager"
"$M" --launch-code work --folder ~/code/example-project   # profile by slug or id
"$M" --launch-desktop work
"$M" --list-running                                       # what's running, grouped by profile
```

### Configuration

- **Profiles** live in `~/Library/Application Support/Claude Manager/profiles.json`. You normally edit them in the app. [`profiles.example.json`](profiles.example.json) shows the format.
- **Preferences** are set in the Settings window and stored in the `local.claudemanager.app` defaults domain: `terminal`, `customTerminalTemplate`, `claudePathOverride`, `desktopAppOverride`, `commandsDir`, `showMenuBarExtra`.
- **Environment variables.** The app needs none. `build.sh` reads `ARCHS`. Every launch exports `CLAUDE_MANAGER_PROFILE` (the profile name) and, for non-default profiles, `CLAUDE_CONFIG_DIR`.

### Uninstall

```sh
rm -rf ~/Applications/"Claude Manager.app" ~/Applications/"Claude Manager" \
       ~/Library/Application\ Support/"Claude Manager"
defaults delete local.claudemanager.app
rm ~/.local/bin/claude-<slug>   # each terminal command you installed from the app
# Profile data, if you want it gone too: ~/.claude-profiles/
```

## Project structure

```
Sources/
  Main.swift               Entry point, window/settings/menu bar scenes, headless mode
  AppModel.swift           App state, profiles.json load/save, user actions
  Profile.swift            Profile model, folder resolution, extra-env parsing
  Paths.swift              Well-known folders, all derived from the home directory
  Launcher.swift           Desktop and Code launching, launch scripts, claude-<slug> commands, Dock launchers
  ProcessScanner.swift     libproc/sysctl scan of running Claude processes
  Toolchain.swift          Finds claude, Claude.app and terminals; inherited-environment cleanup
  Accounts.swift           Sign-in status, disk usage
  SettingsSync.swift       Copy/link settings between profiles, MCP server merge
  Shell.swift              Process runner, shell quoting, preference keys
  IconRenderer.swift       App icon and Dock launcher icons drawn in code
  ContentView.swift        Main window, sidebar, toolchain footer
  ProfileDetailView.swift  Profile page: Desktop, Code and Maintenance cards
  ProfileEditor.swift      New/edit profile sheet
  SyncSheet.swift          Share-settings sheet
  SettingsView.swift       Settings window
  MenuBarContent.swift     Menu bar menu
  Components.swift         Shared SwiftUI views and date formatting
  Bridging.h               Exposes libproc to Swift
Info.plist                 App bundle metadata (version, bundle ID, minimum macOS)
build.sh                   Build script (swiftc, lipo, iconutil, codesign)
make-dmg.sh                DMG packaging
profiles.example.json      Example of the profiles file format
```

## Status and limitations

- Version 1.0.3. A working personal tool. There are no automated tests.
- macOS only (13+). Builds are ad-hoc signed and not notarized.
- Parts of it depend on behaviour that isn't a documented, stable interface: Claude Desktop honouring Electron's `--user-data-dir`, the JSON from `claude auth status --json`, the `oauthAccount` and `mcpServers` keys in `.claude.json`, and the executable paths used to recognise Claude processes. An update to either Claude app could break a feature. Unusual install layouts may not be detected.
- All Desktop copies share Claude's Dock icon and the name "Claude" in ⌘-Tab. Dock launchers and account labels help tell them apart. If a profile's copy is running, clicking the regular Claude icon focuses that copy instead of starting Default. Open Default from Claude Manager instead.
- iTerm2 asks once for Automation permission. Terminal doesn't need any.

Safety notes:

- **Secrets in plain text.** Extra environment values, such as an `ANTHROPIC_API_KEY`, are stored in plain text in `profiles.json`. They are also written into the temporary launch scripts and into installed `claude-<slug>` commands (file mode 755), and included in "Copy Launch Command".
- **Sharing settings replaces files.** Items in the target profile that get replaced are moved to the Trash. If moving to the Trash fails, they are deleted. Linked items are symlinks, so editing one changes every linked profile.
- **MCP merge rewrites `.claude.json`.** The target file is rewritten (formatting and key order may change) and set to mode 600. One backup is kept next to it as `.claude.json.claude-manager-backup` and replaced on each merge. When the target is Default, this is `~/.claude.json`. Restart running sessions afterwards.
- **Deleting a profile** asks whether to keep its folders or move them to the Trash. It never trashes the default Claude folders, your home folder or a folder another profile uses. To make Claude Code forget that profile's saved login too, sign out first. A profile can't be deleted while it is running.
- **Stopping and quitting.** Stop sends `SIGTERM` to a Claude Code session. "Open for Sign-In" quits the other Claude Desktop copies.
- **Shell startup files run.** To find `PATH` and `claude`, the app runs your login shell interactively once (`$SHELL -l -i -c ...`), which runs your shell startup files.
- **Process inspection.** The app reads the arguments and environment of your own Claude processes, and of your Node.js processes to spot npm installs of Claude Code. It only uses `--user-data-dir` and `CLAUDE_CONFIG_DIR` from them.
- **Generated files.** Terminal commands and Dock launchers carry a `# managed-by: Claude Manager` marker. The app won't overwrite or remove a terminal command without it, and only moves marked Dock launchers to the Trash. Creating a Dock launcher replaces any app already at the same path in `~/Applications/Claude Manager/`.
