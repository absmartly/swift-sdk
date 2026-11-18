import Foundation
import Testing

@testable import ABsmartly

@Suite struct MatchOperatorTests {
	private func match(_ text: JSONValue, _ pattern: JSONValue) -> JSONValue {
		eval(apply("match", [text, pattern]))
	}

	@Test func evaluate() {
		#expect(match("abcdefghijk", "").isTrue)
		#expect(match("abcdefghijk", "abc").isTrue)
		#expect(match("abcdefghijk", "ijk").isTrue)
		#expect(match("abcdefghijk", "^abc").isTrue)
		#expect(match(",l5abcdefghijk", "ijk$").isTrue)
		#expect(match("abcdefghijk", "def").isTrue)
		#expect(match("abcdefghijk", "b.*j").isTrue)
		#expect(!match("abcdefghijk", "xyz").isTrue)

		#expect(!match(.null, "abc").isTrue)
		#expect(match("abcdefghijk", .null) == .null)
	}

	@Test func rejectsLongPattern() {
		#expect(match("test", .string(String(repeating: "a", count: 1001))) == .null)
	}

	@Test func rejectsLongInput() {
		#expect(match(.string(String(repeating: "a", count: 10001)), "a") == .null)
	}

	@Test func rejectsNestedQuantifiers() {
		#expect(match("test", "(a+)+b") == .null)
	}

	@Test func rejectsOtherNestedQuantifierForms() {
		for pattern in ["(a*)*b", "((a+)b)+", "(a{1,})+", "(a+){2,}", "(?:x|a+)*"] {
			#expect(match("test", .string(pattern)) == .null, "\(pattern)")
		}
	}

	@Test func acceptsSequentialQuantifiers() {
		#expect(match("ABC-123", "^([A-Z]+)-[0-9]+$") == true)
		#expect(match("ab12", "(a|b)+[0-9]{2}") == true)
		#expect(match("a+b", "(a\\+)b+") == true)
		#expect(match("aa", "([a+])+") == true)
		#expect(match("1234", "^([0-9]{2}){2}$") == true)
		#expect(match("192.168.1.1", "^([0-9]{1,3}\\.){3}[0-9]{1,3}$") == true)
		#expect(match("abab", "^(ab+){1,3}$") == true)
	}

	// No nested quantifier, but exponential backtracking on a near-miss input: the match gives up
	// after its 0.1 s budget, well within the generous 2 s bound below.
	@Test func overlappingAlternationTimesOut() {
		let input = String(repeating: "a", count: 60) + "b"
		let start = Date()
		let result = match(.string(input), "^(a|aa)+$")
		let elapsed = Date().timeIntervalSince(start)
		#expect(result == .null)
		#expect(elapsed < 2.0)

		#expect(match("aaaa", "^(a|aa)+$") == true)
	}

	@Test func acceptsNormalPatternWithinLimits() {
		let pattern = String(repeating: "a", count: 999)
		let input = String(repeating: "a", count: 9999)
		#expect(match(.string(input), .string(pattern)).isTrue)
	}

	@Test func noSemaphoreThreadLeak() {
		#expect(match("hello world", "hello").isTrue)
		#expect(!match("hello world", "^world").isTrue)
	}

	@Test func invalidRegexReturnsNull() {
		#expect(match("test", "[invalid") == .null)
	}
}
