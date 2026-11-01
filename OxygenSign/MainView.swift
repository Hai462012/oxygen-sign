import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @StateObject private var library = FileLibrary()
    @EnvironmentObject private var license: LicenseStore
    @State private var importing = false
    @State private var urlText = ""
    @State private var showURL = false

    var body: some View {
        TabView {
            NavigationView {
                List {
                    Section {
                        Label("Tệp đã nhập: \(library.items.count)", systemImage: "shippingbox")
                        Label("License đã kích hoạt", systemImage: "checkmark.shield.fill")
                    } header: { Text("Tổng quan") }
                    Section("Thao tác") {
                        Button { importing = true } label: { Label("Nhập IPA / P12 / Profile", systemImage: "square.and.arrow.down") }
                        Button { showURL = true } label: { Label("Tải file từ URL", systemImage: "link") }
                    }
                    Section("Ký IPA") {
                        NavigationLink { SigningView() } label: { Label("Ký IPA bằng P12", systemImage: "signature") }
                    }
                }.navigationTitle("Oxygen Sign")
            }.tabItem { Label("Home", systemImage: "house.fill") }
            NavigationView {
                List {
                    ForEach(library.items, id: \.lastPathComponent) { file in
                        HStack {
                            Image(systemName: library.icon(for: file)).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.lastPathComponent).lineLimit(1)
                                Text(library.typeName(for: file)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareFileButton(file: file)
                        }
                    }.onDelete(perform: library.delete)
                }.overlay { if library.items.isEmpty { ContentUnavailableViewFallback() } }
                    .toolbar { Button { importing = true } label: { Image(systemName: "plus") } }
                    .navigationTitle("File Manager")
            }.tabItem { Label("Files", systemImage: "folder.fill") }
            NavigationView {
                List {
                    Section("Chứng chỉ đã nhập") {
                        ForEach(library.items.filter { ["p12", "mobileprovision"].contains($0.pathExtension.lowercased()) }, id: \.lastPathComponent) { file in
                            Label(file.lastPathComponent, systemImage: "checkmark.seal")
                        }
                    }
                    Section { Text("Chứng chỉ P12 và mobileprovision được lưu trong vùng dữ liệu ứng dụng. Sử dụng mục Ký IPA để ký qua signing server HTTPS riêng.").font(.footnote).foregroundStyle(.secondary) }
                }.navigationTitle("Certificates")
            }.tabItem { Label("Certs", systemImage: "checkmark.seal.fill") }
            NavigationView {
                Form {
                    Section("Thông tin") { HStack { Text("Ứng dụng"); Spacer(); Text("Oxygen Sign").foregroundStyle(.secondary) }; HStack { Text("Phiên bản"); Spacer(); Text("1.0").foregroundStyle(.secondary) } }
                    Section("Tài khoản") { Button("Đăng xuất license", role: .destructive) { license.logout() } }
                }.navigationTitle("Settings")
            }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(library)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): urls.forEach { library.importFile($0) }
            case .failure(let error): library.errorMessage = error.localizedDescription
            }
        }
        .alert("Tải từ URL", isPresented: $showURL) {
            TextField("https://example.com/file.ipa", text: $urlText)
            Button("Tải") { Task { await library.download(urlText) } }
            Button("Hủy", role: .cancel) {}
        } message: { Text("Nhập URL trực tiếp tới tệp.") }
        .alert("Lỗi", isPresented: Binding(get: { !library.errorMessage.isEmpty }, set: { if !$0 { library.errorMessage = "" } })) {
            Button("OK", role: .cancel) { library.errorMessage = "" }
        } message: { Text(library.errorMessage) }
    }
}

private struct ContentUnavailableViewFallback: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
            Text("Chưa có tệp nào").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShareFileButton: View {
    let file: URL
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Image(systemName: "square.and.arrow.up") }
            .sheet(isPresented: $showing) { ShareSheet(items: [file]) }
    }
}
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
