// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let sourcesDirectory = "\(packageDirectory)/Sources"
let moduleMapFile = "\(sourcesDirectory)/module.modulemap"

let package = Package(
    name: "SideScreen",
    platforms: [
        // Floor is ScreenCaptureKit basics (12.3) + OSAllocatedUnfairLock /
        // SCStreamConfiguration.capturesAudio (13.0). CGVirtualDisplay is a
        // private API present well before 13 — it does NOT require 14.
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
            path: "Sources",
            cSettings: [
                .unsafeFlags(["-I", sourcesDirectory])
            ],
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-fmodule-map-file=\(moduleMapFile)"])
            ]),
        .executableTarget(
            name: "SideScreenVirtualHIDHelper",
            dependencies: [],
            path: "VirtualHIDHelperSources",
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-fmodule-map-file=\(moduleMapFile)"])
            ]),
        .testTarget(
            name: "SideScreenTests",
            dependencies: ["SideScreen"],
            path: "Tests/SideScreenTests",
            cSettings: [
                .unsafeFlags(["-I", sourcesDirectory])
            ],
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-fmodule-map-file=\(moduleMapFile)"])
            ]
        )
    ]
)
