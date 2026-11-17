import Foundation

#if canImport(os)
	import os
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#endif

/// A non-recursive lock around a value: `os_unfair_lock` on Apple platforms (`OSAllocatedUnfairLock`
/// needs iOS 16 and `Mutex` iOS 18, above the floor) and a `pthread_mutex_t` elsewhere. Both are
/// heap-allocated so they never move.
///
/// Never call user code (event loggers, transports, continuations) while holding it.
final class Locked<Value>: @unchecked Sendable {
	#if canImport(os)
		private let lock: os_unfair_lock_t
	#else
		private let lock: UnsafeMutablePointer<pthread_mutex_t>
	#endif
	private var value: Value

	init(_ value: Value) {
		self.value = value
		#if canImport(os)
			lock = .allocate(capacity: 1)
			lock.initialize(to: os_unfair_lock())
		#else
			lock = .allocate(capacity: 1)
			lock.initialize(to: pthread_mutex_t())
			pthread_mutex_init(lock, nil)
		#endif
	}

	deinit {
		#if !canImport(os)
			pthread_mutex_destroy(lock)
		#endif
		lock.deinitialize(count: 1)
		lock.deallocate()
	}

	private func acquire() {
		#if canImport(os)
			os_unfair_lock_lock(lock)
		#else
			pthread_mutex_lock(lock)
		#endif
	}

	private func release() {
		#if canImport(os)
			os_unfair_lock_unlock(lock)
		#else
			pthread_mutex_unlock(lock)
		#endif
	}

	func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
		acquire()
		defer { release() }
		return try body(&value)
	}
}
