import Foundation
import Observation

/// The Add friend flow: a name, then one of three ways to get their timetable.
@MainActor
@Observable
final class AddFriendViewModel {
    enum Step: Equatable {
        case method
        case bakalari
        case publicClass
        case groups
        case document
        case review
    }

    var step: Step = .method
    var name = ""

    // School search, shared by the Bakaláři and public timetable steps.
    var schoolSearchText = ""
    private(set) var schoolURL = ""
    private(set) var schoolName: String?
    private(set) var directorySchools: [SchoolDirectorySchool] = []
    private(set) var isSchoolDirectoryLoading = false
    var isSchoolSearchActive = false

    var username = ""
    var password = ""

    private(set) var classes: [PublicTimetableClass] = []
    private(set) var publicSchoolURL: URL?
    private(set) var selectedClass: PublicTimetableClass?
    private(set) var groups: [String] = []
    var selectedGroups: Set<String> = []

    private(set) var pages: [TimetableDocumentPage] = []
    private(set) var selectedPageID: Int?
    var draft: ImportedTimetableDraft?
    var excludedGroups: Set<String> = []
    private(set) var fileName: String?

    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private let friends: FriendsViewModel
    @ObservationIgnored private var hasLoadedDirectory = false

    init(friends: FriendsViewModel) {
        self.friends = friends
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSchool: Bool { !schoolURL.isEmpty }

    var schoolResults: [SchoolDirectorySchool] {
        guard isSchoolSearchActive else { return [] }
        return SchoolDirectorySearch.results(for: schoolSearchText, in: directorySchools)
    }

    /// A typed address, offered when the search finds nothing.
    var typedSchoolAddress: String? {
        let text = schoolSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSchoolSearchActive, text.contains("."), !text.contains(" ") else { return nil }
        return text
    }

    var parsedPages: [TimetableDocumentPage] {
        pages.filter { $0.draft != nil }
    }

    // MARK: - Navigation

    func choose(_ step: Step) {
        errorMessage = nil
        self.step = step
    }

    func goBack() {
        errorMessage = nil
        switch step {
        case .method: break
        case .bakalari, .publicClass, .document: step = .method
        case .groups: step = .publicClass
        case .review: step = .document
        }
    }

    // MARK: - School

    func loadSchoolDirectoryIfNeeded() async {
        guard !hasLoadedDirectory else { return }
        hasLoadedDirectory = true
        let cached = try? friends.schoolDirectoryProvider.loadCachedDirectory()
        directorySchools = cached?.schools ?? []
        preselectOwnSchool()
        guard cached.map({ $0.isStale() || !$0.isCurrentFormat }) ?? true else { return }
        isSchoolDirectoryLoading = directorySchools.isEmpty
        defer { isSchoolDirectoryLoading = false }
        if let schools = try? await friends.schoolDirectoryProvider.refreshDirectory() {
            directorySchools = schools
            preselectOwnSchool()
        }
    }

    func updateSchoolSearch(_ text: String) {
        schoolSearchText = text
        isSchoolSearchActive = true
        schoolURL = ""
        schoolName = nil
        resetClasses()
    }

    func selectSchool(_ school: SchoolDirectorySchool) {
        schoolSearchText = school.trimmedName
        schoolURL = school.trimmedSchoolURL
        schoolName = school.trimmedName
        isSchoolSearchActive = false
        resetClasses()
    }

    func useTypedSchool() {
        guard let address = typedSchoolAddress else { return }
        schoolURL = address
        schoolName = nil
        isSchoolSearchActive = false
        resetClasses()
    }

    private func preselectOwnSchool() {
        guard schoolURL.isEmpty, schoolSearchText.isEmpty, let own = friends.ownSchoolURL() else { return }
        let ownHost = own.host?.lowercased()
        if let match = directorySchools.first(where: { URL(string: $0.trimmedSchoolURL)?.host?.lowercased() == ownHost }) {
            selectSchool(match)
        } else {
            schoolURL = SchoolURLNormalizer.displayString(from: own)
            schoolSearchText = schoolURL
        }
    }

    // MARK: - Bakaláři login

    func connectBakalari() async -> Friend? {
        let friend = await run {
            try await self.friends.repository.connectBakalari(
                name: self.trimmedName, schoolURL: self.schoolURL, schoolName: self.schoolName,
                username: self.username, password: self.password
            )
        }
        // iOS offers to save a password when a filled secure field leaves the
        // screen; an empty one gives it nothing to save.
        if friend != nil { password = "" }
        return friend
    }

    // MARK: - Public timetable

    func loadClasses() async {
        guard hasSchool else { return }
        resetClasses()
        _ = await run {
            let (url, classes) = try await self.friends.repository.publicClasses(schoolURL: self.schoolURL)
            self.publicSchoolURL = url
            self.classes = classes
        }
    }

    /// Picks the class; a class with groups asks which ones the friend is in.
    func selectClass(_ schoolClass: PublicTimetableClass) async -> Friend? {
        guard let publicSchoolURL else { return nil }
        selectedClass = schoolClass
        let groups = await run {
            try await self.friends.repository.publicGroups(schoolURL: publicSchoolURL, classID: schoolClass.id)
        }
        guard let groups else { return nil }
        if groups.isEmpty { return finishPublic() }
        self.groups = groups
        selectedGroups = Set(groups)
        step = .groups
        return nil
    }

    func finishPublic() -> Friend? {
        guard let publicSchoolURL, let selectedClass else { return nil }
        return friends.repository.makePublicFriend(
            name: trimmedName, schoolURL: publicSchoolURL, schoolName: schoolName, schoolClass: selectedClass,
            groups: groups.isEmpty || selectedGroups.count == groups.count ? nil : groups.filter(selectedGroups.contains)
        )
    }

    private func resetClasses() {
        classes = []
        publicSchoolURL = nil
        selectedClass = nil
        groups = []
        selectedGroups = []
    }

    // MARK: - PDF or photo

    func readDocument(_ data: Data, fileName: String?) async {
        self.fileName = fileName
        let pages = await run { try await TimetableDocumentReader.read(data: data) }
        guard let pages else { return }
        self.pages = pages
        selectPage(parsedPages.first?.id)
        step = .review
    }

    func selectPage(_ id: Int?) {
        selectedPageID = id
        draft = pages.first { $0.id == id }?.draft
        excludedGroups = []
    }

    /// For a timetable Gradey couldn't read: type it in.
    func startBlank() {
        pages = []
        selectedPageID = nil
        fileName = nil
        draft = .blank
        excludedGroups = []
        errorMessage = nil
        step = .review
    }

    func finishImport() -> Friend? {
        guard let draft else { return nil }
        do {
            return try friends.repository.makeImportedFriend(name: trimmedName, draft: draft, excludingGroups: excludedGroups, fileName: fileName)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: - Private

    private func run<Value>(_ operation: @escaping () async throws -> Value) async -> Value? {
        guard !isWorking else { return nil }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            return try await operation()
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
