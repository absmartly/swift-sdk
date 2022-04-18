import Foundation
import PromiseKit

// sourcery: AutoMockable
public protocol ContextDataProvider {
	func getContextData() -> Promise<ContextData>
}
