// Generated using Sourcery 1.7.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT

import Foundation
import PromiseKit

@testable import ABSmartly

// swiftlint:disable line_length
// swiftlint:disable variable_name

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

}
class ScheduledHandleMock: ScheduledHandle {

	//MARK: - wait

	var waitCallsCount = 0
	var waitCalled: Bool {
		return waitCallsCount > 0
	}
	var waitClosure: (() -> Void)?

	func wait() {
		waitCallsCount += 1
		waitClosure?()
	}

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

}
