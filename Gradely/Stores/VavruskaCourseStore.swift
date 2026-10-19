import Foundation

protocol VavruskaCourseStoring {
    func load() throws -> VavruskaStoredCourse?
    func save(_ course: VavruskaStoredCourse) throws
    func clear() throws
}

/// The ICS link works without a login, so it is a secret: it lives in the Keychain.
final class VavruskaCourseStore: VavruskaCourseStoring {
    private let keychain: KeychainClient
    private let account = "vavruska.course"

    init(keychain: KeychainClient = .live()) {
        self.keychain = keychain
    }

    func load() throws -> VavruskaStoredCourse? {
        guard let data = try keychain.read(account: account) else { return nil }
        return try JSONDecoder.sessionDecoder.decode(VavruskaStoredCourse.self, from: data)
    }

    func save(_ course: VavruskaStoredCourse) throws {
        try keychain.save(JSONEncoder.sessionEncoder.encode(course), account: account)
    }

    func clear() throws {
        try keychain.delete(account: account)
    }
}

final class InMemoryVavruskaCourseStore: VavruskaCourseStoring {
    private var course: VavruskaStoredCourse?

    init(course: VavruskaStoredCourse? = nil) {
        self.course = course
    }

    func load() throws -> VavruskaStoredCourse? { course }
    func save(_ course: VavruskaStoredCourse) throws { self.course = course }
    func clear() throws { course = nil }
}
