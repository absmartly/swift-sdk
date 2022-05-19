// Generated using Sourcery 1.7.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT

// swiftlint:disable line_length
// swiftlint:disable variable_name

import Foundation
import PromiseKit

@testable import ABSmartly

class ClientMock: Client {

	//MARK: - getContextData

	var getContextDataCallsCount = 0
	var getContextDataCalled: Bool {
		return getContextDataCallsCount > 0
	}
	var getContextDataReturnValue: Promise<ContextData>!
	var getContextDataClosure: (() -> Promise<ContextData>)?

	func getContextData() -> Promise<ContextData> {
		getContextDataCallsCount += 1
		if let getContextDataClosure = getContextDataClosure {
			return getContextDataClosure()
		} else {
			return getContextDataReturnValue
		}
	}

	//MARK: - publish

	var publishEventCallsCount = 0
	var publishEventCalled: Bool {
		return publishEventCallsCount > 0
	}
	var publishEventReceivedEvent: PublishEvent?
	var publishEventReceivedInvocations: [PublishEvent] = []
	var publishEventReturnValue: Promise<Void>!
	var publishEventClosure: ((PublishEvent) -> Promise<Void>)?

	func publish(event: PublishEvent) -> Promise<Void> {
		publishEventCallsCount += 1
		publishEventReceivedEvent = event
		publishEventReceivedInvocations.append(event)
		if let publishEventClosure = publishEventClosure {
			return publishEventClosure(event)
		} else {
			return publishEventReturnValue
		}
	}

	//MARK: - close

	var closeCallsCount = 0
	var closeCalled: Bool {
		return closeCallsCount > 0
	}
	var closeReturnValue: Promise<Void>!
	var closeClosure: (() -> Promise<Void>)?

	func close() -> Promise<Void> {
		closeCallsCount += 1
		if let closeClosure = closeClosure {
			return closeClosure()
		} else {
			return closeReturnValue
		}
	}

	func clearInvocations() {
		getContextDataCallsCount = 0
		publishEventCallsCount = 0
		publishEventReceivedEvent = nil
		publishEventReceivedInvocations = []
		closeCallsCount = 0
	}
}

class ClockMock: Clock {

	//MARK: - millis

	var millisCallsCount = 0
	var millisCalled: Bool {
		return millisCallsCount > 0
	}
	var millisReturnValue: Int64!
	var millisClosure: (() -> Int64)?

	func millis() -> Int64 {
		millisCallsCount += 1
		if let millisClosure = millisClosure {
			return millisClosure()
		} else {
			return millisReturnValue
		}
	}

	func clearInvocations() {
		millisCallsCount = 0
	}
}

class ContextDataProviderMock: ContextDataProvider {

	//MARK: - getContextData

	var getContextDataCallsCount = 0
	var getContextDataCalled: Bool {
		return getContextDataCallsCount > 0
	}
	var getContextDataReturnValue: Promise<ContextData>!
	var getContextDataClosure: (() -> Promise<ContextData>)?

	func getContextData() -> Promise<ContextData> {
		getContextDataCallsCount += 1
		if let getContextDataClosure = getContextDataClosure {
			return getContextDataClosure()
		} else {
			return getContextDataReturnValue
		}
	}

	func clearInvocations() {
		getContextDataCallsCount = 0
	}
}

class ContextEventHandlerMock: ContextEventHandler {

	//MARK: - publish

	var publishEventCallsCount = 0
	var publishEventCalled: Bool {
		return publishEventCallsCount > 0
	}
	var publishEventReceivedEvent: PublishEvent?
	var publishEventReceivedInvocations: [PublishEvent] = []
	var publishEventReturnValue: Promise<Void>!
	var publishEventClosure: ((PublishEvent) -> Promise<Void>)?

	func publish(event: PublishEvent) -> Promise<Void> {
		publishEventCallsCount += 1
		publishEventReceivedEvent = event
		publishEventReceivedInvocations.append(event)
		if let publishEventClosure = publishEventClosure {
			return publishEventClosure(event)
		} else {
			return publishEventReturnValue
		}
	}

	func clearInvocations() {
		publishEventCallsCount = 0
		publishEventReceivedEvent = nil
		publishEventReceivedInvocations = []
	}
}

class ContextEventLoggerMock: ContextEventLogger {

	//MARK: - handleEvent

	var handleEventContextEventCallsCount = 0
	var handleEventContextEventCalled: Bool {
		return handleEventContextEventCallsCount > 0
	}
	var handleEventContextEventReceivedArguments: (context: Context, event: ContextEventLoggerEvent)?
	var handleEventContextEventReceivedInvocations: [(context: Context, event: ContextEventLoggerEvent)] = []
	var handleEventContextEventClosure: ((Context, ContextEventLoggerEvent) -> Void)?

