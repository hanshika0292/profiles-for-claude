import AppKit

/// Draws the app icon and per-profile Dock launcher icons. No image assets needed.
enum IconRenderer {
    private static let terracotta = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    private static let cream = NSColor(srgbRed: 0.98, green: 0.95, blue: 0.90, alpha: 1)

    /// macOS icon grid: an 824pt rounded square centered on a 1024pt canvas.
    private static func squircle(in canvas: CGRect) -> NSBezierPath {
        let inset = canvas.width * 100 / 1024
        let r = canvas.insetBy(dx: inset, dy: inset)
        return NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
    }

    static func drawAppIcon(in canvas: CGRect) {
        let shape = squircle(in: canvas)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = canvas.width * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -canvas.width * 0.01)
        shadow.set()
        NSGradient(starting: NSColor(srgbRed: 0.91, green: 0.56, blue: 0.43, alpha: 1),
                   ending: NSColor(srgbRed: 0.74, green: 0.36, blue: 0.24, alpha: 1))?
            .draw(in: shape, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Three stacked windows = several Claude instances side by side.
        let s = canvas.width
        let cardW = s * 0.50, cardH = s * 0.36
        let accents: [NSColor] = [.systemBlue, .systemGreen, cream]
        for i in 0..<3 {
            let offset = CGFloat(2 - i) * s * 0.075
            let rect = CGRect(x: s * 0.215 + offset, y: s * 0.235 + offset, width: cardW, height: cardH)
            let card = NSBezierPath(roundedRect: rect, xRadius: s * 0.04, yRadius: s * 0.04)
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(0.22)
            sh.shadowBlurRadius = s * 0.025
            sh.shadowOffset = NSSize(width: 0, height: -s * 0.008)
            sh.set()
            cream.withAlphaComponent(i == 2 ? 1 : 0.55 + CGFloat(i) * 0.15).setFill()
            card.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Title bar dots.
            let dotR = s * 0.016
            for d in 0..<3 {
                let c = CGRect(x: rect.minX + s * 0.035 + CGFloat(d) * dotR * 3, y: rect.maxY - s * 0.05,
                               width: dotR * 2, height: dotR * 2)
                terracotta.withAlphaComponent(i == 2 ? 0.9 : 0.5).setFill()
                NSBezierPath(ovalIn: c).fill()
            }
            if i == 2 {
                // Prompt glyph on the front window.
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: s * 0.13, weight: .bold),
                    .foregroundColor: terracotta,
                ]
                NSAttributedString(string: ">_", attributes: attrs)
                    .draw(at: CGPoint(x: rect.minX + s * 0.05, y: rect.minY + s * 0.06))
                // Account badge on the front window.
                let badge = CGRect(x: rect.maxX - s * 0.15, y: rect.minY + s * 0.06, width: s * 0.10, height: s * 0.10)
                accents[0].setFill()
                NSBezierPath(ovalIn: badge).fill()
            } else {
                let badge = CGRect(x: rect.maxX - s * 0.13, y: rect.maxY - s * 0.085, width: s * 0.06, height: s * 0.06)
                accents[i].withAlphaComponent(0.8).setFill()
                NSBezierPath(ovalIn: badge).fill()
            }
        }
    }

    static func launcherIcon(profile: Profile, kind: Launcher.LauncherKind) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { canvas in
            if kind == .desktop, let app = Toolchain.desktopAppURL() {
                NSWorkspace.shared.icon(forFile: app.path).draw(in: canvas)
            } else {
                drawCodeBase(in: canvas)
            }
            drawBadge(profile: profile, in: canvas)
            return true
        }
    }

    private static func drawCodeBase(in canvas: CGRect) {
        let shape = squircle(in: canvas)
        NSGradient(starting: NSColor(white: 0.20, alpha: 1), ending: NSColor(white: 0.08, alpha: 1))?.draw(in: shape, angle: -90)
        let s = canvas.width
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: s * 0.26, weight: .bold),
            .foregroundColor: terracotta,
        ]
        NSAttributedString(string: ">_", attributes: attrs).draw(at: CGPoint(x: s * 0.24, y: s * 0.40))
    }

    private static func drawBadge(profile: Profile, in canvas: CGRect) {
        let s = canvas.width
        let d = s * 0.42
        let rect = CGRect(x: s - d - s * 0.06, y: s * 0.06, width: d, height: d)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: -s * 0.015, dy: -s * 0.015)).fill()
        profile.color.nsColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let text = profile.initial
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: d * 0.52, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let b = str.size()
        str.draw(at: CGPoint(x: rect.midX - b.width / 2, y: rect.midY - b.height / 2))
    }

    /// Writes an .iconset folder for `iconutil` (used by build.sh via --render-app-icon).
    static func writeAppIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                rep.size = NSSize(width: px, height: px)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                drawAppIcon(in: CGRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
