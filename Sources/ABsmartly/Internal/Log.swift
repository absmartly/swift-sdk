import Foundation

#if canImport(os)
	import os
#endif

/// The SDK's own diagnostics (malformed payload fields, regex limits). Not customer events: those
/// go to the context's event logger and event streams.
enum Log {
	// Test hook: sees every error message before it is written.
	private static let observer = Locked<(@Sendable (String) -> Void)?>(nil)

	static func setObserver(_ newValue: (@Sendable (String) -> Void)?) {
		observer.withLock { $0 = newValue }
	}

	#if canImport(os)
		private static let logger = os.Logger(subsystem: "com.absmartly.sdk", category: "ABsmartly")
	#endif

	static func error(_ message: String) {
		observer.withLock { $0 }?(message)
		#if canImport(os)
			logger.error("\(message, privacy: .public)")
		#else
			print("ABsmartly Error: " + message)
		#endif
	}
}

enum EventLog {
	#if canImport(os)
		private static let logger = os.Logger(subsystem: "com.absmartly.sdk", category: "events")
	#endif

	static func write(_ event: Context.Event) {
		let text = String(describing: event)
		#if canImport(os)
			if case .error = event {
				logger.error("\(text, privacy: .public)")
			} else {
				logger.debug("\(text, privacy: .public)")
			}
		#else
			print("ABsmartly: " + text)
		#endif
	}
}
