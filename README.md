# NotchDeck

Turn the MacBook notch into something useful. Hover the notch and it expands
into a small dashboard; move away and it tucks back into the camera housing.

- **Home** – clock and date, CPU / RAM / network throughput, battery.
- **Focus timer** – 5 / 25 / 50 minute timers. While running, the collapsed
  notch widens into a live countdown; a sound plays when it ends.
- **Clipboard history** – the last 30 text copies, click to copy again.
  Items marked concealed/transient by password managers
  ([nspasteboard.org](http://nspasteboard.org)) are never recorded.
- **File shelf** – drag files onto the notch to park them, drag them back out
  wherever you need them. Double-click to open.

Works on Macs without a notch too (a pill hugs the menu bar instead).
No Accessibility or other permissions are needed.

## Architecture

```
Sources/NotchDeck/   Swift: AppKit panel + SwiftUI UI, hover tracking, pasteboard, battery
Sources/CNotchCore/  C header + modulemap bridging to Rust
core/                Rust: system stats (sysinfo), clipboard/shelf store, focus timer
```

The Rust crate builds as a static library exposing a small C ABI
(`nd_*` functions in `core/src/lib.rs`). Data crosses the boundary as JSON
strings, which Swift decodes with `Codable`. State is persisted to
`~/Library/Application Support/NotchDeck/state.json`.

## Build

Requirements: macOS 14+, Xcode command line tools (Swift 5.10+), Rust (stable).

```sh
scripts/bundle.sh             # builds dist/NotchDeck.app for this machine
scripts/bundle.sh --universal # arm64 + x86_64 (needs rustup)
open dist/NotchDeck.app
```

For development:

```sh
cargo build --release --manifest-path core/Cargo.toml
swift run
cargo test --manifest-path core/Cargo.toml
```

The app is ad-hoc signed. If macOS blocks a downloaded build, right-click →
Open, or run `xattr -dr com.apple.quarantine NotchDeck.app`.

Quit and "Launch at Login" live in the menu bar icon.

## Roadmap ideas

- Now Playing controls
- Calendar: next event
- Configurable tabs and timer presets
- Keyboard shortcut to toggle the panel

Contributions welcome. MIT licensed.
