import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: model.isExpanded ? 20 : 10,
                    bottomTrailingRadius: model.isExpanded ? 20 : 10
                )
                .fill(.black)
                .overlay {
                    if dropTargeted {
                        UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20)
                            .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    }
                }

                if model.isExpanded {
                    ExpandedView(model: model)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if model.timer.active {
                    CollapsedTimer(model: model)
                } else if model.media?.playing == true {
                    CollapsedMedia(model: model)
                }
            }
            .frame(width: model.size.width, height: model.size.height)
            .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 10, y: 4)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: dropFiles)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.collapsedSize)
    }

    private func dropFiles(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.addToShelf([url]) }
            }
        }
        return true
    }
}

// MARK: - Collapsed

private struct CollapsedTimer: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack {
            Image(systemName: model.timer.finished ? "checkmark.circle.fill" : "timer")
                .foregroundStyle(model.timer.finished ? .green : .orange)
            Spacer()
            Text(formatClock(model.timer.remainingSecs))
                .monospacedDigit()
                .foregroundStyle(model.timer.paused ? .secondary : .primary)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: model.notchSize.height)
    }
}

private struct CollapsedMedia: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let side = model.notchSize.height - 12
        HStack {
            Artwork(image: model.artwork, bundleId: model.media?.bundleId, cornerRadius: 5)
                .frame(width: side, height: side)
            Spacer()
            Equalizer()
                .frame(width: side, height: side * 0.7)
        }
        .padding(.horizontal, 10)
        .frame(height: model.notchSize.height)
    }
}

private struct Equalizer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = sin(t * (5 + Double(i) * 1.7) + Double(i))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: 0.3 + 0.7 * abs(phase), anchor: .center)
                }
            }
        }
    }
}

// MARK: - Expanded

private struct ExpandedView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 6) {
            header
            Group {
                switch model.tab {
                case .media: MediaTab(model: model)
                case .system: SystemTab(model: model)
                case .clipboard: ClipboardTab(model: model)
                case .shelf: ShelfTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// Lives in the strip beside the camera, so the middle stays empty.
    private var header: some View {
        HStack(spacing: 2) {
            ForEach(NotchModel.Tab.allCases, id: \.self) { tab in
                Button { model.tab = tab } label: {
                    Image(systemName: tab.icon)
                        .frame(width: 26, height: 20)
                        .background(model.tab == tab ? Color.white.opacity(0.15) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(model.now, format: .dateTime.hour().minute())
                .monospacedDigit()
            if let battery = model.battery {
                Image(systemName: battery.charging ? "battery.100.bolt" : batteryIcon(battery.percent))
                Text("\(battery.percent)%").monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(height: max(model.notchSize.height, 24))
    }
}

private struct MediaTab: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        if let media = model.media {
            HStack(spacing: 12) {
                Button(action: model.openMediaApp) {
                    Artwork(image: model.artwork, bundleId: media.bundleId, cornerRadius: 10)
                        .frame(width: 76, height: 76)
                }
                .buttonStyle(.plain)
                .help("Open \(media.appName)")

                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title.isEmpty ? "Unknown" : media.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text([media.artist, media.appName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if media.duration > 0 {
                        Bar(value: media.position / media.duration, color: .white)
                            .frame(height: 4)
                        HStack {
                            Text(formatClock(Int(media.position)))
                            Spacer()
                            Text("-" + formatClock(Int(media.duration - media.position)))
                        }
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 22) {
                        control("backward.fill", .previous)
                        control(media.playing ? "pause.fill" : "play.fill", .togglePlayPause, size: 18)
                        control("forward.fill", .next)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            Placeholder(icon: "music.note", text: "Nothing playing")
        }
    }

    private func control(_ symbol: String, _ command: MediaCommand, size: CGFloat = 13) -> some View {
        Button { model.mediaCommand(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Artwork: View {
    let image: NSImage?
    let bundleId: String?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let bundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                // No artwork (common for browser video): fall back to the source app's icon.
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().padding(4)
            } else {
                Image(systemName: "music.note").resizable().scaledToFit().padding(8).foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private struct SystemTab: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 10) {
            Card { StatsView(stats: model.stats) }
            Card { TimerView(model: model) }
                .frame(width: 130)
        }
    }
}

private struct StatsView: View {
    let stats: SystemStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let stats {
                Meter(label: "CPU", value: stats.cpuPercent / 100, text: "\(Int(stats.cpuPercent))%")
                Meter(label: "RAM", value: Double(stats.memUsed) / Double(max(stats.memTotal, 1)),
                      text: ByteCountFormatter.string(fromByteCount: Int64(stats.memUsed), countStyle: .memory))
                HStack(spacing: 10) {
                    Label(rate(stats.netDown), systemImage: "arrow.down")
                    Label(rate(stats.netUp), systemImage: "arrow.up")
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Text("Stats unavailable").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rate(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + "/s"
    }
}

private struct Meter: View {
    let label: String
    let value: Double
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(text).monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            Bar(value: value, color: value > 0.85 ? .red : .accentColor)
                .frame(height: 4)
        }
    }
}

/// ProgressView renders grey in a non-key panel, so draw the bar.
private struct Bar: View {
    let value: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.12))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                }
            }
    }
}

private struct TimerView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 6) {
            if model.timer.active {
                Text(model.timer.finished ? "Done" : formatClock(model.timer.remainingSecs))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.timer.finished ? .green : .primary)
                HStack(spacing: 6) {
                    if !model.timer.finished {
                        iconButton(model.timer.paused ? "play.fill" : "pause.fill", action: model.toggleTimerPause)
                    }
                    iconButton("stop.fill", action: model.stopTimer)
                }
            } else {
                Label("Focus", systemImage: "timer")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach([5, 25, 50], id: \.self) { minutes in
                        Button("\(minutes)") { model.startTimer(minutes: minutes) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct ClipboardTab: View {
    @ObservedObject var model: NotchModel
    @State private var copied: String?

    var body: some View {
        if model.clips.isEmpty {
            Placeholder(icon: "doc.on.clipboard", text: "Copied text shows up here")
        } else {
            HStack(alignment: .top) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.clips.enumerated()), id: \.element) { index, clip in
                            Button {
                                model.copy(clip)
                                copied = clip
                            } label: {
                                Text(clip)
                                    .font(.system(size: 10))
                                    .lineLimit(5)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 100, height: 70, alignment: .topLeading)
                                    .padding(6)
                                    .background(.white.opacity(copied == clip ? 0.2 : 0.08),
                                                in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove") { model.removeClip(at: index) }
                            }
                        }
                    }
                }
                Button { model.clearClips() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear history")
            }
        }
    }
}

private struct ShelfTab: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        if model.shelf.isEmpty {
            Placeholder(icon: "tray.and.arrow.down", text: "Drop files on the notch to keep them here")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.shelf, id: \.self) { url in
                        VStack(spacing: 3) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 40, height: 40)
                            Text(url.lastPathComponent)
                                .font(.system(size: 9))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 70, height: 82)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                        .contextMenu {
                            Button("Open") { NSWorkspace.shared.open(url) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Button("Remove from Shelf") { model.removeFromShelf(url) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(8)
            .frame(maxHeight: .infinity)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct Placeholder: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20))
            Text(text).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func formatClock(_ seconds: Int) -> String {
    let s = max(seconds, 0)
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%02d:%02d", s / 60, s % 60)
}

private func batteryIcon(_ percent: Int) -> String {
    switch percent {
    case ..<13: "battery.0"
    case ..<38: "battery.25"
    case ..<63: "battery.50"
    case ..<88: "battery.75"
    default: "battery.100"
    }
}
