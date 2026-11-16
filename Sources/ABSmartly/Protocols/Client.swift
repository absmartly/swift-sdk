import PromiseKit

// sourcery: AutoMockable
public protocol Client {
	func getContextData() -> Promise<ContextData>
	func publish(event: PublishEvent) -> Promise<Void>
	func close() -> Promise<Void>

	/// The configured application name, used by audiences and assignment-rule conditions
	/// as the `application` attribute. Returns `nil` when the client does not expose it.
	func getApplication() -> String?

	/// The configured environment name, used by audiences and assignment-rule conditions
	/// as the `environment` attribute. Returns `nil` when the client does not expose it.
	func getEnvironment() -> String?
}

extension Client {
	// Default implementations keep existing `Client` conformances source-compatible: a client
	// that predates these methods simply contributes no `application`/`environment` attribute.
	public func getApplication() -> String? { return nil }
	public func getEnvironment() -> String? { return nil }
}
