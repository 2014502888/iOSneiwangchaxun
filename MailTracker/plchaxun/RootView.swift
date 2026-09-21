import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                Text("选择系统")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(25)
                NavigationLink {
                    InternalView()
                } label: {
                    Text("内网查询")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(25)
                }
                NavigationLink {
                    ExternalView()
                } label: {
                    Text("外网查询")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(25)
                }
                Spacer()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}