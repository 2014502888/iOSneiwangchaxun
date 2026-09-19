import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPicked: (URL) -> Void

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
    }
}

struct ContentView: View {
    @State private var mailNo = ""
    @State private var result = ""
    @State private var isLoading = false
    @State private var showPicker = false

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
                    showPicker = true
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
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                HarImporter.importHar(from: url)
            }
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
