import XCTest
@testable import AcmeBank

/// Non-snapshot rendering assertions.
///
/// These tests exercise the **derived string** APIs on `AccountRow` and
/// `TransactionRow` (and indirectly `MoneyFormatter` /
/// `DateFormatters`). They deliberately do NOT instantiate
/// `UIHostingController` or take PNG snapshots - the strings are the
/// product of the design contract, and asserting on them in isolation
/// is what keeps a future visual tweak from accidentally breaking the
/// AC's wording.
///
/// What's covered (per the plan's "Tests required" list):
///   - title-case Type ("CHEQUING" \u2192 "Chequing"),
///   - masked-number subtitle shape,
///   - negative balance formatting with U+2212,
///   - available-balance subtext only on negatives,
///   - transaction date formatted "MMM d, yyyy",
///   - avatar letter falls back to `description` when
///     `merchant_name` is nil.
final class HomeViewModelRenderingTests: XCTestCase {

    // MARK: - Helpers

    private func makeAccount(
        type: AccountType,
        balance: Decimal,
        availableBalance: Decimal? = nil,
        maskedNumber: String = "************1234",
        currencyCode: String = "USD"
    ) -> Account {
        return Account(
            id: "acct-1",
            name: "Primary Account",
            maskedNumber: maskedNumber,
            balance: balance,
            availableBalance: availableBalance ?? balance,
            type: type,
            currencyCode: currencyCode
        )
    }

    private func makeTransaction(
        description: String = "Coffee",
        merchantName: String? = nil,
        amount: Decimal = Decimal(-4.25),
        postedDate: Date = Date(timeIntervalSince1970: 1_717_833_600)
    ) -> Transaction {
        // 2024-06-08T08:00:00Z - chosen so the date renders as
        // "Jun 8, 2024" in en_US_POSIX regardless of device locale.
        return Transaction(
            id: "tx-1",
            accountId: "acct-1",
            description: description,
            amount: amount,
            postedDate: postedDate,
            category: nil,
            merchantName: merchantName
        )
    }

    // MARK: - Title-case Type

    func test_accountRow_titleCases_chequingType() {
        let account = makeAccount(type: .chequing, balance: 100)

        let subtitle = AccountRow.subtitle(for: account)

        XCTAssertTrue(subtitle.hasPrefix("Chequing "),
                      "Wire-uppercase 'CHEQUING' must render title-cased as 'Chequing'. Got: \(subtitle)")
        XCTAssertFalse(subtitle.contains("CHEQUING"),
                       "Subtitle must NOT contain the wire-uppercase form.")
    }

    func test_accountRow_titleCases_allKnownTypes() {
        let cases: [(AccountType, String)] = [
            (.chequing,   "Chequing"),
            (.savings,    "Savings"),
            (.credit,     "Credit"),
            (.investment, "Investment")
        ]

        for (type, expected) in cases {
            XCTAssertEqual(AccountRow.titleCased(type), expected,
                           "Unexpected title-case for \(type).")
        }
    }

    // MARK: - Masked-number subtitle

    func test_accountRow_subtitle_endsWithLast4OfMaskedNumber() {
        let account = makeAccount(
            type: .savings,
            balance: 200,
            maskedNumber: "************7890"
        )

        let subtitle = AccountRow.subtitle(for: account)

        XCTAssertTrue(subtitle.hasSuffix(" 7890"),
                      "Subtitle must end with a space and the last 4 of the masked number. Got: \(subtitle)")
        // The U+00B7 separator + four-dot mask, then a space, then
        // the last 4. Spelled out so a reviewer can see exactly what
        // we render.
        let expectedTail = "\u{00B7} \u{00B7}\u{00B7}\u{00B7}\u{00B7} 7890"
        XCTAssertTrue(subtitle.hasSuffix(expectedTail),
                      "Subtitle must end with the '\u{00B7} \u{00B7}\u{00B7}\u{00B7}\u{00B7} <last4>' tail. Got: \(subtitle)")
    }

    func test_accountRow_lastFour_returnsWholeStringWhenShorterThan4() {
        XCTAssertEqual(AccountRow.lastFour(of: "12"), "12",
                       "Masked numbers shorter than 4 must be returned whole rather than crashing on a suffix slice.")
    }

