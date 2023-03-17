//
// Created by Hermes Waldemarin on 09/03/2023.
//

import Foundation
import PromiseKit

public protocol LocalCache {
	func writeEvent(event: PublishEvent)
	func retrieveEvents() -> [PublishEvent]
	func writeContextData(contextData: ContextData)
	func getContextData() -> ContextData?
}
