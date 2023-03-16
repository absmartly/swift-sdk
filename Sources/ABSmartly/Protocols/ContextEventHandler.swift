import Foundation
import PromiseKit

// sourcery: AutoMockable
public protocol ContextEventHandler {
	func publish(event: PublishEvent) -> Promise<Void>
	func flushCache()
}
