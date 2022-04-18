import Foundation

// sourcery: AutoMockable
public protocol Clock {
	func millis() -> Int64
}
