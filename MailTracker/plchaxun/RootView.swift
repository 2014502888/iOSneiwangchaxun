import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaicar = false

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var pageBg: Color { isDark ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    Spacer().frame(height: 8)
                    Text("选择系统")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(fg)
                        .padding(.top, 24)
                        .padding(.bottom, 12)

                    entryButton("内网查询") { InternalView() }
                    entryButton("外网查询") { ExternalView() }
                    entryButton("网址助手") { WebHelperView() }
                    entryButton("远程开机") { RemoteBootView() }

                    // 派车模块（受控 pop：内部发 paicarBackToRoot 通知可退出）
                    NavigationLink(destination: PaicarModuleView().paicarAuthGuard(), isActive: $showPaicar) {
                        Text("寄递派车")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 16)
                            .background(blue)
                            .cornerRadius(25)
                    }

                    Spacer().frame(height: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
            .background(pageBg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .onReceive(NotificationCenter.default.publisher(for: .paicarBackToRoot)) { _ in
            showPaicar = false
        }
    }

    private var blue: Color { Color(red: 0.08, green: 0.28, blue: 0.75) }

    private func entryButton<D: View>(_ title: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(blue)
                .cornerRadius(25)
        }
    }
}
