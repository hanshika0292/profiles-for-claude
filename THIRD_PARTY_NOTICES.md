# Third-party notices

Profiles for Claude (the app is called Claude Manager) contains no third-party code and has
no package dependencies. It builds only against Apple's system frameworks and libraries
(Foundation, AppKit, SwiftUI and Darwin's libproc), which are not redistributed.

## Images and icons

- No fonts, icons or images are bundled. The app icon and the badges on Dock launchers are
  drawn in code (`Sources/IconRenderer.swift`).
- Interface symbols are SF Symbols, supplied by macOS at run time.
- A Claude Desktop Dock launcher uses the icon of the copy of Claude Desktop installed on
  your Mac, read when you create the launcher. That artwork belongs to Anthropic and is not
  included in this repository or in the app bundle.
- The screenshots in `docs/` were rendered from the app's own views with fictional data.

## Trademarks

Claude, Claude Code, Claude Desktop and Anthropic are trademarks of Anthropic, PBC. They are
used here only to say which software this app works with. This project is not made by,
affiliated with or endorsed by Anthropic.
