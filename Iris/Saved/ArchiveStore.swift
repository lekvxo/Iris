import Foundation

actor ArchiveStore {
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Archives")) {
        self.directory = directory
    }
    func write(_ data: Data, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = id.uuidString + ".webarchive"
        try data.write(to: file(name), options: .atomic)
        return name
    }
    func read(_ name: String) throws -> Data { try Data(contentsOf: file(name)) }
    func delete(_ name: String) throws {
        let url = try file(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func file(_ name: String) throws -> URL {
        guard name == (name as NSString).lastPathComponent, name.hasSuffix(".webarchive"),
              UUID(uuidString: String(name.dropLast(".webarchive".count))) != nil else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return directory.appendingPathComponent(name)
    }
}
