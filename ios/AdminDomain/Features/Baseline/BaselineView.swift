import SwiftUI

struct BaselineView: View {
    private let baseline = AppBaseline()

    var body: some View {
        NavigationStack {
            List {
                Section("Mục tiêu") {
                    Label("Ứng dụng quản trị native", systemImage: "iphone")
                    Label("Cài đặt bằng LiveContainer", systemImage: "shippingbox")
                }

                Section("Thiết bị") {
                    LabeledContent("Thiết bị", value: baseline.targetDevice)
                    LabeledContent("iOS", value: baseline.targetIOS)
                    LabeledContent("Runtime", value: baseline.liveContainer)
                }

                Section("Trạng thái") {
                    Label("Scaffold đã sẵn sàng để build IPA", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .navigationTitle(baseline.appName)
        }
    }
}

#Preview {
    BaselineView()
}
