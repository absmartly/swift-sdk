import Foundation
import Testing

@testable import ABsmartly

// Custom fields, numeric units, misuse, logger re-entrancy and system attributes.
extension ContextTests {
	// MARK: - Custom fields

	@Test func getCustomFieldKeys() {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)
		#expect(context.customFieldKeys == ["country", "languages", "overrides"])
	}

	@Test func getCustomFieldValues() {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)
		#expect(context.customFieldValue("not_found", in: "not_found") == nil)
		#expect(context.customFieldValue("not_found", in: "exp_test_ab") == nil)
		#expect(context.customFieldValue("country", in: "exp_test_ab") == "US,PT,ES,DE,FR")
		#expect(context.customFieldType("country", in: "exp_test_ab") == "string")

		#expect(context.customFieldValue("overrides", in: "exp_test_ab") == ["123": 1, "456": 0])
		#expect(context.customFieldType("overrides", in: "exp_test_ab") == "json")

		#expect(context.customFieldValue("languages", in: "exp_test_ab") == nil)
		#expect(context.customFieldType("languages", in: "exp_test_ab") == nil)

		#expect(context.customFieldValue("country", in: "exp_test_abc") == "US,PT,ES")
		#expect(context.customFieldType("country", in: "exp_test_abc") == "string")
		#expect(context.customFieldValue("overrides", in: "exp_test_abc") == nil)
		#expect(context.customFieldType("overrides", in: "exp_test_abc") == nil)
		#expect(context.customFieldValue("languages", in: "exp_test_abc") == "en-US,en-GB,pt-PT,pt-BR,es-ES,es-MX")
		#expect(context.customFieldType("languages", in: "exp_test_abc") == "string")

		for key in ["country", "overrides", "languages"] {
			#expect(context.customFieldValue(key, in: "exp_test_no_custom_fields") == nil)
			#expect(context.customFieldType(key, in: "exp_test_no_custom_fields") == nil)
		}
	}

	@Test func customFieldValueAllTypes() {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)

		let stringValue = context.customFieldValue("country", in: "exp_test_ab")
		#expect(stringValue != nil)
		#expect(stringValue?.stringValue != nil)
		#expect(context.customFieldType("country", in: "exp_test_ab") == "string")

		#expect(context.customFieldValue("overrides", in: "exp_test_ab") != nil)
		#expect(context.customFieldType("overrides", in: "exp_test_ab") == "json")
	}

	@Test func customFieldNullHandling() {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)

		#expect(context.customFieldValue("any_key", in: "non_existent_experiment") == nil)
		#expect(context.customFieldType("any_key", in: "non_existent_experiment") == nil)
		#expect(context.customFieldValue("non_existent_key", in: "exp_test_ab") == nil)
		#expect(context.customFieldType("non_existent_key", in: "exp_test_ab") == nil)
		#expect(context.customFieldValue("languages", in: "exp_test_ab") == nil)
	}

	@Test func customFieldTypeCoercion() {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)

		let keys = context.customFieldKeys
		#expect(keys.contains("country"))
		#expect(keys.contains("languages"))
		#expect(keys.contains("overrides"))

		let experimentKeys = context.customFieldKeys(in: "exp_test_ab")
		#expect(experimentKeys.contains("country"))
		#expect(experimentKeys.contains("overrides"))
	}

	@Test func customFieldValuesHaveTheirV140Types() {
		let json = """
			{"experiments": [{"id": 1, "name": "exp", "customFieldValues": [
				{"name": "obj", "type": "json", "value": "{\\"a\\": [1, \\"x\\"]}"},
				{"name": "int", "type": "number", "value": "42"},
				{"name": "float", "type": "number", "value": "1.5"},
				{"name": "flag", "type": "boolean", "value": "true"}
			]}]}
			"""
		let env = ContextEnv()
		let context = env.context(data: ContextFixtures.decode(json))

		#expect(context.customFieldValue("obj", in: "exp") == ["a": [1, "x"]])
		#expect(context.customFieldValue("int", in: "exp")?.doubleValue == 42.0)
		#expect(context.customFieldValue("float", in: "exp")?.doubleValue == 1.5)
		#expect(context.customFieldValue("flag", in: "exp")?.boolValue == true)
	}

	// Installing data is internal (`install(_:)`), reachable here only through `@testable`.
	@Test func setDataIsNotPublic() {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)
		context.install(Fixtures.contextData())
		#expect(context.contextData != nil)
	}

	// MARK: - Logger and state

	@Test func contextIsReadyWhenReadyEventIsLogged() async throws {
		let env = ContextEnv()
		let stateWhenLogged = Box<Context.State?>(nil)
		env.log.setHook { context, event in
			if case .ready = event { stateWhenLogged.value = context.state }
		}
		let (context, gate) = await env.loadingContext()
		gate.fulfill(fixture: "context")
		try await context.ready()

		#expect(stateWhenLogged.value == .ready)
		#expect(context.state == .ready)
	}

	// As in 1.5.0 and JavaScript: a logger handling the load failure already sees the context failed.
	@Test func errorEventSeesTheContextFailed() async {
		let env = ContextEnv()
		let stateWhenLogged = Box<Context.State?>(nil)
		env.log.setHook { context, event in
			if case .error = event { stateWhenLogged.value = context.state }
		}
		let (context, gate) = await env.loadingContext()
		gate.reject(TestError("load failed"))
		try? await context.ready()

		#expect(stateWhenLogged.value == .failed(.transport("load failed")))
		#expect(context.state == .failed(.transport("load failed")))
	}

	// As in 1.5.0: the errors of background work (load, refresh, publish) are routed to the logger's
	// main-thread delivery, like ready/refresh/publish/close; misuse errors stay on the calling thread.
	@Test func backgroundErrorsAreDeliveredOnTheMainThread() async {
		let routed = Box<[String]>([])
		let dispatcher: @Sendable (Context.Event, @escaping @Sendable () -> Void) -> Void = { event, deliver in
			let kind: String
			switch event {
			case .error(let error): kind = "error:\(error.description)"
			case .ready: kind = "ready"
			case .refresh: kind = "refresh"
			case .publish: kind = "publish"
			case .close: kind = "close"
			default: kind = "other"
			}
			routed.mutate { $0.append(kind) }
			deliver()
		}
		await Context.$mainThreadDispatcher.withValue(dispatcher) {
			let env = ContextEnv()
			let (failing, gate) = await env.loadingContext()
			gate.reject(TestError("load failed"))
			try? await failing.ready()

			let context = env.context()
			env.failNextRequest("refresh failed")
			try? await context.refresh()
			context.track("goal", properties: nil)
			env.failNextRequest("publish failed")
			try? await context.publish()
			_ = context.variableValue("x")
			try? context.setUnit("session_id", to: "other")
		}

		let errors = routed.value.filter { $0.hasPrefix("error:") }
		#expect(errors == ["error:load failed", "error:refresh failed", "error:publish failed"])
	}

	@Test func publicApiDoesNotThrowAndReturnsDefaultsBeforeReady() async {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()

		let treatment: Int = context.treatment(for: "exp_test_ab")
		#expect(treatment == 0)
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 0)
		#expect(context.variable("banner.size", default: JSONValue(5)) == 5)
		#expect(context.variable("banner.size", default: JSONValue(5), exposing: false) == 5)
		#expect(context.variableKeys == [:])
		#expect(context.experiments == [])
		#expect(context.customFieldKeys == [])
		#expect(context.customFieldValue("country", in: "exp_test_ab") == nil)
		#expect(context.customFieldType("country", in: "exp_test_ab") == nil)
		#expect(context.contextData == nil)
		#expect(context.pendingEventCount == 0)

		#expect(env.log.errorMessages.count == 10)
		#expect(Set(env.log.errorMessages).sorted() == ["ABsmartly Context is not yet ready."])
		gate.fulfill(fixture: "context")
	}

	@Test func errorHandlerReadingContextOnFailedLoadDoesNotRecurse() async {
		let env = ContextEnv()
		let nestedReads = Box(0)
		let nestedData = Box<[ContextData?]>([])
		env.log.setHook { context, event in
			guard case .error = event, nestedReads.value < 50 else { return }
			nestedReads.mutate { $0 += 1 }
			let data = context.contextData
			nestedData.mutate { $0.append(data) }
		}
		let (context, gate) = await env.loadingContext()
		gate.reject(TestError("load failed"))
		try? await context.ready()

		// The handler already sees the context failed, whose data is empty.
		#expect(nestedReads.value == 1)
		#expect(nestedData.value == [ContextData()])
		#expect(env.log.errorMessages == ["load failed"])
		#expect(context.state == .failed(.transport("load failed")))
	}

	@Test func errorHandlerReadingContextBeforeReadyDoesNotRecurse() async {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		let nestedReads = Box(0)
		let nestedTreatments = Box<[Int]>([])
		env.log.setHook { context, event in
			guard case .error = event, nestedReads.value < 50 else { return }
			nestedReads.mutate { $0 += 1 }
			let treatment = context.treatment(for: "exp_test_ab")
			nestedTreatments.mutate { $0.append(treatment) }
		}

		// Each top-level misuse is still reported once; only the nested one is suppressed.
		#expect(context.contextData == nil)
		#expect(context.contextData == nil)
		#expect(nestedReads.value == 2)
		#expect(nestedTreatments.value == [0, 0])
		#expect(env.log.errorMessages == Array(repeating: "ABsmartly Context is not yet ready.", count: 2))
		env.log.setHook(nil)
		gate.fulfill(fixture: "context")
	}

	@Test func readsInsideReadyHandlerSeeTheData() {
		let env = ContextEnv()
		let treatmentInHandler = Box<Int?>(nil)
		let variableInHandler = Box<JSONValue?>(nil)
		env.log.setHook { context, event in
			if case .ready = event {
				treatmentInHandler.value = context.treatment(for: "exp_test_ab")
				variableInHandler.value = context.variableValue("banner.size")
			}
		}

		let context = env.context()
		#expect(context.state == .ready)
		#expect(treatmentInHandler.value == 1)
		#expect(variableInHandler.value == "large")
		#expect(env.log.errorMessages == [])
	}

	@Test func readsInsideReadyHandlerSeeTheDataWhenLoadedAsynchronously() async throws {
		let env = ContextEnv()
		let treatmentInHandler = Box<Int?>(nil)
		env.log.setHook { context, event in
			if case .ready = event { treatmentInHandler.value = context.treatment(for: "exp_test_ab") }
		}

		let (context, gate) = await env.loadingContext()
		gate.fulfill(fixture: "context")
		try await context.ready()

		#expect(treatmentInHandler.value == 1)
		#expect(env.log.errorMessages == [])
	}

	// MARK: - Units

	@Test func numericUnitsKeepTheirTypeAndHashLikeJavaScript() throws {
		let env = ContextEnv()
		let context = env.context(units: [:])
		try context.setUnit(.userID, to: 125)
		try context.setUnit("float_id", to: 125.75)
		try context.setUnit(.sessionID, to: 12345)

		#expect(context.unitValues[.userID] == .int(125))
		#expect(context.unitValues[.userID]?.isNumber == true)
		#expect(context.unitValues["float_id"]?.doubleValue == 125.75)
		#expect(context.unitValues[.sessionID]?.isNumber == true)
		#expect(context.unitValues["float_id"]?.isNumber == true)

		// Same number again is not a change; a different one is.
		try context.setUnit(.userID, to: 125)
		#expect(env.log.errorMessages == [])
		#expect(throws: ABsmartlyError.unitAlreadySet(unitType: "user_id")) { try context.setUnit(.userID, to: "125") }
		#expect(env.log.errorMessages == ["Unit 'user_id' UID already set."])
		#expect(context.unitValues[.userID] == .int(125))

		// JS hashes numbers with toFixed(0): 125.75 -> "126".
		#expect(unitHash(Hashing.unitString(125.75)) == "BpBZt--EDwx0qBTskje27A")
		#expect(unitHash(Hashing.unitString(125.75)) == unitHash("126"))
		#expect(unitHash(Hashing.unitString(12345)) == unitHash("12345"))

		try context.setUnit("json_id", to: 7)
		#expect(context.unitValues["json_id"]?.isNumber == true)

		let stringContext = env.context(units: ["float_id": "126"])
		#expect(stringContext.unitValues["float_id"] == .string("126"))
	}

	@Test func hashingHelpers() {
		#expect(Hashing.base64URL(Data("abc".utf8)) == "YWJj")
		#expect(Hashing.base64URL(Data([0x3f, 0x3f, 0x3e])) == "Pz8-")
	}

	@Test func numericUnitStringMatchesJavaScriptToFixed() async throws {
		#expect(Hashing.unitString(-0.1) == "-0")
		#expect(Hashing.unitString(-0.0) == "0")
		#expect(Hashing.unitString(1e21) == "1e+21")
		#expect(Hashing.unitString(-1.5e22) == "-1.5e+22")
		#expect(Hashing.unitString(2.5) == "3")
		#expect(Hashing.unitString(-2.5) == "-3")

		let env = ContextEnv()
		let context = env.context(units: [:])
		try context.setUnit("neg_id", to: -0.1)
		try context.setUnit("big_id", to: 1e21)
		_ = context.treatment(for: "exp_test_ab")
		try await context.publish()

		let units = env.lastSentEvent?["units"]?.arrayValue ?? []
		let published = Dictionary(
			uniqueKeysWithValues: units.compactMap { unit in
				unit["type"]?.stringValue.flatMap { type in unit["uid"]?.stringValue.map { (type, $0) } }
			})
		#expect(published["neg_id"] == unitHash("-0"))
		#expect(published["big_id"] == unitHash("1e+21"))
	}

	@Test func longUnitUIDIsAcceptedAndAssigned() async throws {
		let longUID = String(repeating: "a", count: 300)
		let env = ContextEnv()
		let context = env.context(units: [.sessionID: longUID])
		try context.setUnit(.userID, to: String(repeating: "b", count: 1000))

		#expect(context.units[.sessionID] == longUID)
		#expect(context.units[.userID]?.count == 1000)
		#expect(env.log.errorMessages == [])

		_ = context.treatment(for: "exp_test_ab")
		try await context.publish()

		let event = try #require(env.log.publishes.last)
		#expect(event.units.map(\.type).sorted() == ["session_id", "user_id"])
		#expect(event.units.first { $0.type == "session_id" }?.uid == unitHash(longUID))
		#expect(event.exposures.first?.assigned == true)
	}

	// MARK: - System attributes (application / environment) in audience evaluation

	// exp_test_ab with a strict audience and a 0/100 split to variant 1, so a match yields 1 and a
	// mismatch (strict) yields the control variant 0.
	private static func strictAudienceData(filter: String) -> ContextData {
		let audience = "{\"filter\":\(filter)}"
		let escapedAudience = audience
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		return ContextFixtures.decode(
			"""
			{"experiments":[{"id":1,"name":"exp_test_ab","iteration":1,"unitType":"session_id",\
			"seedHi":3603515,"seedLo":233373850,"split":[0.0,1.0],"trafficSeedHi":449867249,\
			"trafficSeedLo":455443629,"trafficSplit":[0.0,1.0],"fullOnVariant":0,\
			"applications":[{"name":"website"}],"variants":[{"name":"A","config":null},\
			{"name":"B","config":"{\\"banner.border\\":1,\\"banner.size\\":\\"large\\"}"}],\
			"audienceStrict":true,"audience":"\(escapedAudience)"}]}
			""")
	}

	private static let environmentIsProduction = #"[{"eq":[{"var":"environment"},{"value":"production"}]}]"#
	private static let environmentIsStaging = #"[{"eq":[{"var":"environment"},{"value":"staging"}]}]"#
	private static let environmentIsNull = #"[{"null":{"var":"environment"}}]"#
	private static let appVersionIs123 = #"[{"eq":[{"var":"app_version"},{"value":"1.2.3"}]}]"#

	/// A context created as the client would, with application "website" and environment "production".
	private func systemContext(_ env: ContextEnv, filter: String) -> Context {
		env.directContext(data: Self.strictAudienceData(filter: filter))
	}

	@Test func strictAudienceMatchesConfiguredEnvironment() {
		let env = ContextEnv()
		let context = systemContext(env, filter: Self.environmentIsProduction)

		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(env.log.exposures == [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false)])
		#expect(context.variable("banner.size", default: "default") == "large")
	}

	@Test func strictAudienceMatchesConfiguredApplication() {
		let env = ContextEnv()
		let context = systemContext(env, filter: #"[{"eq":[{"var":"application"},{"value":"website"}]}]"#)

		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(env.log.exposures == [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false)])
	}

	@Test func strictAudienceMismatchOnOtherEnvironment() {
		let env = ContextEnv()
		let context = systemContext(env, filter: Self.environmentIsStaging)

		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(env.log.exposures == [exposure(1, "exp_test_ab", "session_id", 0, false, true, false, false, false, true)])
	}

	// A user-set attribute wins over the configured value, even set after creation, and invalidates
	// an assignment cached before it was set.
	@Test func userSetEnvironmentOverridesConfiguredValue() {
		let env = ContextEnv()
		let context = systemContext(env, filter: Self.environmentIsStaging)

		// Cached before the attribute is set: production ≠ staging, strict mismatch → 0.
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 0)

		context.setAttribute("environment", to: "staging")

		// The cached assignment is invalidated and re-evaluated: staging now matches → 1.
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 1)
		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(env.log.exposures == [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false)])
	}

	// A user value also loses the match once it overrides a configured value that matched.
	@Test func userSetEnvironmentOverridesMatchingConfiguredValue() {
		let env = ContextEnv()
		let context = systemContext(env, filter: Self.environmentIsProduction)

		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 1)

		context.setAttribute("environment", to: "staging")

		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(env.log.exposures == [exposure(1, "exp_test_ab", "session_id", 0, false, true, false, false, false, true)])
	}

	@Test func audienceConditionMatchesConfiguredEnvironment() {
		let env = ContextEnv()
		let context = systemContext(env, filter: #"{"and":[{"eq":[{"var":"environment"},{"value":"production"}]}]}"#)
		#expect(context.treatment(for: "exp_test_ab") == 1)
	}

	// With no environment configured, the key is absent from the map: no crash, and a filter on
	// `environment` does not match.
	@Test func missingEnvironmentConfigLeavesKeyOut() {
		let env = ContextEnv()
		let context = env.directContext(data: Self.strictAudienceData(filter: Self.environmentIsProduction), environment: nil)

		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(env.log.exposures == [exposure(1, "exp_test_ab", "session_id", 0, false, true, false, false, false, true)])
	}

	// A `null` filter on a missing environment matches, confirming the key is absent (not null/"").
	@Test func missingEnvironmentConfigMatchesNullFilter() {
		let env = ContextEnv()
		let context = env.directContext(data: Self.strictAudienceData(filter: Self.environmentIsNull), environment: nil)
		#expect(context.treatment(for: "exp_test_ab") == 1)
	}

	// An empty environment name is treated the same as unconfigured: the key is left out.
	@Test func emptyEnvironmentConfigLeavesKeyOut() {
		let env = ContextEnv()
		let context = env.directContext(data: Self.strictAudienceData(filter: Self.environmentIsNull), environment: "")
		#expect(context.treatment(for: "exp_test_ab") == 1)
	}

	@Test func emptyApplicationConfigLeavesKeyOut() {
		let env = ContextEnv()
		let context = env.directContext(
			data: Self.strictAudienceData(filter: #"[{"null":{"var":"application"}}]"#), application: "")
		#expect(context.treatment(for: "exp_test_ab") == 1)
	}

	// Nothing extra is published: the payload carries no `application`/`environment`/`app_version`
	// attribute beyond the user-set ones.
	@Test func systemAttributesAreNotPublished() async throws {
		let env = ContextEnv()
		let context = systemContext(env, filter: Self.environmentIsProduction)
		context.setAttribute("custom_attr", to: "custom_value")

		#expect(context.treatment(for: "exp_test_ab") == 1)
		try await context.publish()

		let body = try #require(env.lastSentEvent)
		let names = (body["attributes"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
		#expect(names == ["custom_attr"])
		#expect(!names.contains("application"))
		#expect(!names.contains("environment"))
		#expect(!names.contains("app_version"))
	}

	// `app_version` is never injected: a filter on it does not match.
	@Test func appVersionIsNotInjectedIntoEvaluation() {
		let env = ContextEnv()
		let context = systemContext(env, filter: Self.appVersionIs123)

		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(env.log.exposures == [exposure(1, "exp_test_ab", "session_id", 0, false, true, false, false, false, true)])
	}

	@Test func userSetAppVersionIsEvaluated() {
		let env = ContextEnv()
		let context = systemContext(env, filter: Self.appVersionIs123)
		context.setAttribute("app_version", to: "1.2.3")
		#expect(context.treatment(for: "exp_test_ab") == 1)
	}

	@Test func systemAttributesAreNotReportedAsUserAttributes() {
		let env = ContextEnv()
		let context = env.directContext(data: Fixtures.contextData())
		context.setAttribute("age", to: 25)

		#expect(context.attributes == ["age": 25])
		#expect(context.attribute("environment") == nil)
		#expect(context.attribute("application") == nil)
	}
}
