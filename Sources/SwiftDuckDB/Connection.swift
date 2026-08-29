public actor Connection {
    private let database: Database
    private let nativeConnection: NativeConnection

    init(database: Database, nativeDatabase: NativeDatabase) throws {
        self.database = database
        self.nativeConnection = try nativeDatabase.connect()
    }
}
