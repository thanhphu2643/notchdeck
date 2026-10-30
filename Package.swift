// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CNotchCore", path: "Sources/CNotchCore"),
        .executableTarget(
            name: "NotchDeck",
            dependencies: ["CNotchCore"],
            linkerSettings: [
                // Build the Rust core first: `cargo build --release --manifest-path core/Cargo.toml`
                .unsafeFlags(["-L", Context.packageDirectory + "/core/target/release"]),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
    ]
)
