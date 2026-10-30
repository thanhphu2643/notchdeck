import AppKit
import IOKit.ps

struct Battery: Equatable {
    var percent: Int
    var charging: Bool

    static func read() -> Battery? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return Battery(percent: current * 100 / max, charging: desc[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }
}

@MainActor
final class NotchModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case media, system, clipboard, shelf

        var icon: String {
            switch self {
            case .media: "play.circle"
            case .system: "gauge.with.dots.needle.33percent"
            case .clipboard: "doc.on.clipboard"
            case .shelf: "tray.full"
            }
        }
    }

    @Published var isExpanded = false
    /// Remembered across launches.
    @Published var tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .media {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
    }
    @Published var now = Date()
    @Published var stats: SystemStats?
    @Published var battery: Battery?
    @Published var clips: [String] = []
    @Published var shelf: [URL] = []
    @Published var timer: TimerState = .idle
    @Published var media: MediaState?
    @Published var artwork: NSImage?
    @Published var notchSize: CGSize

    private var pasteboardChangeCount = NSPasteboard.general.changeCount
    private var timers: [Timer] = []
    private var watcher: NowPlayingWatcher?

    init(notchSize: CGSize) {
        self.notchSize = notchSize
        clips = Core.clips()
        shelf = Core.shelf().filter { FileManager.default.fileExists(atPath: $0.path) }
        battery = Battery.read()
        timers = [
            repeating(1) { $0.tick() },
            repeating(0.5) { $0.pollPasteboard() },
        ]
        watcher = NowPlayingWatcher { [weak self] line in
            Task { @MainActor in self?.ingestMedia(line) }
        }
        watcher?.start()
    }

    /// Kept small: just a band of content under the notch.
    var expandedSize: CGSize { CGSize(width: 440, height: notchSize.height + 112) }

    /// While a timer runs or media plays, the collapsed notch grows sideways like a live activity.
    var collapsedSize: CGSize {
        let side: CGFloat = timer.active ? 64 : (media?.playing == true ? notchSize.height + 8 : 0)
        return CGSize(width: notchSize.width + 2 * side, height: notchSize.height)
    }

    var size: CGSize { isExpanded ? expandedSize : collapsedSize }

    private func repeating(_ interval: TimeInterval, _ body: @escaping @MainActor (NotchModel) -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { body(self) }
            }
        }
    }

    private func tick() {
        now = Date()
        let next = Core.timerState()
        if next.finished && !timer.finished {
            NSSound(named: "Glass")?.play()
        }
        timer = next
        media = Core.mediaState()
        if isExpanded {
            stats = Core.stats()
            battery = Battery.read()
        }
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pasteboard.changeCount
        // Respect password managers: http://nspasteboard.org
        let types = pasteboard.types ?? []
        let private_ = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        guard !types.contains(where: { private_.contains($0.rawValue) }),
              let text = pasteboard.string(forType: .string)
        else { return }
        if Core.pushClip(text) { clips = Core.clips() }
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        if expanded {
            stats = Core.stats()
            battery = Battery.read()
        }
        isExpanded = expanded
    }

    // MARK: Media

    private func ingestMedia(_ line: String) {
        if Core.updateMedia(line) {
            artwork = Self.artwork(in: line)
        } else if artwork == nil, let image = Self.artwork(in: line) {
            artwork = image
        }
        media = Core.mediaState()
    }

    private static func artwork(in line: String) -> NSImage? {
        guard line.contains("\"artwork\""),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let base64 = object["artwork"] as? String,
              let data = Data(base64Encoded: base64)
        else { return nil }
        return NSImage(data: data)
    }

    func mediaCommand(_ command: MediaCommand) {
        command.send()
        if command == .togglePlayPause, let media {
            Core.setMediaPlaying(!media.playing)
            self.media = Core.mediaState()
        }
    }

    func openMediaApp() {
        guard let id = media?.bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: Clipboard

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func removeClip(at index: Int) {
        Core.removeClip(at: index)
        clips = Core.clips()
    }

    func clearClips() {
        Core.clearClips()
        clips = []
    }

    // MARK: Shelf

    func addToShelf(_ urls: [URL]) {
        urls.forEach(Core.addToShelf)
        shelf = Core.shelf()
        tab = .shelf
    }

    func removeFromShelf(_ url: URL) {
        Core.removeFromShelf(url)
        shelf = Core.shelf()
    }

    // MARK: Timer

    func startTimer(minutes: Int) {
        Core.startTimer(minutes: minutes)
        timer = Core.timerState()
    }

    func toggleTimerPause() {
        Core.toggleTimerPause()
        timer = Core.timerState()
    }

    func stopTimer() {
        Core.stopTimer()
        timer = .idle
    }
}
