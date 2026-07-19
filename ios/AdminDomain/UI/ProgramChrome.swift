import SwiftUI

struct ProgramHeader: View {
    let title: String
    let state: ProgramState?
    let onBack: () -> Void
    let onRefresh: (() -> Void)?

    var body: some View {
        HStack(spacing: ToolOneLayout.spacingXS) {
            Button(action: onBack) {
                Label("Tool One", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .frame(minWidth: ToolOneLayout.minimumTouchTarget, minHeight: ToolOneLayout.minimumTouchTarget)
            .accessibilityHint("Quay lại không gian Tool One")

            Spacer(minLength: ToolOneLayout.spacingXS)

            VStack(spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                if let state { StatusPill(state: state, compact: true) }
            }

            Spacer(minLength: ToolOneLayout.spacingXS)

            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: ToolOneLayout.minimumTouchTarget, height: ToolOneLayout.minimumTouchTarget)
                }
                .accessibilityLabel("Làm mới \(title)")
            } else {
                Color.clear.frame(width: ToolOneLayout.minimumTouchTarget, height: ToolOneLayout.minimumTouchTarget)
            }
        }
        .padding(.horizontal, ToolOneLayout.spacingXS)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct StatusPill: View {
    let state: ProgramState
    var compact = false

    var body: some View {
        Label(label, systemImage: symbol)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 2 : 5)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Trạng thái: \(label)")
    }

    private var label: String {
        switch state {
        case .online: return "Sẵn sàng"
        case .degraded: return "Gián đoạn"
        case .offline: return "Ngoại tuyến"
        case .unknown: return "Đang kiểm tra"
        }
    }

    private var symbol: String {
        switch state {
        case .online: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        case .unknown: return "clock"
        }
    }

    private var color: Color {
        switch state {
        case .online: return .green
        case .degraded: return .orange
        case .offline: return .red
        case .unknown: return .secondary
        }
    }
}

struct FreshnessLabel: View {
    let date: Date
    let stale: Bool

    var body: some View {
        Label {
            Text(stale ? "Dữ liệu đã lưu · \(date, style: .relative)" : "Cập nhật \(date, style: .relative)")
        } icon: {
            Image(systemName: stale ? "clock.badge.exclamationmark" : "checkmark.circle")
        }
        .font(.footnote)
        .foregroundStyle(stale ? .orange : .secondary)
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: ToolOneLayout.spacingXS) {
            Label(label, systemImage: systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolOneCard()
        .accessibilityElement(children: .combine)
    }
}

struct PrimaryProgramButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: ToolOneLayout.minimumTouchTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(ToolOneBrand.electric)
    }
}
