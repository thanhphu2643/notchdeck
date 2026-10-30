import CNotchCore
import Foundation

struct SystemStats: Decodable {
    var cpuPercent: Double
    var memUsed: UInt64
    var memTotal: UInt64
    var netDown: UInt64
    var netUp: UInt64
}

struct TimerState: Decodable, Equatable {
    var active: Bool
    var paused: Bool
    var totalSecs: Int
    var remainingSecs: Int
    var finished: Bool

    static let idle = TimerState(active: false, paused: false, totalSecs: 0, remainingSecs: 0, finished: false)
}

struct MediaState: Decodable, Equatable {
    var title: String
    var artist: String
    var album: String
    var appName: String
    var bundleId: String
    var duration: Double
    var position: Double
    var playing: Bool
}

/// Thin Swift facade over the Rust core's C ABI.
enum Core {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static func decode<T: Decodable>(_ call: () -> UnsafeMutablePointer<CChar>?) -> T? {
        guard let ptr = call() else { return nil }
        defer { nd_string_free(ptr) }
        return try? decoder.decode(T.self, from: Data(String(cString: ptr).utf8))
    }

    static func initialize() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchDeck")
        _ = nd_init(dir.path)
    }

    static func stats() -> SystemStats? { decode(nd_stats) }

    @discardableResult
    static func pushClip(_ text: String) -> Bool { nd_clip_push(text) }
    static func clips() -> [String] { decode(nd_clip_list) ?? [] }
    static func removeClip(at index: Int) { nd_clip_remove(UInt32(index)) }
    static func clearClips() { nd_clip_clear() }

    static func addToShelf(_ url: URL) { _ = nd_shelf_add(url.path) }
    static func removeFromShelf(_ url: URL) { nd_shelf_remove(url.path) }
    static func shelf() -> [URL] {
        let paths: [String] = decode(nd_shelf_list) ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// Returns true when the playing item changed.
    static func updateMedia(_ json: String) -> Bool { nd_media_update(json) }
    static func setMediaPlaying(_ playing: Bool) { nd_media_set_playing(playing) }
    static func mediaState() -> MediaState? { decode(nd_media_state) }

    static func startTimer(minutes: Int) { nd_timer_start(UInt32(minutes * 60)) }
    static func toggleTimerPause() { nd_timer_toggle_pause() }
    static func stopTimer() { nd_timer_stop() }
    static func timerState() -> TimerState { decode(nd_timer_state) ?? .idle }
}
