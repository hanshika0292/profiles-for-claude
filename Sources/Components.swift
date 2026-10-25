import SwiftUI

struct Avatar: View {
    let profile: Profile
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(profile.color.color.gradient)
            Text(profile.initial)
                .font(.system(size: size * (profile.emoji.isEmpty ? 0.45 : 0.52), weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = .green

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .foregroundStyle(color)
    }
}

struct RunningBadge: View {
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            if count > 1 { Text("\(count)") }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.green.opacity(0.18)))
        .foregroundStyle(.green)
    }
}

struct Card<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    let accessory: Accessory
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title).font(.headline)
                Spacer()
                accessory
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

extension Card where Accessory == EmptyView {
    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}

/// Label / value row with an optional trailing action, used for folder paths and sizes.
struct InfoRow<Trailing: View>: View {
    let label: String
    let value: String
    var monospaced = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            trailing
        }
        .font(.callout)
    }
}

extension InfoRow where Trailing == EmptyView {
    init(label: String, value: String, monospaced: Bool = false) {
        self.init(label: label, value: value, monospaced: monospaced, trailing: { EmptyView() })
    }
}

struct Notice<Actions: View>: View {
    let systemImage: String
    var tint: Color = .orange
    let text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            actions
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.10)))
    }
}

extension Notice where Actions == EmptyView {
    init(systemImage: String, tint: Color = .orange, text: String) {
        self.init(systemImage: systemImage, tint: tint, text: text, actions: { EmptyView() })
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum Format {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func ago(_ date: Date?) -> String {
        guard let date else { return "Never" }
        if Date().timeIntervalSince(date) < 45 { return "Just now" }
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
