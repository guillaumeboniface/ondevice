// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OfflineInference",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "OfflineInference", targets: ["OfflineInference"])],
    dependencies: [
        .package(path: "vendor/moonshine"),
        .package(path: "vendor/phonon")
    ],
    targets: [
        .binaryTarget(name: "llama", path: "Frameworks/llama.xcframework"),
        .target(name: "OfflineInference", dependencies: [
            "llama", .product(name: "MoonshineVoice", package: "moonshine")
        ], path: "App", exclude: ["Audio", "Resources", "Info.plist", "OnDeviceApp.swift", "ConversationView.swift", "Core/ConversationController.swift", "Core/Diagnostics.swift", "Inference/PhononSynthesizer.swift"],
        sources: ["Core/Inference.swift", "Inference/MoonshineRecognizer.swift", "Inference/LlamaLanguageModel.swift"]),
        .testTarget(name: "OfflineInferenceTests", dependencies: [
            "OfflineInference", .product(name: "ptts", package: "phonon")
        ], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
