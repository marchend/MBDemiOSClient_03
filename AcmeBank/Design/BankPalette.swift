import SwiftUI

/// The Acme Bank monochrome design palette.
///
/// The Home screen's visual contract is **strictly monochrome**: navy,
/// white, and greys only. There are no semantic colours \(no red for
/// negative balances, no green for credits\) \- the leading U+2212
/// minus sign is the only signal a transaction or balance is negative.
///
/// Centralising every colour token here gives the PR-3 reviewer one
/// file to grep for accidental `Color.red` / `Color.green` literals,
/// and makes future theme changes \(dark-mode tweaks, a re-brand\) a
/// single-file edit. Every component view in `Home/View/Components/`
/// reads its colours from this enum and **never** instantiates
/// `Color\(red:green:blue:\)` inline.
///
/// All values are `Color` constants \(not `UIColor`\) so SwiftUI views
/// can reference them directly. The hex values are chosen to render
/// the same in light mode \(the only mode shipped today\); the
/// `secondaryText` token uses `.secondary` so it still adapts in dark
/// mode the day we enable it.
enum BankPalette {

    /// Primary brand navy. Used for the brand bar logo tile, the
    /// signed-in card background, account-row icon tiles, and the
    /// Log out button's symbol/label.
    static let navy = Color(red: 0.07, green: 0.13, blue: 0.27)

    /// Slightly lighter navy used as an accent inside the signed-in
    /// card \(avatar background\) to give the card a subtle two-tone
    /// without breaking the monochrome contract.
    static let navyAlt = Color(red: 0.12, green: 0.20, blue: 0.38)

    /// Page background \- near-white with a hint of warmth so the
    /// white surface cards visibly float above it.
    static let background = Color(red: 0.97, green: 0.97, blue: 0.97)

    /// Card / row surface \- pure white. Account rows, transaction
    /// rows, and section bodies sit on this colour.
    static let surface = Color.white

    /// Primary text \(near-black/navy\). Headlines, account names,
    /// amounts \- every piece of text that is NOT a caption.
    static let primaryText = Color(red: 0.07, green: 0.10, blue: 0.18)

    /// Secondary text \(grey\). Subtitles, captions, the "available"
    /// subtext under a negative balance, formatted dates on
    /// transaction rows. Uses the system `.secondary` token so it
    /// adapts cleanly when dark mode lands.
    static let secondaryText = Color.secondary

    /// Inverted text \(white\) for use on top of the navy card / navy
    /// icon tiles. Kept as a named token so a reviewer doesn't have
    /// to wonder whether a stray `.white` is intentional.
    static let onNavy = Color.white
}
