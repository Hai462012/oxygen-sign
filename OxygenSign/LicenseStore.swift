import Foundation
import SwiftUI
import Security

@MainActor final class LicenseStore: ObservableObject {
    @Published var isActivated = false
    @Published var errorMessage = ""
    @Published var isLoading = false
    private let apiURL = URL(string: "http://esign.letruonghai.site/api/verify")!
    private let storageKey = "oxygen.license"
    private let deviceKey = "oxygen.device"

    init() { isActivated = UserDefaults.standard.bool(forKey: "oxygen.activated") }

    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    var currentLicense: String { UserDefaults.standard.string(forKey: storageKey) ?? "" }
    var currentDeviceID: String { deviceID }

    func activate(_ key: String) async {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "Nhập license key"; return }
        isLoading = true; errorMessage = ""
        defer { isLoading = false }
        do {
            var req = URLRequest(url: apiURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["key": key.trimmingCharacters(in: .whitespacesAndNewlines), "device_id": deviceID])
            req.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let valid = (json["valid"] as? Bool) ?? (json["success"] as? Bool) ?? false
            if (200...299).contains(http.statusCode) && valid {
                UserDefaults.standard.set(key, forKey: storageKey)
                UserDefaults.standard.set(true, forKey: "oxygen.activated")
                isActivated = true
            } else { errorMessage = (json["message"] as? String) ?? (json["error"] as? String) ?? "Key không hợp lệ hoặc đã được sử dụng" }
        } catch { errorMessage = "Không kết nối được server: \(error.localizedDescription)" }
    }
    func logout() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.set(false, forKey: "oxygen.activated")
        isActivated = false
    }
}
