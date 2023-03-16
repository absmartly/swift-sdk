//
// Created by Hermes Waldemarin on 09/03/2023.
//

import Foundation
import PromiseKit

public protocol LocalCache {
    func writeEvent(event: PublishEvent) -> Promise<Void>
    func retrieveEvents() -> Promise<[PublishEvent]>
    func writeContextData(contextData: ContextData) -> Promise<Void>
    func getContextData() -> Promise<ContextData?>
}
