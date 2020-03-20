// MIT License
//
// Copyright (c) 2018 Marcin Krzyzanowski
//

import Foundation
import Dispatch
import KituraSession
import SwiftKuery

/// An implementation of the `Store` protocol for the storage of `Session` data Swift-Kuery.
public class KueryStore: Store {
    
    public class Sessions: Table {
        let tableName = "Sessions"
        let id = Column("id", String.self, primaryKey: true)
        let data = Column("data", String.self)
    }
    
    private let pool: SwiftKuery.ConnectionPool
    private var sessions: Sessions
    
    public init(pool: SwiftKuery.ConnectionPool) {
        self.pool = pool
        self.sessions = Sessions()
        self.setupDB()
    }
    
    private func setupDB() {
        self.pool.getConnection() { connection, error in
            guard let connection = connection else {
                print("Could not create connection to database in setup.  \(error?.localizedDescription ?? "")")
                return
            }
            self.sessions.create(connection: connection) { result in
                guard result.success else {
                    print("Failed to create table: \(result)")
                    return
                }
            }
        }
    }
    
    public func load(sessionId: String, callback: @escaping (Data?, NSError?) -> Void) {
        let query = Select(sessions.data, from: sessions).where(sessions.id == sessionId)
        self.pool.getConnection() { connection, error in
            guard let connection = connection else {
                print("Could not create connection to database in all to load(sessionId: \(sessionId).  \(error?.localizedDescription ?? "")")
                return
            }
            connection.execute(query: query) { result in
                guard result.success else {
                    callback(nil, result.asError as NSError?)
                    return
                }
                
                result.asRows { rows, error in
                    if let row = rows?.first {
                        if let base64String = row[self.sessions.data.name] as? String, let decodedData = Data(base64Encoded: base64String) {
                            callback(decodedData, nil)
                            return
                        }
                    }
                    callback(nil, nil)
                }
            }
        }
    }
    
    public func save(sessionId: String, data: Data, callback: @escaping (NSError?) -> Void) {
        let query = Insert(into: sessions, rows: [[sessionId, data.base64EncodedString()]])
        self.pool.getConnection() { connection, error in
            guard let connection = connection else {
                print("Could not create connection to database in all to save(sessionId: \(sessionId).  \(error?.localizedDescription ?? "")")
                return
            }
            connection.execute(query: query) { insertresult in
                // INSERT might fail, try UPDATE
                if !insertresult.success {
                    let uquery = Update(self.sessions, set: [(self.sessions.data, data.base64EncodedString())], where: self.sessions.id == sessionId)
                    connection.execute(query: uquery) { updateresult in
                        guard updateresult.success else {
                            let cError = NSError(domain: "Session", code: -108, userInfo: ["message": "couldn't either insert or update session"])
                            callback(cError)
                            return
                        }
                        callback(nil)
                    }
                }
                callback(nil)
             }
        }
    }
    
    public func touch(sessionId _: String, callback: @escaping (NSError?) -> Void) {
        callback(nil)
    }
    
    public func delete(sessionId: String, callback: @escaping (NSError?) -> Void) {
        let query = Delete(from: sessions, where: sessions.id == sessionId)
        self.pool.getConnection() { connection, error in
            guard let connection = connection else {
                print("Could not create connection to database in all to delete(sessionId: \(sessionId).  \(error?.localizedDescription ?? "")")
                return
            }
            connection.execute(query: query) { result in
                guard result.success else {
                    callback(result.asError as NSError?)
                    return
                }
                callback(nil)
            }
        }
    }
}
