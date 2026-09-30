// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ExorciseCore", platforms: [.macOS(.v13)],
  products: [.library(name: "ExorciseCore", targets: ["ExorciseCore"])],
  targets: [
    .target(name: "ExorciseCore", path: "Exorcise Anything/Core"),
    .testTarget(name: "ExorciseCoreTests", dependencies: ["ExorciseCore"], path: "Tests"),
  ])
