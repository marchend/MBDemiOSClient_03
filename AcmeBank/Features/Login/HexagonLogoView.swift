import SwiftUI

/// A flat-top hexagonal "A" logo drawn entirely in SwiftUI.
/// No image asset required — pure Path/Shape rendering.
struct HexagonLogoView: View {
    private let navyColor = Color(red: 0x1B / 255.0, green: 0x2A / 255.0, blue: 0x4A / 255.0)
    private let size: CGFloat = 80

    var body: some View {
        ZStack {
            HexagonShape()
                .fill(navyColor)
                .frame(width: size, height: size)

            Text("A")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - HexagonShape

private struct HexagonShape: Shape {
    /// Draws a flat-top hexagon (first vertex at top-right).
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2.0
        // Flat-top: rotate 30° so the first vertex is at upper-right
        let angleOffset: Double = .pi / 6
        for i in 0 ..< 6 {
            let angle = angleOffset + Double(i) * (.pi / 3)
            let x = cx + CGFloat(cos(angle)) * r
            let y = cy + CGFloat(sin(angle)) * r
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    HexagonLogoView()
        .padding()
}
