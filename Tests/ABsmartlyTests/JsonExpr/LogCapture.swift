import Foundation

@testable import ABsmartly

/// Collects the SDK's `Log.error` messages. One observer is installed for the whole process and
/// fans messages into a buffer, so suites running in parallel never replace each other's observer;
/// tests filter the buffer by a marker unique to them.
enum LogCapture {
	private static let messages = Locked<[String]>([])
	private static let installed: Void = Log.setObserver { message in
		LogCapture.messages.withLock { $0.append(message) }
	}

	static func install() {
		_ = installed
	}

	static func messages(containing marker: String) -> [String] {
		install()
		return messages.withLock { $0 }.filter { $0.contains(marker) }
	}
}

/// An expression that, when evaluated, logs a message containing `marker` (an invalid regex) and
/// gives null. Used where 1.x asserted on a mock evaluator's `evaluate` calls: 2.0's operators are
/// not injectable, so "was this argument evaluated" is observed through the log instead.
func evaluationProbe(_ marker: String) -> JSONValue {
	LogCapture.install()
	return ["match": [["value": "x"], ["value": .string("[" + marker)]]]
}

func wasEvaluated(_ marker: String) -> Bool {
	!LogCapture.messages(containing: marker).isEmpty
}

/// A unique marker for `evaluationProbe`.
func uniqueMarker(_ function: String = #function) -> String {
	"probe-\(function)-\(UUID().uuidString)"
}
