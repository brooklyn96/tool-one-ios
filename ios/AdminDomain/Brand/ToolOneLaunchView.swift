import SwiftUI

enum ToolOneLaunchTimeline {
    static let standardDuration: TimeInterval = 1.45
    static let reducedMotionDuration: TimeInterval = 0.15
}

struct ToolOneLaunchView: View {
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 18) {
                FoldedOneMark(progress: reduceMotion ? 1 : progress)
                    .frame(width: 154, height: 154)

                VStack(spacing: 7) {
                    HStack(spacing: 7) {
                        Text("TOOL").foregroundStyle(ToolOneBrand.deep)
                        Text("ONE").foregroundStyle(ToolOneBrand.electric)
                    }
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .tracking(-1.2)

                    Text("MANY TOOLS. ONE FLOW.")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color.secondary)
                }
                .opacity(reduceMotion ? 1 : Double(wordmarkProgress))
                .offset(y: reduceMotion ? 0 : (1 - wordmarkProgress) * 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tool One")
        }
        .onAppear {
            guard !reduceMotion else {
                progress = 1
                return
            }
            withAnimation(.easeInOut(duration: 1.18)) {
                progress = 1
            }
        }
    }

    private var wordmarkProgress: CGFloat {
        min(max((progress - 0.72) / 0.28, 0), 1)
    }
}

struct ToolOneLaunchGate<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = true
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
            if isPresented {
                ToolOneLaunchView(reduceMotion: reduceMotion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            let duration = reduceMotion
                ? ToolOneLaunchTimeline.reducedMotionDuration
                : ToolOneLaunchTimeline.standardDuration
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                isPresented = false
            }
        }
    }
}
