import SwiftUI

enum AsyncPresentationState: Equatable {
    case loading(message: String)
    case empty(title: String, message: String, systemImage: String)
    case failure(title: String, message: String)
    case content
}

struct AsyncStateView<Content: View>: View {
    let state: AsyncPresentationState
    let retry: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        state: AsyncPresentationState,
        retry: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.state = state
        self.retry = retry
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        switch state {
        case .loading(let message):
            VStack(spacing: ToolOneLayout.spacingS) {
                ProgressView()
                Text(message).font(.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty(let title, let message, let systemImage):
            messageView(title: title, message: message, systemImage: systemImage, tint: ToolOneBrand.electric)
        case .failure(let title, let message):
            messageView(title: title, message: message, systemImage: "exclamationmark.triangle", tint: .orange)
        case .content:
            content()
        }
    }

    private func messageView(title: String, message: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: ToolOneLayout.spacingS) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry {
                Button("Thử lại", action: retry)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: ToolOneLayout.minimumTouchTarget)
            }
        }
        .padding(ToolOneLayout.spacingM)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
