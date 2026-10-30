import AppKit

/// Tracks system-wide Now Playing (Spotify, Music, browsers, VLC, …).
///
/// Since macOS 15.4, MediaRemote only returns now-playing info to Apple-signed
/// processes, so reading runs inside a long-lived `osascript` (JavaScript for
/// Automation) that prints one JSON line whenever something changes.
/// Sending commands is still allowed from regular apps, so that stays in-process.
final class NowPlayingWatcher {
    private var process: Process?
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] _ in
            // Restart if the watcher dies (e.g. after sleep); back off a little.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.start() }
        }
        try? process.run()
        self.process = process
    }

    deinit {
        process?.terminationHandler = nil
        process?.terminate()
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self)
            buffer.removeSubrange(...newline)
            if !line.isEmpty { onLine(line) }
        }
    }

    private static let script = #"""
    ObjC.import("Foundation");
    $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/").load;
    const R = $.NSClassFromString("MRNowPlayingRequest");
    const out = $.NSFileHandle.fileHandleWithStandardOutput;
    const val = (info, key) => {
      const v = info.valueForKey("kMRMediaRemoteNowPlayingInfo" + key);
      return v.isNil() ? null : v;
    };
    let last = null, lastItem = null;
    while (true) {
      let o = { active: false };
      try {
        const info = R.localNowPlayingItem.nowPlayingInfo;
        if (!info.isNil()) {
          const client = R.localNowPlayingPlayerPath.client;
          const num = k => { const v = val(info, k); return v ? v.doubleValue : null; };
          const str = k => { const v = val(info, k); return v ? v.js : null; };
          const ts = val(info, "Timestamp");
          o = {
            active: true,
            title: str("Title"), artist: str("Artist"), album: str("Album"),
            duration: num("Duration"), elapsed: num("ElapsedTime"), rate: num("PlaybackRate"),
            timestamp: ts ? ts.timeIntervalSince1970 : null,
            playing: R.localIsPlaying,
            app_name: client.isNil() ? null : client.displayName.js,
            bundle_id: client.isNil() ? null : client.bundleIdentifier.js,
          };
        }
      } catch (e) {}
      const item = o.active ? [o.title, o.artist, o.bundle_id].join("|") : null;
      let line = JSON.stringify(o);
      if (line !== last || item !== lastItem) {
        last = line;
        if (item && item !== lastItem) {
          try {
            const art = val(R.localNowPlayingItem.nowPlayingInfo, "ArtworkData");
            if (art) o.artwork = art.base64EncodedStringWithOptions(0).js;
          } catch (e) {}
          line = JSON.stringify(o);
        }
        lastItem = item;
        out.writeData($(line + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
      }
      delay(1);
    }
    """#
}

enum MediaCommand: Int32 {
    case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5

    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool

    private static let send: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand")
        else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    func send() {
        _ = Self.send?(rawValue, nil)
    }
}
