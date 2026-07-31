// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AT22",
    // 配布時の動作要件。最終チェックで足りない API が出たら上げる（README にも同じ注記あり）
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "AT22", path: "Sources/AT22")
    ]
)
