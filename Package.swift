// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickTranslate",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuickTranslate", targets: ["QuickTranslate"])],
    targets: [
        .target(name: "TranslationCore"),
        .executableTarget(name: "QuickTranslate", dependencies: ["TranslationCore"]),
        .testTarget(name: "TranslationCoreTests", dependencies: ["TranslationCore"]),
        .testTarget(name: "TranslationServiceTests", dependencies: ["QuickTranslate", "TranslationCore"])
    ],
    swiftLanguageModes: [.v5]
)
