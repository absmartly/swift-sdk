import ABSmartly

// A clock that always returns the same time. Used instead of the generated ClockMock, whose call
// counter is not synchronized and races when contexts read the clock from several threads.
final class FixedClock: Clock {
	private let value: Int64

	init(_ value: Int64) {
		self.value = value
	}

	func millis() -> Int64 {
		return value
	}
}
