import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
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
            .navigationTitle("快递查询")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
