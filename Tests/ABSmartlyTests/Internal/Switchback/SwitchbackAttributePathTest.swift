import Foundation
import XCTest

@testable import ABSmartly

// Resources/switchback/attribute-path-cases.json is copied byte-for-byte from absmartly/abs 9bd2b5ca35
// collector/src/test/resources/switchback/attribute-path-cases.json (git blob 7b1d3fed5985), via
// java-sdk 07807b51. Port of java-sdk SwitchbackAttributePathTest.
final class SwitchbackAttributePathTest: XCTestCase {
	static func loadCases() throws -> JSON {
		let path = TestResources.path(forResource: "attribute-path-cases", ofType: "json", subdirectory: "switchback")
		return try JSON(data: Data(contentsOf: URL(fileURLWithPath: path)))
	}

	func parse(_ path: String?) -> SwitchbackAttributePath? {
		return SwitchbackAttributePath.parseSupported(path)
	}

	func testMatchesEveryPathCase() throws {
		let fixture = try Self.loadCases()
		let attributes = fixture["attributes"].dictionaryValue
		let cases = fixture["cases"].arrayValue
		XCTAssertEqual(7, cases.count)

		for c in cases {
			let path = parse(c["path"].stringValue)
			if !c["supported"].boolValue {
				XCTAssertNil(path, "\(c)")
				continue
			}
			XCTAssertNotNil(path, "\(c)")
			let value = path?.resolve(attributes)
			if c["value"].type == .null {
				XCTAssertNil(value, "\(c)")
			} else {
				XCTAssertEqual(c["value"], value, "\(c)")
			}
		}
	}

	func testQuotedSegmentsAreLiteralKeys() {
		let attributes: [String: JSON] = ["geo": JSON(["0": "zero", "a/b": "slash"])]
		XCTAssertEqual("zero", parse("geo/'0'")?.resolve(attributes)?.string)
		XCTAssertEqual("slash", parse("geo/\"a/b\"")?.resolve(attributes)?.string)
	}

	// Malformed paths are unsupported, which makes the experiment unservable: an unterminated quote
	// anywhere, or a '.' anywhere, quoted or not.
	func testRejectsMalformedPaths() {
		for path in [
			"geo/'0", "'geo", "\"geo/city", "geo/\"", "geo.city", "geo/a.b", "a./b", ".", "items/0.5/city", "'geo.city'",
			"\"geo.city\"", "geo/'a.b'",
		] {
			XCTAssertNil(parse(path), path)
		}
	}

	func testSeparatorsAreCollapsed() {
		let attributes: [String: JSON] = ["geo": JSON(["city": "Porto"])]
		XCTAssertEqual("Porto", parse("/geo//city/")?.resolve(attributes)?.string)
		XCTAssertEqual(attributes["geo"], parse("geo")?.resolve(attributes))
	}

	func testRejectsUnsupportedPaths() {
		for path in [nil, "", "/", "//", "0/city", "items/0", "items/0/1/city", "items/-1/city", "'"] as [String?] {
			XCTAssertNil(parse(path), String(describing: path))
		}
	}

	func testIndexSegmentsReadOnlyArraysAndKeySegmentsReadOnlyObjects() {
		let attributes: [String: JSON] = [
			"items": JSON([["city": "Lisbon"]]), "geo": JSON(["0": ["city": "zero"]]), "name": JSON("scalar"),
		]
		XCTAssertNil(parse("geo/0/city")?.resolve(attributes))
		XCTAssertNil(parse("items/1/city")?.resolve(attributes))
		XCTAssertNil(parse("name/x")?.resolve(attributes))
		XCTAssertNil(parse("missing/x")?.resolve(attributes))
		XCTAssertEqual("Lisbon", parse("items/-0/city")?.resolve(attributes)?.string)
	}

	func testTryParseIntFollowsGuava() {
		XCTAssertEqual(0, SwitchbackAttributePath.tryParseInt("0"))
		XCTAssertEqual(0, SwitchbackAttributePath.tryParseInt("-0"))
		XCTAssertEqual(7, SwitchbackAttributePath.tryParseInt("007"))
		XCTAssertEqual(2_147_483_647, SwitchbackAttributePath.tryParseInt("2147483647"))
		XCTAssertEqual(-2_147_483_648, SwitchbackAttributePath.tryParseInt("-2147483648"))
		// An arbitrarily long digit run is not an int (Guava returns null), so it reads as an object key,
		// and parsing it never overflows.
		let long = String(repeating: "9", count: 10_000)
		XCTAssertNil(SwitchbackAttributePath.tryParseInt(long))
		XCTAssertNil(SwitchbackAttributePath.tryParseInt("-" + long))
		XCTAssertEqual(
			"deep", SwitchbackAttributePath.parseSupported("items/\(long)/city")?.resolve(["items": JSON([long: ["city": "deep"]])])?.string)
		for s in ["", "-", "+1", "1a", " 1", "2147483648", "-2147483649", "99999999999999999999", "\u{0660}", "1.0"] {
			XCTAssertNil(SwitchbackAttributePath.tryParseInt(s), s)
		}
	}

	// Non-ASCII keys and a quote next to a combining mark are read scalar by scalar.
	func testUnicodeSegments() {
		let attributes: [String: JSON] = ["géo": JSON(["cidade": "Évora", "'\u{301}x": "accent"])]
		XCTAssertEqual("Évora", parse("géo/cidade")?.resolve(attributes)?.string)
		XCTAssertEqual("accent", parse("géo/\"'\u{301}x\"")?.resolve(attributes)?.string)
	}
}
