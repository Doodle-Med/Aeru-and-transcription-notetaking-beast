// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperControlMobile",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WhisperControlMobile",
            targets: ["WhisperControlMobile"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.14.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
        .package(url: "https://github.com/johnmai-dev/Jinja", exact: "1.3.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "0.1.15"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/Dripfarm/SVDB.git", from: "2.0.0"),
        .package(url: "https://github.com/gonzalezreal/MarkdownUI.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "WhisperControlMobile",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Jinja", package: "Jinja"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "SVDB", package: "SVDB"),
                .product(name: "MarkdownUI", package: "MarkdownUI")
            ],
            path: "Sources/WhisperControlMobile"
        ),
        .testTarget(
            name: "WhisperControlMobileTests",
            dependencies: ["WhisperControlMobile"],
            path: "Tests/WhisperControlMobileTests"
        )
    ]
)