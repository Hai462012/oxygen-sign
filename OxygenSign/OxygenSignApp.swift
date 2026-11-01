import SwiftUI

@main
struct OxygenSignApp: App {
    @StateObject private var license = LicenseStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if license.isActivated { MainView() }
                else { ActivationView() }
            }
            .environmentObject(license)
        }
    }
}
