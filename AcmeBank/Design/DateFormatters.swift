import Foundation

/// Shared date formatters for the Home screen.
///
/// The transaction-row design calls for `"MMM d, yyyy"` formatted
/// dates \(e.g. `"Jun 8, 2026"`\). `DateFormatter` is expensive to
/// allocate, so we share a single instance behind a `static let` -
/// `DateFormatter` is documented thread-safe for read-only use after
/// configuration.
enum DateFormatters {

    /// `"MMM d, yyyy"` - the canonical posted-date format used by
    /// every `TransactionRow`. Locale-pinned to `en_US_POSIX` so the
    /// output is stable across device locales; a future localisation
    /// pass would swap this for `Locale.current` and a localized
    /// template.
    ///
    /// The BFF emits `posted_date` as a full ISO-8601 UTC timestamp.
    /// We render the calendar date in the device's CURRENT time zone
    /// (no `timeZone` override) so a transaction posted at
    /// 2024-06-08T03:00:00Z still reads as "Jun 8" for a user on
    /// UTC or Eastern time. Tests that need deterministic output
    /// pick a timestamp far from midnight in any of the common
    /// device locales (e.g. noon UTC).
    static let postedDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// Convenience wrapper so callers don't have to know the
    /// formatter exists.
    static func formatPostedDate(_ date: Date) -> String {
        return postedDate.string(from: date)
    }
}