	func handleEvent(context: Context, event: ContextEventLoggerEvent) {
		handleEventContextEventCallsCount += 1
		handleEventContextEventReceivedArguments = (context: context, event: event)
		handleEventContextEventReceivedInvocations.append((context: context, event: event))
		handleEventContextEventClosure?(context, event)
	}

	func clearInvocations() {
		handleEventContextEventCallsCount = 0
		handleEventContextEventReceivedArguments = nil
		handleEventContextEventReceivedInvocations = []
	}
}

class EvaluatorMock: Evaluator {

	//MARK: - evaluate

	var evaluateCallsCount = 0
	var evaluateCalled: Bool {
		return evaluateCallsCount > 0
	}
	var evaluateReceivedExpr: JSON?
	var evaluateReceivedInvocations: [JSON] = []
	var evaluateReturnValue: JSON!
	var evaluateClosure: ((JSON) -> JSON)?

	func evaluate(_ expr: JSON) -> JSON {
		evaluateCallsCount += 1
		evaluateReceivedExpr = expr
		evaluateReceivedInvocations.append(expr)
		if let evaluateClosure = evaluateClosure {
			return evaluateClosure(expr)
		} else {
			return evaluateReturnValue
		}
	}

	//MARK: - booleanConvert

	var booleanConvertCallsCount = 0
	var booleanConvertCalled: Bool {
		return booleanConvertCallsCount > 0
	}
	var booleanConvertReceivedX: JSON?
	var booleanConvertReceivedInvocations: [JSON] = []
	var booleanConvertReturnValue: JSON!
	var booleanConvertClosure: ((JSON) -> JSON)?

	func booleanConvert(_ x: JSON) -> JSON {
		booleanConvertCallsCount += 1
		booleanConvertReceivedX = x
		booleanConvertReceivedInvocations.append(x)
		if let booleanConvertClosure = booleanConvertClosure {
			return booleanConvertClosure(x)
		} else {
			return booleanConvertReturnValue
		}
	}

	//MARK: - numberConvert

	var numberConvertCallsCount = 0
	var numberConvertCalled: Bool {
		return numberConvertCallsCount > 0
	}
	var numberConvertReceivedX: JSON?
	var numberConvertReceivedInvocations: [JSON] = []
	var numberConvertReturnValue: JSON!
	var numberConvertClosure: ((JSON) -> JSON)?

	func numberConvert(_ x: JSON) -> JSON {
		numberConvertCallsCount += 1
		numberConvertReceivedX = x
		numberConvertReceivedInvocations.append(x)
		if let numberConvertClosure = numberConvertClosure {
			return numberConvertClosure(x)
		} else {
			return numberConvertReturnValue
		}
	}

	//MARK: - stringConvert

	var stringConvertCallsCount = 0
	var stringConvertCalled: Bool {
		return stringConvertCallsCount > 0
	}
	var stringConvertReceivedX: JSON?
	var stringConvertReceivedInvocations: [JSON] = []
	var stringConvertReturnValue: JSON!
	var stringConvertClosure: ((JSON) -> JSON)?

	func stringConvert(_ x: JSON) -> JSON {
		stringConvertCallsCount += 1
		stringConvertReceivedX = x
		stringConvertReceivedInvocations.append(x)
		if let stringConvertClosure = stringConvertClosure {
			return stringConvertClosure(x)
		} else {
			return stringConvertReturnValue
		}
	}

	//MARK: - extractVar

	var extractVarCallsCount = 0
	var extractVarCalled: Bool {
		return extractVarCallsCount > 0
	}
	var extractVarReceivedPath: String?
	var extractVarReceivedInvocations: [String] = []
	var extractVarReturnValue: JSON!
	var extractVarClosure: ((String) -> JSON)?

	func extractVar(_ path: String) -> JSON {
		extractVarCallsCount += 1
		extractVarReceivedPath = path
		extractVarReceivedInvocations.append(path)
		if let extractVarClosure = extractVarClosure {
			return extractVarClosure(path)
		} else {
			return extractVarReturnValue
		}
	}

	//MARK: - compare

	var compareCallsCount = 0
	var compareCalled: Bool {
		return compareCallsCount > 0
	}
	var compareReceivedArguments: (lhs: JSON, rhs: JSON)?
	var compareReceivedInvocations: [(lhs: JSON, rhs: JSON)] = []
	var compareReturnValue: Int?
	var compareClosure: ((JSON, JSON) -> Int?)?

