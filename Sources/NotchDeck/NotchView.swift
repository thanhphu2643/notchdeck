import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: model.isExpanded ? 26 : 10,
                    bottomTrailingRadius: model.isExpanded ? 26 : 10
                )
                .fill(.black)
                .overlay {
                    if dropTargeted {
                        UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26)
                            .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    }
                }

                if model.isExpanded {
                    ExpandedView(model: model)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if model.timer.active {
                    CollapsedTimer(model: model)
                }
            }
            .frame(width: model.size.width, height: model.size.height)
            .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 12, y: 4)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: dropFiles)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
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

// MARK: - Expanded

private struct ExpandedView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 10) {
            header
            Group {
                switch model.tab {
                case .home: HomeTab(model: model)
                case .clipboard: ClipboardTab(model: model)
                case .shelf: ShelfTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    /// Lives in the strip beside the camera, so the middle stays empty.
    private var header: some View {
        HStack(spacing: 4) {
            ForEach(NotchModel.Tab.allCases, id: \.self) { tab in
                Button { model.tab = tab } label: {
                    Image(systemName: tab.icon)
                        .frame(width: 30, height: 22)
                        .background(model.tab == tab ? Color.white.opacity(0.15) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if let battery = model.battery {
                Label("\(battery.percent)%", systemImage: battery.charging ? "battery.100.bolt" : batteryIcon(battery.percent))
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(height: max(model.notchSize.height, 28))
    }
}

private struct HomeTab: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.now, format: .dateTime.hour().minute())
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(model.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Card { StatsView(stats: model.stats) }
            Card { TimerView(model: model) }
        }
    }
}

private struct StatsView: View {
    let stats: SystemStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stats {
                Meter(label: "CPU", value: stats.cpuPercent / 100, text: "\(Int(stats.cpuPercent))%")
                Meter(label: "RAM", value: Double(stats.memUsed) / Double(max(stats.memTotal, 1)),
                      text: ByteCountFormatter.string(fromByteCount: Int64(stats.memUsed), countStyle: .memory))
                HStack(spacing: 10) {
                    Label(rate(stats.netDown), systemImage: "arrow.down")
                    Label(rate(stats.netUp), systemImage: "arrow.up")
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Text("Stats unavailable").foregroundStyle(.secondary)
            }
        }
        .frame(width: 150)
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
            .font(.system(size: 11, weight: .medium))
            // ProgressView renders grey in a non-key panel, so draw the bar.
            Capsule()
                .fill(.white.opacity(0.12))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(value > 0.85 ? Color.red : Color.accentColor)
                            .frame(width: geo.size.width * min(max(value, 0), 1))
                    }
                }
                .frame(height: 5)
        }
    }
}

private struct TimerView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 8) {
            if model.timer.active {
                Text(model.timer.finished ? "Done" : formatClock(model.timer.remainingSecs))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.timer.finished ? .green : .primary)
                HStack(spacing: 8) {
                    if !model.timer.finished {
                        iconButton(model.timer.paused ? "play.fill" : "pause.fill", action: model.toggleTimerPause)
                    }
                    iconButton("stop.fill", action: model.stopTimer)
                }
            } else {
                Label("Focus", systemImage: "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach([5, 25, 50], id: \.self) { minutes in
                        Button("\(minutes)m") { model.startTimer(minutes: minutes) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .frame(width: 140)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 28, height: 22)
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
            Placeholder(icon: "doc.on.clipboard", text: "Copy some text and it shows up here")
        } else {
            HStack(alignment: .top) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.clips.enumerated()), id: \.element) { index, clip in
                            Button {
                                model.copy(clip)
                                copied = clip
                            } label: {
                                Text(clip)
                                    .font(.system(size: 11))
                                    .lineLimit(6)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 130, height: 110, alignment: .topLeading)
                                    .padding(8)
                                    .background(.white.opacity(copied == clip ? 0.2 : 0.08),
                                                in: RoundedRectangle(cornerRadius: 10))
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
                HStack(spacing: 10) {
                    ForEach(model.shelf, id: \.self) { url in
                        VStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 56, height: 56)
                            Text(url.lastPathComponent)
                                .font(.system(size: 10))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 84, height: 110)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
            .padding(12)
            .frame(maxHeight: .infinity)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Placeholder: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26))
            Text(text).font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func formatClock(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
