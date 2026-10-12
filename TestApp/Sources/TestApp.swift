import SwiftUI

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("iOS-release-pipeline-sandbox")
                Text(versionString)
            }
        }
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