	func compare(_ lhs: JSON, _ rhs: JSON) -> Int? {
		compareCallsCount += 1
		compareReceivedArguments = (lhs: lhs, rhs: rhs)
		compareReceivedInvocations.append((lhs: lhs, rhs: rhs))
		if let compareClosure = compareClosure {
			return compareClosure(lhs, rhs)
		} else {
			return compareReturnValue
		}
	}

	func clearInvocations() {
		evaluateCallsCount = 0
		evaluateReceivedExpr = nil
		evaluateReceivedInvocations = []
		booleanConvertCallsCount = 0
		booleanConvertReceivedX = nil
		booleanConvertReceivedInvocations = []
		numberConvertCallsCount = 0
		numberConvertReceivedX = nil
		numberConvertReceivedInvocations = []
		stringConvertCallsCount = 0
		stringConvertReceivedX = nil
		stringConvertReceivedInvocations = []
		extractVarCallsCount = 0
		extractVarReceivedPath = nil
		extractVarReceivedInvocations = []
		compareCallsCount = 0
		compareReceivedArguments = nil
		compareReceivedInvocations = []
	}
}

class HTTPClientMock: HTTPClient {

	//MARK: - get

	var getUrlQueryHeadersCallsCount = 0
	var getUrlQueryHeadersCalled: Bool {
		return getUrlQueryHeadersCallsCount > 0
	}
	var getUrlQueryHeadersReceivedArguments: (url: String, query: [String: String]?, headers: [String: String]?)?
	var getUrlQueryHeadersReceivedInvocations: [(url: String, query: [String: String]?, headers: [String: String]?)] =
		[]
	var getUrlQueryHeadersReturnValue: Promise<Response>!
	var getUrlQueryHeadersClosure: ((String, [String: String]?, [String: String]?) -> Promise<Response>)?

	func get(url: String, query: [String: String]?, headers: [String: String]?) -> Promise<Response> {
		getUrlQueryHeadersCallsCount += 1
		getUrlQueryHeadersReceivedArguments = (url: url, query: query, headers: headers)
		getUrlQueryHeadersReceivedInvocations.append((url: url, query: query, headers: headers))
		if let getUrlQueryHeadersClosure = getUrlQueryHeadersClosure {
			return getUrlQueryHeadersClosure(url, query, headers)
		} else {
			return getUrlQueryHeadersReturnValue
		}
	}

	//MARK: - put

	var putUrlQueryHeadersBodyCallsCount = 0
	var putUrlQueryHeadersBodyCalled: Bool {
		return putUrlQueryHeadersBodyCallsCount > 0
	}
	var putUrlQueryHeadersBodyReceivedArguments:
		(url: String, query: [String: String]?, headers: [String: String]?, body: Data?)?
	var putUrlQueryHeadersBodyReceivedInvocations:
		[(url: String, query: [String: String]?, headers: [String: String]?, body: Data?)] = []
	var putUrlQueryHeadersBodyReturnValue: Promise<Response>!
	var putUrlQueryHeadersBodyClosure: ((String, [String: String]?, [String: String]?, Data?) -> Promise<Response>)?

	func put(url: String, query: [String: String]?, headers: [String: String]?, body: Data?) -> Promise<Response> {
		putUrlQueryHeadersBodyCallsCount += 1
		putUrlQueryHeadersBodyReceivedArguments = (url: url, query: query, headers: headers, body: body)
		putUrlQueryHeadersBodyReceivedInvocations.append((url: url, query: query, headers: headers, body: body))
		if let putUrlQueryHeadersBodyClosure = putUrlQueryHeadersBodyClosure {
			return putUrlQueryHeadersBodyClosure(url, query, headers, body)
		} else {
			return putUrlQueryHeadersBodyReturnValue
		}
	}

	//MARK: - post

	var postUrlQueryHeadersBodyCallsCount = 0
	var postUrlQueryHeadersBodyCalled: Bool {
		return postUrlQueryHeadersBodyCallsCount > 0
	}
	var postUrlQueryHeadersBodyReceivedArguments:
		(url: String, query: [String: String]?, headers: [String: String]?, body: Data?)?
	var postUrlQueryHeadersBodyReceivedInvocations:
		[(url: String, query: [String: String]?, headers: [String: String]?, body: Data?)] = []
	var postUrlQueryHeadersBodyReturnValue: Promise<Response>!
	var postUrlQueryHeadersBodyClosure: ((String, [String: String]?, [String: String]?, Data?) -> Promise<Response>)?

