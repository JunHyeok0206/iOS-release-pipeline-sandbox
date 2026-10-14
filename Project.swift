import ProjectDescription

let bundleId = "com.junhyeok.testactions"

let project = Project(
    name: "TestApp",
    settings: .settings(
        base: ["CODE_SIGNING_ALLOWED": "NO"],
        configurations: [
            .debug(name: .debug, xcconfig: "Config/Version.xcconfig"),
            .release(name: .release, xcconfig: "Config/Version.xcconfig")
        ]
    ),
    targets: [
        .target(
            name: "TestApp",
            destinations: .iOS,
            product: .app,
            bundleId: bundleId,
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "TestApp/Resources/Info.plist"),
            sources: ["TestApp/Sources/**"],
            dependencies: [
                .target(name: "TestWidget"),
                .external(name: "Alamofire"),
                .external(name: "SnapKit"),
                .external(name: "RxSwift"),
                .external(name: "Kingfisher"),
                .external(name: "Lottie")
            ]
        ),
        .target(
            name: "TestWidget",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "\(bundleId).TestWidget",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "TestWidget/Info.plist"),
            sources: ["TestWidget/Sources/**"]
        )
    ]
)
