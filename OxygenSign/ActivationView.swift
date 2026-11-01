import SwiftUI

struct ActivationView: View {
    @EnvironmentObject var license: LicenseStore
    @State private var key = ""
    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.24), .blue.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "signature")
                    .font(.system(size: 62, weight: .light)).foregroundStyle(.blue)
                    .frame(width: 110, height: 110).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
                Text("Oxygen Sign").font(.largeTitle.bold())
                Text("Nhập license key để bắt đầu").foregroundStyle(.secondary)
                TextField("License Key", text: $key).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().textFieldStyle(.roundedBorder)
                if !license.errorMessage.isEmpty {
                    Text(license.errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button {
                    Task { await license.activate(key) }
                } label: {
                    HStack { if license.isLoading { ProgressView().tint(.white) }; Text("Kích hoạt").bold() }
                        .frame(maxWidth: .infinity).padding(12)
                }.buttonStyle(.borderedProminent).disabled(license.isLoading)
                Spacer()
                Text("Oxygen Sign • iOS 15+").font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 470)
        }
    }
}