	func post(url: String, query: [String: String]?, headers: [String: String]?, body: Data?) -> Promise<Response> {
		postUrlQueryHeadersBodyCallsCount += 1
		postUrlQueryHeadersBodyReceivedArguments = (url: url, query: query, headers: headers, body: body)
		postUrlQueryHeadersBodyReceivedInvocations.append((url: url, query: query, headers: headers, body: body))
		if let postUrlQueryHeadersBodyClosure = postUrlQueryHeadersBodyClosure {
			return postUrlQueryHeadersBodyClosure(url, query, headers, body)
		} else {
			return postUrlQueryHeadersBodyReturnValue
		}
	}

	//MARK: - close

	var closeCallsCount = 0
	var closeCalled: Bool {
		return closeCallsCount > 0
	}
	var closeReturnValue: Promise<Void>!
	var closeClosure: (() -> Promise<Void>)?

	func close() -> Promise<Void> {
		closeCallsCount += 1
		if let closeClosure = closeClosure {
			return closeClosure()
		} else {
			return closeReturnValue
		}
	}

	func clearInvocations() {
		getUrlQueryHeadersCallsCount = 0
		getUrlQueryHeadersReceivedArguments = nil
		getUrlQueryHeadersReceivedInvocations = []
		putUrlQueryHeadersBodyCallsCount = 0
		putUrlQueryHeadersBodyReceivedArguments = nil
		putUrlQueryHeadersBodyReceivedInvocations = []
		postUrlQueryHeadersBodyCallsCount = 0
		postUrlQueryHeadersBodyReceivedArguments = nil
		postUrlQueryHeadersBodyReceivedInvocations = []
		closeCallsCount = 0
	}
}

class OperatorMock: Operator {

	//MARK: - evaluate

	var evaluateCallsCount = 0
	var evaluateCalled: Bool {
		return evaluateCallsCount > 0
	}
	var evaluateReceivedArguments: (evaluator: Evaluator, args: JSON)?
	var evaluateReceivedInvocations: [(evaluator: Evaluator, args: JSON)] = []
	var evaluateReturnValue: JSON!
	var evaluateClosure: ((Evaluator, JSON) -> JSON)?

	func evaluate(_ evaluator: Evaluator, _ args: JSON) -> JSON {
		evaluateCallsCount += 1
		evaluateReceivedArguments = (evaluator: evaluator, args: args)
		evaluateReceivedInvocations.append((evaluator: evaluator, args: args))
		if let evaluateClosure = evaluateClosure {
			return evaluateClosure(evaluator, args)
		} else {
			return evaluateReturnValue
		}
	}

	func clearInvocations() {
		evaluateCallsCount = 0
		evaluateReceivedArguments = nil
		evaluateReceivedInvocations = []
	}
}

class ResponseMock: Response {
	var status: Int {
		get { return underlyingStatus }
		set(value) { underlyingStatus = value }
	}
	var underlyingStatus: Int!
	var statusMessage: String {
		get { return underlyingStatusMessage }
		set(value) { underlyingStatusMessage = value }
	}
	var underlyingStatusMessage: String!
	var contentType: String {
		get { return underlyingContentType }
		set(value) { underlyingContentType = value }
	}
	var underlyingContentType: String!
	var content: Data {
		get { return underlyingContent }
		set(value) { underlyingContent = value }
	}
	var underlyingContent: Data!

	func clearInvocations() {
	}
}

class ScheduledHandleMock: ScheduledHandle {

	//MARK: - cancel

	var cancelCallsCount = 0
	var cancelCalled: Bool {
		return cancelCallsCount > 0
	}
	var cancelClosure: (() -> Void)?

	func cancel() {
		cancelCallsCount += 1
		cancelClosure?()
	}

	//MARK: - isCancelled

	var isCancelledCallsCount = 0
	var isCancelledCalled: Bool {
		return isCancelledCallsCount > 0
	}
	var isCancelledReturnValue: Bool!
	var isCancelledClosure: (() -> Bool)?

	func isCancelled() -> Bool {
		isCancelledCallsCount += 1
		if let isCancelledClosure = isCancelledClosure {
			return isCancelledClosure()
		} else {
			return isCancelledReturnValue
		}
	}

	func clearInvocations() {
		cancelCallsCount = 0
		isCancelledCallsCount = 0
	}
}

class SchedulerMock: Scheduler {

	//MARK: - schedule

