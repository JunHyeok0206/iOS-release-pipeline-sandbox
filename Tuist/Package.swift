// swift-tools-version: 5.9
// Timespread 와 같은 방식의 SPM 의존성. deploy.yml 의 캐시(Tuist/.build) 검증용으로 실제 앱이 쓰는 패키지 중 4개를 같은 버전으로 둔다.
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(productTypes: [:])
#endif

let package = Package(
    name: "TestApp",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.9.1"),
        .package(url: "https://github.com/SnapKit/SnapKit", exact: "5.7.1"),
        .package(url: "https://github.com/ReactiveX/RxSwift", exact: "6.8.0"),
        .package(url: "https://github.com/onevcat/Kingfisher", exact: "7.11.0"),
        // 바이너리 아티팩트(GitHub release asset 55MB). Timespread 6.0.5 첫 Deploy 가 이 다운로드에서 멈춘 원인 재현용
        .package(url: "https://github.com/airbnb/lottie-spm", exact: "4.4.3"),
    ]
)
