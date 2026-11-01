import Foundation
import SwiftUI

/// Signs via an administrator-operated HTTPS service running the zsign executable.
/// The P12 and password are transmitted to that server for this request only.
@MainActor final class SigningStore: ObservableObject {
    @Published var isSigning = false
    @Published var progressText = ""
    @Published var errorMessage = ""
    @Published var signedURL: URL?
    @Published var installManifestURL: URL?
    @AppStorage("oxygen.signEndpoint") var endpoint = ""

    func sign(ipa: URL, p12: URL, profile: URL, password: String, license: String, deviceID: String, library: FileLibrary) async {
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https", url.path.hasSuffix("/api/sign/install") else {
            errorMessage = "Cấu hình HTTPS URL kết thúc bằng /api/sign/install trong Settings"; return
        }
        guard !license.isEmpty, !deviceID.isEmpty else { errorMessage = "Cần license hợp lệ"; return }
        isSigning = true; errorMessage = ""; signedURL = nil; installManifestURL = nil; progressText = "Đang chuẩn bị tệp…"
        defer { isSigning = false; progressText = "" }
        do {
            let boundary = "OXYGEN-" + UUID().uuidString
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".multipart")
            defer { try? FileManager.default.removeItem(at: temp) }
            FileManager.default.createFile(atPath: temp.path, contents: nil)
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            func write(_ text: String) throws { try handle.write(contentsOf: Data(text.utf8)) }
            func field(_ name: String, _ value: String) throws {
                try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
            }
            func attachment(_ fieldName: String, _ file: URL) throws {
                try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fieldName)\"; filename=\"upload.\(file.pathExtension)\"\r\nContent-Type: application/octet-stream\r\n\r\n")
                let input = try FileHandle(forReadingFrom: file)
                defer { try? input.close() }
                while true {
                    let piece = try input.read(upToCount: 1024 * 1024) ?? Data()
                    if piece.isEmpty { break }
                    try handle.write(contentsOf: piece)
                }
                try write("\r\n")
            }
            try field("key", license)
            try field("device_id", deviceID)
            try field("p12_password", password)
            try attachment("ipa", ipa)
            try attachment("p12", p12)
            try attachment("profile", profile)
            try write("--\(boundary)--\r\n")
            try handle.synchronize()
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 600
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            progressText = "Đang gửi tệp và ký trên server…"
            let (responseFile, response) = try await URLSession.shared.upload(for: req, fromFile: temp)
            defer { try? FileManager.default.removeItem(at: responseFile) }
            guard let http = response as? HTTPURLResponse else { throw SigningError.message("Không nhận được phản hồi HTTP") }
            guard (200...299).contains(http.statusCode) else {
                let body = (try? Data(contentsOf: responseFile)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                throw SigningError.message("Server lỗi \(http.statusCode): \(String(body.prefix(300)))")
            }
            let info = try JSONDecoder().decode(InstallResponse.self, from: Data(contentsOf: responseFile))
            guard info.ok, let fileURL = URL(string: info.ipa_url), fileURL.scheme == "https",
                  let manifest = URL(string: info.manifest_url), manifest.scheme == "https",
                  fileURL.host == url.host, manifest.host == url.host else {
                throw SigningError.message("Signing server trả URL không hợp lệ")
            }
            progressText = "Đang tải IPA đã ký…"
            let (downloaded, downloadResponse) = try await URLSession.shared.download(from: fileURL)
            guard (downloadResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw SigningError.message("Không tải được IPA đã ký")
            }
            let destination = library.destination(for: "Oxygen-Signed-\(UUID().uuidString.prefix(8)).ipa")
            try FileManager.default.copyItem(at: downloaded, to: destination)
            library.refresh()
            signedURL = destination
            installManifestURL = manifest
            progressText = "Đã ký xong — có thể chọn Cài IPA"
        } catch { errorMessage = "Ký IPA thất bại: \(error.localizedDescription)" }
    }
}

enum SigningError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

private struct InstallResponse: Decodable {
    let ok: Bool
    let ipa_url: String
    let manifest_url: String
}