	var scheduleAfterExecuteCallsCount = 0
	var scheduleAfterExecuteCalled: Bool {
		return scheduleAfterExecuteCallsCount > 0
	}
	var scheduleAfterExecuteReceivedArguments: (after: TimeInterval, execute: Work)?
	var scheduleAfterExecuteReceivedInvocations: [(after: TimeInterval, execute: Work)] = []
	var scheduleAfterExecuteReturnValue: ScheduledHandle!
	var scheduleAfterExecuteClosure: ((TimeInterval, @escaping Work) -> ScheduledHandle)?

	func schedule(after: TimeInterval, execute: @escaping Work) -> ScheduledHandle {
		scheduleAfterExecuteCallsCount += 1
		scheduleAfterExecuteReceivedArguments = (after: after, execute: execute)
		scheduleAfterExecuteReceivedInvocations.append((after: after, execute: execute))
		if let scheduleAfterExecuteClosure = scheduleAfterExecuteClosure {
			return scheduleAfterExecuteClosure(after, execute)
		} else {
			return scheduleAfterExecuteReturnValue
		}
	}

	//MARK: - scheduleWithFixedDelay

	var scheduleWithFixedDelayAfterRepeatingExecuteCallsCount = 0
	var scheduleWithFixedDelayAfterRepeatingExecuteCalled: Bool {
		return scheduleWithFixedDelayAfterRepeatingExecuteCallsCount > 0
	}
	var scheduleWithFixedDelayAfterRepeatingExecuteReceivedArguments:
		(after: TimeInterval, repeating: TimeInterval, execute: Work)?
	var scheduleWithFixedDelayAfterRepeatingExecuteReceivedInvocations:
		[(after: TimeInterval, repeating: TimeInterval, execute: Work)] = []
	var scheduleWithFixedDelayAfterRepeatingExecuteReturnValue: ScheduledHandle!
	var scheduleWithFixedDelayAfterRepeatingExecuteClosure:
		((TimeInterval, TimeInterval, @escaping Work) -> ScheduledHandle)?

	func scheduleWithFixedDelay(after: TimeInterval, repeating: TimeInterval, execute: @escaping Work)
		-> ScheduledHandle
	{
		scheduleWithFixedDelayAfterRepeatingExecuteCallsCount += 1
		scheduleWithFixedDelayAfterRepeatingExecuteReceivedArguments = (
			after: after, repeating: repeating, execute: execute
		)
		scheduleWithFixedDelayAfterRepeatingExecuteReceivedInvocations.append(
			(after: after, repeating: repeating, execute: execute))
		if let scheduleWithFixedDelayAfterRepeatingExecuteClosure = scheduleWithFixedDelayAfterRepeatingExecuteClosure {
			return scheduleWithFixedDelayAfterRepeatingExecuteClosure(after, repeating, execute)
		} else {
			return scheduleWithFixedDelayAfterRepeatingExecuteReturnValue
		}
	}

	func clearInvocations() {
		scheduleAfterExecuteCallsCount = 0
		scheduleAfterExecuteReceivedArguments = nil
		scheduleAfterExecuteReceivedInvocations = []
		scheduleWithFixedDelayAfterRepeatingExecuteCallsCount = 0
		scheduleWithFixedDelayAfterRepeatingExecuteReceivedArguments = nil
		scheduleWithFixedDelayAfterRepeatingExecuteReceivedInvocations = []
	}
}

class VariableParserMock: VariableParser {

	//MARK: - parse

	var parseExperimentNameConfigCallsCount = 0
	var parseExperimentNameConfigCalled: Bool {
		return parseExperimentNameConfigCallsCount > 0
	}
	var parseExperimentNameConfigReceivedArguments: (experimentName: String, config: String)?
	var parseExperimentNameConfigReceivedInvocations: [(experimentName: String, config: String)] = []
	var parseExperimentNameConfigReturnValue: [String: JSON]?
	var parseExperimentNameConfigClosure: ((String, String) -> [String: JSON]?)?

	func parse(experimentName: String, config: String) -> [String: JSON]? {
		parseExperimentNameConfigCallsCount += 1
		parseExperimentNameConfigReceivedArguments = (experimentName: experimentName, config: config)
		parseExperimentNameConfigReceivedInvocations.append((experimentName: experimentName, config: config))
		if let parseExperimentNameConfigClosure = parseExperimentNameConfigClosure {
			return parseExperimentNameConfigClosure(experimentName, config)
		} else {
			return parseExperimentNameConfigReturnValue
		}
	}

	func clearInvocations() {
		parseExperimentNameConfigCallsCount = 0
		parseExperimentNameConfigReceivedArguments = nil
		parseExperimentNameConfigReceivedInvocations = []
	}
}
