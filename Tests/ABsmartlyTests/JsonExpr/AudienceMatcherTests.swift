import Testing

@testable import ABsmartly

// Ported from 1.x AudienceMatcherTest.swift. 1.x's `evaluate` took the audience string; 2.0 parses
// it once (`parseAudience`) and evaluates the parsed filter.
@Suite struct AudienceMatcherTests {
	private func evaluate(_ audience: String, _ attributes: [String: JSONValue]) -> Bool? {
		AudienceMatcher.evaluate(AudienceMatcher.parseAudience(audience), attributes)
	}

	@Test func evaluateReturnsNullOnEmptyAudience() {
		#expect(evaluate("", [:]) == nil)
		#expect(evaluate("{}", [:]) == nil)
		#expect(evaluate("null", [:]) == nil)
	}

	// 1.x installed `Logger.errorObserver` for the duration of the test; 2.0's log observer is
	// process-wide, so the shared capture is filtered for messages about these two audiences.
	@Test func emptyAudienceIsNotLoggedAsAnError() {
		LogCapture.install()
		#expect(evaluate("null", [:]) == nil)
		#expect(evaluate("{}", [:]) == nil)
		let errors = LogCapture.messages(containing: "Audience: 'null'") + LogCapture.messages(containing: "Audience: '{}'")
		#expect(errors == [])
	}

	@Test func evaluateReturnsNullIfFilterNotMapOrList() {
		#expect(evaluate("{\"filter\":null}", [:]) == nil)
		#expect(evaluate("{\"filter\":false}", [:]) == nil)
		#expect(evaluate("{\"filter\":5}", [:]) == nil)
		#expect(evaluate("{\"filter\":\"a\"}", [:]) == nil)
	}

	@Test func evaluateReturnsBoolean() {
		#expect(evaluate("{\"filter\":[{\"value\":5}]}", [:]) == true)
		#expect(evaluate("{\"filter\":[{\"value\":true}]}", [:]) == true)
		#expect(evaluate("{\"filter\":[{\"value\":1}]}", [:]) == true)
		#expect(evaluate("{\"filter\":[{\"value\":null}]}", [:]) == false)
		#expect(evaluate("{\"filter\":[{\"value\":0}]}", [:]) == false)

		#expect(evaluate("{\"filter\":[{\"not\":{\"var\":\"returning\"}}]}", ["returning": true]) == false)
		#expect(evaluate("{\"filter\":[{\"not\":{\"var\":\"returning\"}}]}", ["returning": false]) == true)
	}
}
