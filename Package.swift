// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-longhair",
    products: [
      // .library(name: "Longhair", targets: ["Longhair"]),
    ],
    targets: [
      // .target(name: "Longhair", dependencies: ["CLonghair"]),
      .target(
        name: "CLonghair",
        exclude: [
          "docs",
          "tests",
          "CMakeLists.txt",
          "README.md",
        ],
        publicHeadersPath: ".",
        cxxSettings: [
          .define("GF256_TARGET_MOBILE"),
        ],
        
      ),
      .testTarget(name: "LonghairTests",
        dependencies: ["CLonghair"],
        cxxSettings: [
          .define("GF256_TARGET_MOBILE"),
        ],
        swiftSettings: [.interoperabilityMode(.Cxx)]
      ),
    ],
)
