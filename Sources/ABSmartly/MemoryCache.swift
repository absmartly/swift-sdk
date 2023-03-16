//
// Created by Hermes Waldemarin on 09/03/2023.
//

import Foundation
import PromiseKit
import SQLite

class MemoryCache : SqlliteCache {

    public var memorydb = try! Connection(.inMemory)

    override public var db: Connection {
        get {
            return memorydb
        }
        set {}
    }

}
