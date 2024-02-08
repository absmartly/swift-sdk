//
// Created by Hermes Waldemarin on 09/03/2023.
//

import Foundation
import PromiseKit
import SQLite

public class SqlliteCache: LocalCache {

	let path = NSSearchPathForDirectoriesInDomains(
		.documentDirectory, .userDomainMask, true)

	var db: Connection?

	public init() {
	}

	public func getConnection() -> Connection {
		do {
			if db == nil {
				db = try! Connection("\(path.first ?? "")/absmartly.sqlite3")
				setupDatabase()
			}
		} catch {
			Logger.error(error.localizedDescription)
		}
		return self.db!
	}

	public func setupDatabase() {
		do {
			var stmt = try getConnection().prepare(
				"create table if not exists  events (id INTEGER PRIMARY KEY AUTOINCREMENT, event text)")
			try stmt.run()

			stmt = try getConnection().prepare(
				"create table if not exists  context (id INTEGER PRIMARY KEY AUTOINCREMENT, context text)")
			try stmt.run()
		} catch {
			Logger.error(error.localizedDescription)
		}
	}

	public func writePublishEvent(event: PublishEvent) {
		do {
			let stmt = try self.getConnection().prepare("insert into events (event) values (?)")
			let eventStr = try JSONEncoder().encode(event)
			let binding = String(bytes: eventStr, encoding: .utf8)
			try stmt.run(binding)
		} catch {
			Logger.error(error.localizedDescription)
		}
	}

	public func retrievePublishEvents() -> [PublishEvent] {
		var events: [PublishEvent] = [PublishEvent]()
		do {
			for row in try self.getConnection().prepare("select * from events") {
				let dataString = row[1] as? String ?? ""
				let data = dataString.data(using: .utf8) ?? Data()
				let event = try JSONDecoder().decode(PublishEvent.self, from: data)
				events.append(event)
			}
			let deleteStm = try self.getConnection().prepare("delete from events")
			try deleteStm.run()
		} catch {
			Logger.error(error.localizedDescription)
		}
		return events
	}

	public func writeContextData(contextData: ContextData) {
		do {
			let deleteStm = try self.getConnection().prepare("delete from context")
			try deleteStm.run()

			let stmt = try getConnection().prepare("insert into context (context) values (?)")
			let data = try JSONEncoder().encode(contextData)
			let binding = String(data: data, encoding: .utf8)
			try stmt.run(binding)
		} catch {
			Logger.error(error.localizedDescription)
		}
	}

	public func getContextData() -> ContextData? {
		var contextData: ContextData?
		do {
			for row in try self.getConnection().prepare("select * from context") {
				let dataString = row[1] as? String ?? ""
				let data = dataString.data(using: .utf8) ?? Data()
				let ctx = try JSONDecoder().decode(ContextData.self, from: data)
				contextData = ctx
			}
		} catch {
			Logger.error(error.localizedDescription)
		}
		return contextData
	}

}
