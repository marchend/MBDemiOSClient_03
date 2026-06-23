import XCTest
@testable import AcmeBank

/// Verifies the `HomeDashboard` value-object tree decodes the EXACT
/// `/v1/home` wire shape the BFF emits. The fixture
/// (`home_bankuser_one.json`) is the sample payload pinned in the
/// parent story — keeping it as a separate file (rather than an inline
/// string) means a server-side OpenAPI change can be diffed visually
/// in review.
final class HomeDashboardDecodingTests: XCTestCase {

    // MARK: - Decoder under test

    /// Mirrors `BFFHomeRepository`'s decoder exactly. Kept private here
    /// so decoding tests cannot accidentally drift from the production
    /// configuration (snake_case keys, ISO-8601 dates).
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Fixture loading

    private func loadFixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing fixture \(name).json in test bundle")
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    // MARK: - Happy path: full bankuser.one fixture round-trips

    func test_bankuserOneFixture_decodesAllFields() throws {
        let data = try loadFixtureData(named: "home_bankuser_one")
        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: data)

        // Customer
        XCTAssertEqual(dashboard.customer.id, "cust-1002")
        XCTAssertEqual(dashboard.customer.firstName, "Bankuser")
        XCTAssertEqual(dashboard.customer.lastName, "One")
        XCTAssertEqual(dashboard.customer.email, "bankuser.one@sisystems.com")
        XCTAssertEqual(dashboard.customer.phoneNumber, "+1-604-555-0188")

        // Accounts: 4 rows, in response order.
        XCTAssertEqual(dashboard.accounts.count, 4)

        let chequing = dashboard.accounts[0]
        XCTAssertEqual(chequing.id, "acct-11")
        XCTAssertEqual(chequing.name, "Everyday Chequing")
        XCTAssertEqual(chequing.maskedNumber, "3310")
        XCTAssertEqual(chequing.balance, Decimal(string: "1542.88"))
        XCTAssertEqual(chequing.availableBalance, Decimal(string: "1542.88"))
        XCTAssertEqual(chequing.type, .chequing)
        XCTAssertEqual(chequing.currencyCode, "USD")

        let savings = dashboard.accounts[1]
        XCTAssertEqual(savings.type, .savings)
        XCTAssertEqual(savings.balance, Decimal(string: "6120.00"))

        let credit = dashboard.accounts[2]
        XCTAssertEqual(credit.type, .credit)
        XCTAssertEqual(credit.balance, Decimal(string: "-243.10"))
        XCTAssertEqual(credit.availableBalance, Decimal(string: "4756.90"))

        let investment = dashboard.accounts[3]
        XCTAssertEqual(investment.type, .investment)
        XCTAssertEqual(investment.balance, Decimal(string: "23410.55"))

        // Recent transactions: 3 rows, newest-first (already by wire).
        XCTAssertEqual(dashboard.recentTransactions.count, 3)

        let timHortons = dashboard.recentTransactions[0]
        XCTAssertEqual(timHortons.id, "txn-114")
        XCTAssertEqual(timHortons.accountId, "acct-11")
        XCTAssertEqual(timHortons.description, "Tim Hortons")
        XCTAssertEqual(timHortons.amount, Decimal(string: "-3.45"))
        XCTAssertEqual(timHortons.category, "dining")
        XCTAssertEqual(timHortons.merchantName, "Tim Hortons")
    }

    // MARK: - posted_date decodes as a real Date (ISO-8601 with time)

    func test_postedDate_decodesIso8601DateTime() throws {
        let data = try loadFixtureData(named: "home_bankuser_one")
        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: data)

        // "2026-06-08T07:48:00Z" — full date-time, NOT a date-only
        // string. Compare against a TimeZone-stable reference Date.
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 8
        components.hour = 7
        components.minute = 48
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let expected = Calendar(identifier: .gregorian).date(from: components)
        XCTAssertEqual(dashboard.recentTransactions[0].postedDate, expected)
    }

    // MARK: - UPPERCASE account type wire values decode

    func test_accountType_decodesUppercaseWireValues() throws {
        let json = """
        { "type": "CHEQUING" }
        """.data(using: .utf8)!

        struct Wrapper: Decodable { let type: AccountType }
        let wrapper = try makeDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(wrapper.type, .chequing)
    }

    // MARK: - Unknown account type falls back to .unknown

    func test_accountType_unknownWireValue_fallsBackToUnknown() throws {
        // A future server-side addition (e.g. MORTGAGE) must NOT fail
        // the whole `/v1/home` decode.
        let json = """
        { "type": "MORTGAGE" }
        """.data(using: .utf8)!

        struct Wrapper: Decodable { let type: AccountType }
        let wrapper = try makeDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(wrapper.type, .unknown)
    }

    // MARK: - Real BFF wire shape: lowercase type + null email decode

    func test_realBffShape_lowercaseType_andNullEmail_decode() throws {
        // The deployed BFF lowercases account type on the wire ("chequing")
        // and the orchestrator's customer projection omits email (null).
        // Before the fix this threw valueNotFound on `email` and mapped the
        // type to .unknown — blanking Home with "couldn't read the response"
        // even though every other field decoded. This is the captured real
        // /v1/home payload shape (bankuser.one).
        let json = """
        {
          "customer": {
            "id": "cust-1002",
            "first_name": "Bankuser",
            "last_name": "One",
            "email": null,
            "phone_number": null
          },
          "accounts": [
            {
              "id": "acct-11",
              "name": "Everyday Chequing",
              "masked_number": "3310",
              "balance": 1542.88,
              "available_balance": 1542.88,
              "type": "chequing",
              "currency_code": "USD"
            }
          ],
          "recent_transactions": [
            {
              "id": "txn-14",
              "account_id": "acct-11",
              "description": "ATM Withdrawal",
              "amount": -200.00,
              "posted_date": "2026-06-07T11:00:00Z",
              "category": null,
              "merchant_name": null
            }
          ]
        }
        """.data(using: .utf8)!

        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: json)
        XCTAssertNil(dashboard.customer.email)
        XCTAssertEqual(dashboard.customer.firstName, "Bankuser")
        XCTAssertEqual(dashboard.accounts.count, 1)
        // lowercase wire value still resolves to the typed case
        XCTAssertEqual(dashboard.accounts[0].type, .chequing)
        XCTAssertEqual(dashboard.accounts[0].name, "Everyday Chequing")
        XCTAssertEqual(dashboard.recentTransactions.count, 1)
    }

    // MARK: - Nullable fields round-trip as nil

    func test_nullableFields_decodeAsNil() throws {
        // Customer with no phone_number; transaction with null
        // merchant_name and null category. All three fields are
        // declared optional and must NOT fail the decode.
        let json = """
        {
          "customer": {
            "id": "cust-9999",
            "first_name": "No",
            "last_name": "Phone",
            "email": "no.phone@example.com",
            "phone_number": null
          },
          "accounts": [],
          "recent_transactions": [
            {
              "id": "txn-1",
              "account_id": "acct-1",
              "description": "Payroll",
              "amount": 100.00,
              "posted_date": "2026-01-02T03:04:05Z",
              "category": null,
              "merchant_name": null
            }
          ]
        }
        """.data(using: .utf8)!

        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: json)
        XCTAssertNil(dashboard.customer.phoneNumber)
        XCTAssertNil(dashboard.recentTransactions[0].merchantName)
        XCTAssertNil(dashboard.recentTransactions[0].category)
    }
}
