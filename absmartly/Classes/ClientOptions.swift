//
//  ClientOptions.swift
//  absmartly
//
//  Created by Roman Odyshew on 18.08.2021.
//

import Foundation

public struct ClientOptions {
    let agent: String = "swift-client"
    let retries: Int
    let timeout: TimeInterval
    
    public var apiKey: String
    public var application: String
    public var endpoint: String
    public var environment: String
    public var version: String
    
    public init(_ apiKey: String, _ application: String, _ endpoint: String, _ environment: String, _ version: String, _ retries: Int = 3, _ timeout: TimeInterval = 1.5) {
        self.apiKey = apiKey
        self.application = application
        self.endpoint = endpoint
        self.environment = environment
        self.version = version
        self.retries = retries
        self.timeout = timeout
    }
}
