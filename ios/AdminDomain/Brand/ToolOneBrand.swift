import SwiftUI

enum ToolOneBrand {
    static let deep = Color(hex: 0x0038A9)
    static let electric = Color(hex: 0x0071FE)
    static let cyan = Color(hex: 0x00AFFF)
}

struct FoldedOneMark: View {
    var progress: CGFloat = 1

    var body: some View {
        ZStack {
            facet(
                points: [[27, 42], [127, 42], [109, 61], [27, 61]],
                color: ToolOneBrand.deep
            )
            .mask(horizontalReveal(segment(from: 0, to: 0.28)))

            facet(
                points: [[105, 42], [127, 42], [109, 61], [87, 61]],
                color: ToolOneBrand.cyan
            )
            .opacity(Double(segment(from: 0.22, to: 0.44)))
            .scaleEffect(
                x: segment(from: 0.22, to: 0.44),
                y: segment(from: 0.22, to: 0.44),
                anchor: .bottomLeading
            )

            facet(
                points: [[72, 61], [91, 61], [91, 126], [72, 126]],
                color: ToolOneBrand.deep
            )
            .mask(verticalReveal(segment(from: 0.36, to: 0.64)))

            facet(
                points: [[72, 126], [91, 126], [117, 105], [98, 105]],
                color: ToolOneBrand.electric
            )
            .opacity(Double(segment(from: 0.58, to: 0.82)))
            .scaleEffect(
                x: segment(from: 0.58, to: 0.82),
                y: segment(from: 0.58, to: 0.82),
                anchor: .topLeading
            )

            facet(
                points: [[87, 61], [109, 61], [91, 78], [91, 61]],
                color: ToolOneBrand.electric.opacity(0.42)
            )
            .opacity(Double(segment(from: 0.7, to: 0.9)))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tool One")
    }

    private func facet(points: [[CGFloat]], color: Color) -> some View {
        FoldedOneFacet(points: points.map { CGPoint(x: $0[0], y: $0[1]) })
            .fill(color)
    }

    private func segment(from start: CGFloat, to end: CGFloat) -> CGFloat {
        min(max((progress - start) / (end - start), 0), 1)
    }

    private func horizontalReveal(_ amount: CGFloat) -> some View {
        GeometryReader { proxy in
            Rectangle()
                .frame(width: proxy.size.width * amount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func verticalReveal(_ amount: CGFloat) -> some View {
        GeometryReader { proxy in
            Rectangle()
                .frame(height: proxy.size.height * amount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct FoldedOneFacet: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        let xScale = rect.width / 164
        let yScale = rect.height / 164
        path.move(to: CGPoint(x: first.x * xScale, y: first.y * yScale))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * xScale, y: point.y * yScale))
        }
        path.closeSubpath()
        return path
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
