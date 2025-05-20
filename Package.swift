// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-longhair",
    products: [
    ],
    targets: [
      .target(
        name: "CLonghair",
        exclude: [
          "CMakeLists.txt",
          "README.md",
        ],
        sources: [
          "cauchy_256.cpp",
          "cauchy_256.h",
          "gf256.cpp",
          "gf256.h",
          "SiameseTools.cpp",
          "SiameseTools.h"
        ],
        publicHeadersPath: ".",
        cSettings: [
          .define("GF256_TARGET_MOBILE"),
        ]
      )
    ]
)
