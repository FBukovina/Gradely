import Foundation

enum FriendTimetableError: LocalizedError, Equatable {
    case signInAgain
    case missingTimetable

    var errorDescription: String? {
        switch self {
        case .signInAgain: AppL10n.string("friends.error.signInAgain")
        case .missingTimetable: AppL10n.string("friends.error.missingTimetable")
        }
    }
}

/// Adds friends and loads their timetables from whichever source they came
/// from, as the same `TimetableWeek` your own timetable uses.
final class FriendRepository {
    private let store: any FriendStoring
    private let client: any BakalariClient
    private let publicClient: any BakalariPublicTimetableClient
    private let cache: any TimetableCaching
    private let dateProvider: () -> Date

    init(
        store: any FriendStoring,
        client: any BakalariClient,
        publicClient: any BakalariPublicTimetableClient,
        cache: any TimetableCaching = InMemoryTimetableCache(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.client = client
        self.publicClient = publicClient
        self.cache = cache
        self.dateProvider = dateProvider
    }

    // MARK: - List

    func loadFriends() -> [Friend] {
        store.loadFriends()
    }

    func save(_ friends: [Friend]) {
        try? store.saveFriends(friends)
    }

    func removeData(for friend: Friend) {
        store.removeData(friendID: friend.id)
        try? cache.clear(scope: Self.scope(friend))
    }

    func clearCache(for friends: [Friend]) {
        friends.forEach { try? cache.clear(scope: Self.scope($0)) }
    }

    // MARK: - Adding

    /// Signs the friend in and loads this week once, so a wrong password or
    /// school fails here rather than on the timetable.
    func connectBakalari(name: String, schoolURL: String, schoolName: String?, username: String, password: String) async throws -> Friend {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { throw AppError.missingFields }
        let baseURL = try SchoolURLNormalizer.normalizedBaseURL(from: schoolURL)
        let response = try await client.login(baseURL: baseURL, username: username, password: password)
        let friend = Friend(
            id: UUID(), name: name,
            source: .bakalari(schoolURL: baseURL, schoolName: schoolName, username: username),
            addedAt: dateProvider()
        )
        try store.saveSession(
            session(from: response, baseURL: baseURL, credentials: BakalariCredentials(username: username, password: password)),
            friendID: friend.id
        )
        do {
            _ = try await loadWeek(for: friend, weekContaining: dateProvider(), kind: .weekly)
        } catch {
            store.removeData(friendID: friend.id)
            throw error
        }
        return friend
    }

    func publicClasses(schoolURL: String) async throws -> (URL, [PublicTimetableClass]) {
        let baseURL = try SchoolURLNormalizer.normalizedBaseURL(from: schoolURL)
        return (baseURL, try await publicClient.fetchClasses(schoolURL: baseURL))
    }

    /// The class's groups (language and PE splits), read from its permanent timetable.
    func publicGroups(schoolURL: URL, classID: String) async throws -> [String] {
        let response = try await publicClient.fetchTimetable(
            schoolURL: schoolURL, classID: classID, term: .permanent, weekStart: TimetableDates.monday(of: dateProvider())
        )
        return Set(response.groups.map(\.abbrev).filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func makePublicFriend(name: String, schoolURL: URL, schoolName: String?, schoolClass: PublicTimetableClass, groups: [String]?) -> Friend {
        Friend(
            id: UUID(), name: name,
            source: .publicClass(schoolURL: schoolURL, schoolName: schoolName, classID: schoolClass.id, className: schoolClass.name, groups: groups),
            addedAt: dateProvider()
        )
    }

    func makeImportedFriend(name: String, draft: ImportedTimetableDraft, excludingGroups: Set<String>, fileName: String?) throws -> Friend {
        let friend = Friend(id: UUID(), name: name, source: .imported(fileName: fileName), addedAt: dateProvider())
        try store.saveImportedTimetable(draft.makeResponse(excludingGroups: excludingGroups), friendID: friend.id)
        return friend
    }

    // MARK: - Timetable

    func cachedWeek(for friend: Friend, weekContaining date: Date, kind: TimetableKind) -> TimetableWeek? {
        let monday = TimetableDates.monday(of: date)
        if case .imported = friend.source {
            return importedWeek(for: friend, monday: monday)
        }
        guard let cached = try? cache.load(weekStart: monday, scope: Self.scope(friend), kind: kind) else { return nil }
        return week(from: cached.response, friend: friend, monday: monday, kind: kind)
    }

    func loadWeek(for friend: Friend, weekContaining date: Date, kind: TimetableKind) async throws -> TimetableWeek {
        let monday = TimetableDates.monday(of: date)
        let response: TimetableResponse
        switch friend.source {
        case .imported:
            guard let week = importedWeek(for: friend, monday: monday) else { throw FriendTimetableError.missingTimetable }
            return week

        case .bakalari:
            response = try await withSession(of: friend) { session in
                kind == .permanent
                    ? try await self.client.fetchPermanentTimetable(baseURL: session.baseURL, accessToken: session.accessToken)
                    : try await self.client.fetchTimetable(baseURL: session.baseURL, accessToken: session.accessToken, date: monday)
            }

        case .publicClass(let schoolURL, _, let classID, _, _):
            // The public page has this week, next week and the permanent
            // timetable; any other week shows the permanent one on its dates.
            let thisWeek = TimetableDates.monday(of: dateProvider())
            let term: PublicTimetableTerm = kind == .permanent ? .permanent
                : monday == thisWeek ? .actual
                : monday == TimetableDates.addingWeeks(1, to: thisWeek) ? .next
                : .permanent
            let fetched = try await publicClient.fetchTimetable(schoolURL: schoolURL, classID: classID, term: term, weekStart: monday)
            response = kind == .weekly && term == .permanent ? fetched.rebased(toWeekContaining: monday) : fetched
        }

        try? cache.save(response, weekStart: monday, scope: Self.scope(friend), kind: kind)
        return week(from: response, friend: friend, monday: monday, kind: kind)
    }

    // MARK: - Private

    private static func scope(_ friend: Friend) -> SchoolDataScope {
        SchoolDataScope(rawValue: "friend-\(friend.id.uuidString)")
    }

    private func importedWeek(for friend: Friend, monday: Date) -> TimetableWeek? {
        guard let response = store.loadImportedTimetable(friendID: friend.id) else { return nil }
        return TimetableMapper.makeWeek(from: response.rebased(toWeekContaining: monday), weekStart: monday, today: dateProvider())
    }

    private func week(from response: TimetableResponse, friend: Friend, monday: Date, kind: TimetableKind) -> TimetableWeek {
        var response = response
        if case .publicClass(_, _, _, _, let groups?) = friend.source {
            response = Self.filtered(response, keepingGroups: Set(groups))
        }
        return TimetableMapper.makeWeek(from: response, weekStart: monday, today: dateProvider(), kind: kind)
    }

    /// A class timetable shows every group; keep whole-class lessons and the
    /// friend's own groups.
    static func filtered(_ response: TimetableResponse, keepingGroups kept: Set<String>) -> TimetableResponse {
        let names = Dictionary(response.groups.map { ($0.id, $0.abbrev) }, uniquingKeysWith: { first, _ in first })
        return TimetableResponse(
            hours: response.hours,
            days: response.days.map { day in
                TimetableDayDTO(
                    atoms: day.atoms.filter { atom in
                        atom.groupIDs.isEmpty || atom.groupIDs.contains { names[$0].map(kept.contains) ?? true }
                    },
                    dayOfWeek: day.dayOfWeek, date: day.date, dayDescription: day.dayDescription, dayType: day.dayType
                )
            },
            classes: response.classes, groups: response.groups, subjects: response.subjects,
            teachers: response.teachers, rooms: response.rooms, cycles: response.cycles
        )
    }

    /// Runs a request with the friend's token, refreshing it (or signing in
    /// again with the stored login) when Bakaláři rejects it.
    private func withSession<Value>(of friend: Friend, _ operation: (StoredSession) async throws -> Value) async throws -> Value {
        guard var session = store.loadSession(friendID: friend.id) else { throw FriendTimetableError.signInAgain }
        if session.isExpired {
            session = try await refreshed(session, friendID: friend.id)
        }
        do {
            return try await operation(session)
        } catch BakalariAPIError.httpStatus(401, _) {
            return try await operation(try await refreshed(session, friendID: friend.id))
        }
    }

    private func refreshed(_ session: StoredSession, friendID: UUID) async throws -> StoredSession {
        let response: LoginResponse
        do {
            response = try await client.refreshToken(baseURL: session.baseURL, refreshToken: session.refreshToken)
        } catch BakalariAPIError.httpStatus(let status, _) where status == 400 || status == 401 {
            guard let credentials = session.bakalari else { throw FriendTimetableError.signInAgain }
            do {
                response = try await client.login(baseURL: session.baseURL, username: credentials.username, password: credentials.password)
            } catch BakalariAPIError.httpStatus(let status, _) where status == 400 || status == 401 {
                throw FriendTimetableError.signInAgain
            }
        }
        let updated = self.session(from: response, baseURL: session.baseURL, credentials: session.bakalari)
        try store.saveSession(updated, friendID: friendID)
        return updated
    }

    private func session(from response: LoginResponse, baseURL: URL, credentials: BakalariCredentials?) -> StoredSession {
        StoredSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            tokenType: response.tokenType,
            expiresAt: dateProvider().addingTimeInterval(TimeInterval(response.expiresIn)),
            baseURL: baseURL,
            bakalari: credentials
        )
    }
}
