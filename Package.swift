// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AT22",
    // 配布時の動作要件。最終チェックで足りない API が出たら上げる（README にも同じ注記あり）
    platforms: [.macOS("15.0")],
    // 唯一の外部依存。端末（09 TERMINAL）のため。チャットが主・端末は脱出口
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.20.0")
    ],
    targets: [
        .executableTarget(name: "AT22",
                          dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
                          path: "Sources/AT22")
    ]
)
