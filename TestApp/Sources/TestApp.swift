import SwiftUI
import Alamofire
import Kingfisher
import RxSwift
import SnapKit
import Toast_Swift

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("iOS-release-pipeline-sandbox")
                Text(versionString)
                Text(dependencyNames).font(.caption)
            }
        }
    }

    // SPM(Alamofire·Kingfisher·RxSwift·SnapKit)·CocoaPods(Toast-Swift) 가 실제로 링크되는지 확인용
    private var dependencyNames: String {
        [Session.self, KingfisherManager.self, DisposeBag.self, ConstraintMaker.self, ToastManager.self]
            .map { String(describing: $0) }.joined(separator: " ")
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "-"
        let build = info["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}
// qa fix 1
// qa fix 2
// qa fix 3
// fix
