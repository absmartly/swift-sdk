import Foundation

#if canImport(os)
	import os
#endif

/// One diagnostic line. `summary` says what failed (SDK text, experiment and field names) and is
/// logged public; `detail` holds customer payload text (variant configs, field values, regex
/// patterns, audiences, error text, event contents) and is logged private on Apple platforms, so
/// the unified log redacts it unless the device is set up to show private data.
struct LogEntry: Sendable, Equatable {
	let summary: String
	let detail: String?

	/// The whole line, as printed on Linux.
	var text: String {
		detail.map { "\(summary) \($0)" } ?? summary
	}
}

/// The SDK's own diagnostics (malformed payload fields, regex limits). Not customer events: those
/// go to the context's event logger and event streams.
enum Log {
	// Test hook: sees every entry before it is written.
	private static let observer = Locked<(@Sendable (LogEntry) -> Void)?>(nil)

	static func setObserver(_ newValue: (@Sendable (LogEntry) -> Void)?) {
		observer.withLock { $0 = newValue }
	}

	#if canImport(os)
		private static let logger = os.Logger(subsystem: "com.absmartly.sdk", category: "ABsmartly")
	#endif

	static func error(_ summary: String, detail: String? = nil) {
		let entry = LogEntry(summary: summary, detail: detail)
		observer.withLock { $0 }?(entry)
		#if canImport(os)
			if let detail {
				logger.error("\(summary, privacy: .public) \(detail, privacy: .private)")
			} else {
				logger.error("\(summary, privacy: .public)")
			}
		#else
			print("ABsmartly Error: " + entry.text)
		#endif
	}

	static func error(_ summary: String, _ error: ABsmartlyError) {
		self.error("\(summary): \(error.logSummary)", detail: error.logDetail)
	}
}

extension ABsmartlyError {
	/// The error's kind, with SDK-generated text only. Every case that carries a string (which a
	/// custom transport can set) is named by its kind; that string is `logDetail`.
	var logSummary: String {
		switch self {
		case .invalidConfiguration: return "invalid configuration"
		case .httpStatus(let code, _): return "HTTP status \(code)"
		case .transport: return "transport error"
		case .decoding: return "decoding error"
		case .notReady, .closing, .closed, .blankUnitUID, .unitAlreadySet, .cancelled: return description
		}
	}

	/// The caller- or payload-supplied text of the error, logged privately.
	var logDetail: String? {
		switch self {
		case .invalidConfiguration(let message), .httpStatus(_, let message), .transport(let message),
			.decoding(let message):
			return message
		case .notReady, .closing, .closed, .blankUnitUID, .unitAlreadySet, .cancelled: return nil
		}
	}
}

enum EventLog {
	#if canImport(os)
		private static let logger = os.Logger(subsystem: "com.absmartly.sdk", category: "events")
	#endif

	static func entry(_ event: Context.Event) -> LogEntry {
		switch event {
		case .ready: return LogEntry(summary: "ready", detail: String(describing: event))
		case .refresh: return LogEntry(summary: "refresh", detail: String(describing: event))
		case .publish: return LogEntry(summary: "publish", detail: String(describing: event))
		case .exposure(let exposure):
			return LogEntry(summary: "exposure '\(exposure.name)'", detail: String(describing: event))
		case .goal(let goal): return LogEntry(summary: "goal '\(goal.name)'", detail: String(describing: event))
		case .close: return LogEntry(summary: "close", detail: nil)
		case .error(let error): return LogEntry(summary: "error: \(error.logSummary)", detail: error.logDetail)
		}
	}

	static func write(_ event: Context.Event) {
		let entry = entry(event)
		#if canImport(os)
			let summary = entry.summary
			let detail = entry.detail ?? ""
			if case .error = event {
				logger.error("\(summary, privacy: .public) \(detail, privacy: .private)")
			} else {
				logger.debug("\(summary, privacy: .public) \(detail, privacy: .private)")
			}
		#else
			print("ABsmartly: " + entry.text)
		#endif
	}
}
