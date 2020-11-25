// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "WSAudioKit",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "WSAudioKit",
            targets: ["WSAudioKit"])
    ],
    targets: [
        .target(
            name: "WSAudioKit",
            path: ".",
            sources: ["Source"])
    ]
)
