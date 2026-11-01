import Foundation

@MainActor final class FileLibrary: ObservableObject {
    @Published var items: [URL] = []
    @Published var errorMessage = ""
    private let folder: URL
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("Imported", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
    }
    func refresh() {
        items = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func importFile(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let dest = uniqueURL(for: url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            refresh()
        } catch { errorMessage = "Không nhập được tệp: \(error.localizedDescription)" }
    }
    func download(_ raw: String) async {
        guard let url = URL(string: raw), url.scheme == "https" else { errorMessage = "Vui lòng dùng URL HTTPS hợp lệ"; return }
        do {
            let (temp, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let name = url.lastPathComponent.isEmpty ? "download.ipa" : url.lastPathComponent
            try FileManager.default.moveItem(at: temp, to: uniqueURL(for: name))
            refresh()
        } catch { errorMessage = "Không tải được: \(error.localizedDescription)" }
    }
    func delete(at offsets: IndexSet) {
        for index in offsets { try? FileManager.default.removeItem(at: items[index]) }
        refresh()
    }
    func icon(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "ipa": return "shippingbox.fill"
        case "p12": return "key.fill"
        case "mobileprovision": return "checkmark.shield.fill"
        default: return "doc.fill"
        }
    }
    func typeName(for file: URL) -> String { file.pathExtension.uppercased() }
    func destination(for name: String) -> URL { uniqueURL(for: name) }
    private func uniqueURL(for name: String) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return folder.appendingPathComponent("\(base)-\(UUID().uuidString.prefix(8))" + (ext.isEmpty ? "" : ".\(ext)"))
    }
}