    // MARK: - Negative balance formatting (U+2212)

    func test_accountRow_negativeBalance_usesUnicodeMinus() {
        let account = makeAccount(type: .credit, balance: Decimal(-123.45))

        let formatted = AccountRow.formattedBalance(for: account)

        XCTAssertTrue(formatted.contains("\u{2212}"),
                      "Negative balance must use U+2212 MINUS SIGN (not ASCII '-'). Got: \(formatted)")
        XCTAssertFalse(formatted.contains("-"),
                       "Negative balance must NOT contain ASCII hyphen-minus. Got: \(formatted)")
    }

    func test_accountRow_positiveBalance_hasNoMinusSign() {
        let account = makeAccount(type: .chequing, balance: Decimal(50))

        let formatted = AccountRow.formattedBalance(for: account)

        XCTAssertFalse(formatted.contains("\u{2212}"),
                       "Positive balance must not carry a U+2212. Got: \(formatted)")
        XCTAssertFalse(formatted.contains("-"),
                       "Positive balance must not carry an ASCII hyphen-minus. Got: \(formatted)")
    }

    // MARK: - Available-balance subtext only on negatives

    func test_accountRow_trailingSubtext_isCurrencyCode_onPositiveBalance() {
        let account = makeAccount(
            type: .chequing,
            balance: Decimal(100),
            availableBalance: Decimal(80),
            currencyCode: "CAD"
        )

        XCTAssertEqual(AccountRow.trailingSubtext(for: account), "CAD",
                       "Positive balances show the ISO currency code as the trailing subtext.")
    }

    func test_accountRow_trailingSubtext_isAvailableBalance_onNegativeBalance() {
        let account = makeAccount(
            type: .credit,
            balance: Decimal(-500),
            availableBalance: Decimal(1500),
            currencyCode: "USD"
        )

        let subtext = AccountRow.trailingSubtext(for: account)

        XCTAssertTrue(subtext.hasSuffix(" available"),
                      "Negative balances show '<available_balance> available'. Got: \(subtext)")
        // The available_balance value itself is positive (1500) so
        // it must NOT carry a U+2212.
        XCTAssertFalse(subtext.contains("\u{2212}"),
                       "Available-balance subtext is positive and must not carry a minus sign.")
    }

    // MARK: - Transaction date formatted "MMM d, yyyy"

    func test_transactionRow_formattedDate_usesMMMdyyyy() {
        // 2024-06-08T12:00:00Z - locale-pinned formatter must render
        // "Jun 8, 2024".
        let date = ISO8601DateFormatter().date(from: "2024-06-08T12:00:00Z")!
        let tx = makeTransaction(postedDate: date)

        let formatted = TransactionRow.formattedDate(for: tx)

        XCTAssertEqual(formatted, "Jun 8, 2024",
                       "Transaction posted_date must render as 'MMM d, yyyy'. Got: \(formatted)")
    }

    // MARK: - Avatar letter falls back to description when merchant is nil

    func test_transactionRow_avatarLetter_usesMerchantWhenPresent() {
        let tx = makeTransaction(description: "Coffee", merchantName: "Starbucks")

        XCTAssertEqual(TransactionRow.avatarLetter(for: tx), "S",
                       "When merchant_name is present the avatar letter is its first character.")
    }

    func test_transactionRow_avatarLetter_fallsBackToDescriptionWhenMerchantIsNil() {
        let tx = makeTransaction(description: "Payroll \u{2014} Sisystems", merchantName: nil)

        XCTAssertEqual(TransactionRow.avatarLetter(for: tx), "P",
                       "When merchant_name is nil the avatar letter falls back to the first character of description.")
    }

    // MARK: - Transaction amount carries U+2212 on debits

    func test_transactionRow_formattedAmount_negative_usesUnicodeMinus() {
        let tx = makeTransaction(amount: Decimal(-4.25))

        let formatted = TransactionRow.formattedAmount(for: tx, currencyCode: "USD")

        XCTAssertTrue(formatted.contains("\u{2212}"),
                      "Negative transaction amount must carry U+2212. Got: \(formatted)")
        XCTAssertFalse(formatted.contains("-"),
                       "Negative transaction amount must not carry ASCII hyphen-minus. Got: \(formatted)")
    }
}
