import SwiftUI

/// Monochrome capsule pill that renders a customer segment label
/// (e.g. "PREMIER") trailing the customer name in `SignedInCard`.
///
/// Strictly monochrome: `Color.white.opacity(0.15)` background,
/// `.foregroundColor(.white)`, `.capsule` clip shape,
/// `.caption.weight(.semibold)` font. No accent colour anywhere.
///
/// The call site is responsible for unwrapping `Customer.segment?`
/// and only instantiating this view when a segment value is present.
struct SegmentBadgeView: View {
    let segment: String

    var body: some View {
        Text(segment.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
    }
}

#Preview {
    ZStack {
        BankPalette.navy.ignoresSafeArea()
        SegmentBadgeView(segment: "PREMIER")
            .padding()
    }
}
