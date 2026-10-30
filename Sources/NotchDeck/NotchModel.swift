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
        case home, clipboard, shelf

        var icon: String {
            switch self {
            case .home: "square.grid.2x2"
            case .clipboard: "doc.on.clipboard"
            case .shelf: "tray.full"
            }
        }
    }

    static let expandedSize = CGSize(width: 640, height: 220)

    @Published var isExpanded = false
    @Published var tab: Tab = .home
    @Published var now = Date()
    @Published var stats: SystemStats?
    @Published var battery: Battery?
    @Published var clips: [String] = []
    @Published var shelf: [URL] = []
    @Published var timer: TimerState = .idle
    @Published var notchSize: CGSize

    private var pasteboardChangeCount = NSPasteboard.general.changeCount
    private var timers: [Timer] = []

    init(notchSize: CGSize) {
        self.notchSize = notchSize
        clips = Core.clips()
        shelf = Core.shelf().filter { FileManager.default.fileExists(atPath: $0.path) }
        battery = Battery.read()
        timers = [
            repeating(1) { $0.tick() },
            repeating(0.5) { $0.pollPasteboard() },
        ]
    }

    /// Collapsed size grows sideways while a timer runs, like a live activity.
    var collapsedSize: CGSize {
        timer.active ? CGSize(width: notchSize.width + 2 * 64, height: notchSize.height) : notchSize
    }

    var size: CGSize { isExpanded ? Self.expandedSize : collapsedSize }

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
