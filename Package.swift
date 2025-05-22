// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let longhairCxxSettings: [CXXSetting] = [
    .define("GF256_TARGET_MOBILE"),
]

let package = Package(
    name: "swift-longhair",
    products: [
      .library(name: "Longhair", targets: ["Longhair"]),
    ],
    targets: [
      .target(
        name: "Longhair", 
        dependencies: ["CLonghair"], 
        cxxSettings: longhairCxxSettings,
        swiftSettings: [.interoperabilityMode(.Cxx)]
      ),
      .target(
        name: "CLonghair",
        exclude: [
          "docs",
          "tests",
          "CMakeLists.txt",
          "README.md",
        ],
        publicHeadersPath: ".",
        cxxSettings: longhairCxxSettings
      ),
      .testTarget(
        name: "LonghairTests",
        dependencies: ["CLonghair", "Longhair"],
        cxxSettings: longhairCxxSettings,
        swiftSettings: [.interoperabilityMode(.Cxx)]
      ),
    ],
)
