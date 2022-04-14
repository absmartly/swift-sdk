import Foundation

class RequestFactory {
	private let options: ClientOptions

	init(_ options: ClientOptions) {
		self.options = options

		if options.apiKey.isEmpty {
			Logger.error("The API key can not be empty")
		}

		if options.application.isEmpty {
			Logger.error("The application name can not be empty")
		}
	}

	var publishRequest: URLRequest? {
		guard let url = getContextUrl(nil) else {
			return nil
		}

		var request = URLRequest(url: url)
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue(options.apiKey, forHTTPHeaderField: "X-API-Key")
		request.setValue(options.application, forHTTPHeaderField: "X-Application")
		request.setValue(options.environment, forHTTPHeaderField: "X-Environment")
		request.setValue(String(options.applicationVersion), forHTTPHeaderField: "X-Application-Version")
		request.setValue(options.agent, forHTTPHeaderField: "X-Agent")

		request.httpMethod = "PUT"

		return request
	}

	var contextRequest: URLRequest? {
		guard let url = getContextUrl(["application": options.application, "environment": options.environment]) else {
			return nil
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		return request
	}

	private func getContextUrl(_ querryParams: [String: String]?) -> URL? {
		var urlComponents: URLComponents? = URLComponents(
			string: options.endpoint + ((options.endpoint.last == "/") ? "context" : "/context"))

		if let querryParams = querryParams {
			urlComponents?.queryItems = querryParams.compactMap { (key, value) in
				guard !key.isEmpty, !value.isEmpty else {
					return nil
				}
				return URLQueryItem(name: key, value: value)
			}

			let percentEncodedQuery: String? = urlComponents?.percentEncodedQuery?.replacingOccurrences(
				of: "+", with: "%2B")
			urlComponents?.percentEncodedQuery = percentEncodedQuery
		}

		if urlComponents?.url == nil {
			Logger.error("Fails to compose a valid URL from: " + options.endpoint + "/context")
		}

		return urlComponents?.url
	}
}
