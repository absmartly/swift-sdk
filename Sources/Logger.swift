//
//  Logger.swift
//  absmartly
//
//  Created by Roman Odyshew on 18.08.2021.
//

import Foundation
import OSLog

class Logger {
    static func error(_ error: String) {
        #if os(OSX)
        if #available(macOS 11.0, *) {
            let customLog = os.Logger(subsystem: "ABSmartly", category: "")
            customLog.error("\(error)")
        } else {
            let log = OSLog(subsystem: "ABSmartly", category: "")
            os_log("%@", log: log, type: .error, error)
        }
        
        #else
        if #available(iOS 14.0, *) {
            let customLog = os.Logger(subsystem: "ABSmartly", category: "")
            customLog.error("\(error)")
        } else if #available(iOS 10.0, *) {
            let log = OSLog(subsystem: "ABSmartly", category: "")
            os_log("%@", log: log, type: .error, error)
        } else {
            print("ABSmartly Error: " + error)
        }
        #endif
    }
    
    static func notice(_ note: String) {
        #if os(OSX)
        if #available(macOS 11.0, *) {
            let customLog = os.Logger(subsystem: "ABSmartly", category: "")
            customLog.notice("\(note)")
        } else {
            let log = OSLog(subsystem: "ABSmartly", category: "")
            os_log("%@", log: log, type: .default, note)
        }
        
        #else
        if #available(iOS 14.0, *) {
            let customLog = os.Logger(subsystem: "ABSmartly", category: "")
            customLog.notice("\(note)")
        } else if #available(iOS 10.0, *) {
            let log = OSLog(subsystem: "ABSmartly", category: "")
            os_log("%@", log: log, type: .default, note)
        } else {
            print("ABSmartly Note: " + note)
        }
        #endif
    }
}
