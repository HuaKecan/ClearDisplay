// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClearDisplay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClearDisplay", targets: ["ClearDisplay"]),
        .executable(name: "DisplayRescue", targets: ["DisplayRescue"]),
        .executable(name: "DisplayVirtualHost", targets: ["DisplayVirtualHost"])
    ],
    targets: [
        .target(name: "DisplayCore"),
        .target(name: "VirtualDisplayBridge", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]),
        .target(name: "DisplayRuntime", dependencies: ["DisplayCore", "VirtualDisplayBridge"],
                linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreGraphics")]),
        .executableTarget(name: "ClearDisplay", dependencies: ["DisplayCore", "DisplayRuntime"]),
        .executableTarget(name: "DisplayRescue", dependencies: ["DisplayCore", "DisplayRuntime"]),
        .executableTarget(name: "DisplayVirtualHost", dependencies: ["VirtualDisplayBridge"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreGraphics")]),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
        .testTarget(name: "DisplayRuntimeTests", dependencies: ["DisplayRuntime", "DisplayCore"])
    ],
    swiftLanguageModes: [.v5]
)
