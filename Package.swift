// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Room",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Room", targets: ["Room"]),
    .executable(name: "room-scan", targets: ["RoomScan"]),
  ],
  targets: [
    .target(name: "RoomCore"),
    .executableTarget(name: "Room", dependencies: ["RoomCore"]),
    .executableTarget(name: "RoomScan", dependencies: ["RoomCore"]),
    .testTarget(name: "RoomCoreTests", dependencies: ["RoomCore"]),
  ]
)
