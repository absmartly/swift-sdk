import Foundation
import PromiseKit

// sourcery: AutoMockable
public protocol Response {
	var status: Int { get }
	var statusMessage: String { get }
	var contentType: String { get }
	var content: Data { get }
}

// sourcery: AutoMockable
public protocol HTTPClient {
	func get(url: String, query: [String: String]?, headers: [String: String]?) -> Promise<Response>
	func put(url: String, query: [String: String]?, headers: [String: String]?, body: Data?) -> Promise<Response>
	func post(url: String, query: [String: String]?, headers: [String: String]?, body: Data?) -> Promise<Response>
	func close() -> Promise<Void>
}
