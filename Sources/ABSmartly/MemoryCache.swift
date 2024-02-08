//
// Created by Hermes Waldemarin on 09/03/2023.
//

import Foundation
import PromiseKit
import SQLite

public class MemoryCache: SqlliteCache {
	public override init() {
	}

	public override func getConnection() -> Connection {
		do {
			if db == nil {
				db = try! Connection(.inMemory)
				setupDatabase()
			}
		} catch {
			print(error)
		}
		return self.db!
	}

}
