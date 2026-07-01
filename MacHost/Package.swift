// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SideScreen",
    platforms: [
        // Floor is ScreenCaptureKit basics (12.3) + OSAllocatedUnfairLock /
        // SCStreamConfiguration.capturesAudio (13.0).
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SideScreen",
            targets: ["SideScreen"]),
        .executable(
            name: "SideScreenVirtualHIDHelper",
            targets: ["SideScreenVirtualHIDHelper"])
    ],
    targets: [
        .executableTarget(
            name: "SideScreen",
            dependencies: [],
            path: "Sources"),
        .executableTarget(
            name: "SideScreenVirtualHIDHelper",
            dependencies: [],
            path: "VirtualHIDHelperSources"),
        .testTarget(
            name: "SideScreenTests",
            dependencies: ["SideScreen"],
            path: "Tests/SideScreenTests"
        )
    ]
)
