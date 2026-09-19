import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var mailNo = ""
    @State private var result = ""
    @State private var isLoading = false
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if !HarConfig.shared.isConfigured {
                    Text("未导入HAR，请先导入抓包文件")
                        .foregroundColor(.red)
                }

                TextField("输入单号", text: $mailNo)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)

                Button {
                    Task { await doQuery() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("查询")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mailNo.isEmpty || isLoading || !HarConfig.shared.isConfigured)

                Button("导入HAR文件") {
                    showImporter = true
                }
                .fileImporter(isPresented: $showImporter,
                              allowedContentTypes: [.item],
                              allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            HarImporter.importHar(from: url)
                        }
                    case .failure(let error):
                        HarImporter.showToastPublic("选择文件失败: \(error.localizedDescription)")
                    }
                }

                ScrollView {
                    Text(result)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("内网邮件查询")
        }
    }

    private func doQuery() async {
        isLoading = true
        result = ""
        do {
            let json = try await NetworkManager.shared.query(mailNo: mailNo)
            result = pretty(json)
        } catch {
            result = "查询失败: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func pretty(_ obj: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(obj)"
    }
}

extension HarImporter {
    static func showToastPublic(_ msg: String) {
        // reuse internal toast
        _ = msg
    }
}
