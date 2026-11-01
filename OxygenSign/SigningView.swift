import SwiftUI

struct SigningView: View {
    @EnvironmentObject private var library: FileLibrary
    @EnvironmentObject private var license: LicenseStore
    @StateObject private var signer = SigningStore()
    @State private var ipaName = ""
    @State private var certName = ""
    @State private var profileName = ""
    @State private var password = ""
    @Environment(\.openURL) private var openURL
    private var ipas: [URL] { library.items.filter { $0.pathExtension.lowercased() == "ipa" } }
    private var certificates: [URL] { library.items.filter { $0.pathExtension.lowercased() == "p12" } }
    private var profiles: [URL] { library.items.filter { $0.pathExtension.lowercased() == "mobileprovision" } }
    private func selected(_ name: String, in files: [URL]) -> URL? { files.first { $0.lastPathComponent == name } }

    var body: some View {
        Form {
            Section("IPA cần ký") {
                Picker("IPA", selection: $ipaName) {
                    Text("Chọn IPA").tag("")
                    ForEach(ipas, id: \.lastPathComponent) { Text($0.lastPathComponent).tag($0.lastPathComponent) }
                }
            }
            Section("Chứng chỉ") {
                Picker("P12", selection: $certName) {
                    Text("Chọn P12").tag("")
                    ForEach(certificates, id: \.lastPathComponent) { Text($0.lastPathComponent).tag($0.lastPathComponent) }
                }
                Picker("Provisioning", selection: $profileName) {
                    Text("Chọn Profile").tag("")
                    ForEach(profiles, id: \.lastPathComponent) { Text($0.lastPathComponent).tag($0.lastPathComponent) }
                }
                SecureField("Mật khẩu P12", text: $password)
            }
            Section("Signing server") {
                TextField("https://sign.example.com/api/sign/install", text: $signer.endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("Ứng dụng gửi chứng chỉ và mật khẩu qua HTTPS đến server riêng của bạn; không lưu mật khẩu P12.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button { startSigning() } label: {
                    HStack {
                        if signer.isSigning { ProgressView() }
                        Label("Ký IPA bằng P12", systemImage: "signature")
                    }
                }
                .disabled(signer.isSigning || selected(ipaName, in: ipas) == nil || selected(certName, in: certificates) == nil || selected(profileName, in: profiles) == nil)
                if !signer.progressText.isEmpty { Text(signer.progressText).font(.footnote) }
                if !signer.errorMessage.isEmpty { Text(signer.errorMessage).foregroundStyle(.red).font(.footnote) }
                if let signed = signer.signedURL {
                    ShareLink(item: signed) { Label("Chia sẻ IPA đã ký", systemImage: "square.and.arrow.up") }
                }
                if let manifest = signer.installManifestURL {
                    Button {
                        guard let encoded = manifest.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                              let otaURL = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else { return }
                        openURL(otaURL)
                    } label: { Label("Cài IPA lên iPhone", systemImage: "iphone.and.arrow.forward") }
                }
            }
            Section("Cài đặt") {
                Text("Nút Cài IPA chỉ hoạt động khi chứng chỉ và provisioning profile cho phép cài trên iPhone này (ví dụ Ad Hoc đã đăng ký UDID hoặc Enterprise hợp lệ). iOS có quyền từ chối. Liên kết cài đặt HTTPS tự hết hạn.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Ký IPA")
    }
    private func startSigning() {
        guard let ipa = selected(ipaName, in: ipas), let cert = selected(certName, in: certificates), let profile = selected(profileName, in: profiles) else { return }
        Task { await signer.sign(ipa: ipa, p12: cert, profile: profile, password: password, license: license.currentLicense, deviceID: license.currentDeviceID, library: library) }
    }
}
