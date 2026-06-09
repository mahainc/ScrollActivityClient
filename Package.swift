// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScrollActivityClient",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .singleTargetLibrary("ScrollActivityClient"),
        .singleTargetLibrary("ScrollActivityClientLive"),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.12.0"
        ),
        // Underlying UIScrollView introspection for `trackScrollActivity()`.
        .package(
            url: "https://github.com/siteline/swiftui-introspect",
            "1.3.0"..<"27.0.0"
        ),
    ],
    targets: [
        .target(
            name: "ScrollActivityClient",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "ScrollActivityClientLive",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                "ScrollActivityClient",
            ]
        ),
        .testTarget(
            name: "ScrollActivityClientLiveTests",
            dependencies: [
                "ScrollActivityClient",
                "ScrollActivityClientLive",
            ]
        ),
    ]
)

extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
