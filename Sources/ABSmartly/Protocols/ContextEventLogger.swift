import Foundation
import PromiseKit

public enum ContextEventLoggerEvent: Equatable {
	case ready(data: ContextData)
	case refresh(data: ContextData)
	case publish(event: PublishEvent)
	case exposure(exposure: Exposure)
	case goal(goal: GoalAchievement)
	case close
	case error(error: Error)

	public static func == (lhs: ContextEventLoggerEvent, rhs: ContextEventLoggerEvent) -> Bool {
		switch (lhs, rhs) {
		case (let .ready(lhsData), let .ready(rhsData)):
			return lhsData == rhsData
		case (let .refresh(lhsData), let .refresh(rhsData)):
			return lhsData == rhsData
		case (let .publish(lhsData), let .publish(rhsData)):
			return lhsData == rhsData
		case (let .exposure(lhsData), let .exposure(rhsData)):
			return lhsData == rhsData
		case (let .goal(lhsData), let .goal(rhsData)):
			return lhsData == rhsData
		case (let .error(lhsError), let .error(rhsError)):
			return lhsError._code == rhsError._code && lhsError.localizedDescription == rhsError.localizedDescription
		case (.close, .close):
			return true
		default:
			return false
		}
	}
}

// sourcery: AutoMockable
public protocol ContextEventLogger {
	func handleEvent(context: Context, event: ContextEventLoggerEvent)
}
