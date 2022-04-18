import PromiseKit

// sourcery: AutoMockable
public protocol Client {
	func getContextData() -> Promise<ContextData>
	func publish(event: PublishEvent) -> Promise<Void>
	func close() -> Promise<Void>
}
