// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ios_termios",
    products: [
        .library(
            name: "ios_termios",
            targets: ["ios_termios"]
        ),
    ],
    targets: [
        .target(
            name: "ios_termios",
            publicHeadersPath: "include"
        ),

    ]
)
