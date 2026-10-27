import Foundation
import PromiseKit

// sourcery: AutoMockable
public protocol ContextPublisher {
	func publish(event: PublishEvent) -> Promise<Void>
}
