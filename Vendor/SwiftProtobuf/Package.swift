// swift-tools-version: 5.8
// SwiftProtobuf 1.29.0 (d72aed98f8253ec1aa9ea1141e28150f408cf17f).
// Runtime sources are unmodified. See LICENSE.txt.
import PackageDescription

let package = Package(
    name: "SwiftProtobuf",
    products: [.library(name: "SwiftProtobuf", targets: ["SwiftProtobuf"])],
    targets: [
        .target(name: "SwiftProtobuf", exclude: ["CMakeLists.txt"],
                resources: [.copy("PrivacyInfo.xcprivacy")])
    ]
)
