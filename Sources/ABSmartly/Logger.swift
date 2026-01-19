import Foundation
#if canImport(OSLog)
import OSLog
#endif

class Logger {
	static func error(_ error: String) {
		#if canImport(OSLog)
		if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
			let customLog = os.Logger(subsystem: "ABSmartly", category: "")
			customLog.error("\(error)")
		} else if #available(macOS 10.12, iOS 10.0, *) {
			let log = OSLog(subsystem: "ABSmartly", category: "")
			os_log("%@", log: log, type: .error, error)
		} else {
			print("ABSmartly Error: " + error)
		}
		#else
		print("ABSmartly Error: " + error)
		#endif
	}

	static func notice(_ note: String) {
		#if canImport(OSLog)
		if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
			let customLog = os.Logger(subsystem: "ABSmartly", category: "")
			customLog.notice("\(note)")
		} else if #available(macOS 10.12, iOS 10.0, *) {
			let log = OSLog(subsystem: "ABSmartly", category: "")
			os_log("%@", log: log, type: .default, note)
		} else {
			print("ABSmartly Note: " + note)
		}
		#else
		print("ABSmartly Note: " + note)
		#endif
	}
}
