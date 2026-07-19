import SwiftUI

enum ToolOneLayout {
    static let spacingXS: CGFloat = 8
    static let spacingS: CGFloat = 16
    static let spacingM: CGFloat = 24
    static let spacingL: CGFloat = 32
    static let minimumTouchTarget: CGFloat = 44
    static let cardRadius: CGFloat = 20
}

enum ToolOneSurface {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border = Color(uiColor: .separator).opacity(0.28)
}

enum ToolOneFriendlyError {
    static func message(for error: Error) -> String {
        let value = error as NSError
        let raw = value.localizedDescription
        let technical = "\(value.domain) \(raw)".lowercased()

        if value.domain == NSURLErrorDomain {
            return "Không thể kết nối. Kiểm tra mạng rồi thử lại."
        }
        if technical.contains("authenticationservices") || technical.contains("webauthentication") {
            return value.code == 1
                ? "Đăng nhập đã được đóng. Bạn có thể thử lại khi sẵn sàng."
                : "Chưa thể mở đăng nhập Google. Vui lòng thử lại."
        }
        if value.domain.hasPrefix("tab.") || raw.range(of: #"^[a-z]+\.[a-z0-9._-]+$"#, options: .regularExpression) != nil {
            return "Đã có lỗi xảy ra. Vui lòng thử lại."
        }
        return raw.isEmpty ? "Đã có lỗi xảy ra. Vui lòng thử lại." : raw
    }
}

struct ToolOneMotion<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: value)
    }
}

extension View {
    func toolOneCard() -> some View {
        padding(ToolOneLayout.spacingS)
            .background(ToolOneSurface.card, in: RoundedRectangle(cornerRadius: ToolOneLayout.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ToolOneLayout.cardRadius, style: .continuous)
                    .stroke(ToolOneSurface.border, lineWidth: 1)
            }
    }
}
