import Foundation

class Queue<T> {
	private var queue: [T] = []
	private let lock: NSLock = NSLock()

	func addElement(_ element: T) {
		lock.lock()
		defer { lock.unlock() }

		queue.append(element)
	}

	func dequeue() -> T? {
		lock.lock()
		defer { lock.unlock() }

		return queue.removeFirst()
	}

	var count: Int {
		lock.lock()
		defer { lock.unlock() }

		return queue.count
	}
}
