import Foundation
import Testing
@testable import Gradely

struct EduPageTests {
    @Test func eduPageSignInIsHiddenUnlessUITestOverride() {
        #expect(SchoolProvider.bakalari.isOfferedForNewSignIn(arguments: []))
        #expect(!SchoolProvider.eduPage.isOfferedForNewSignIn(arguments: []))
        #expect(SchoolProvider.offeredForNewSignIn(arguments: []) == [.bakalari])
        #expect(SchoolProvider.eduPage.isOfferedForNewSignIn(arguments: ["-uiTestingShowEduPage"]))
        #expect(SchoolProvider.eduPage.isOfferedForNewSignIn(arguments: ["-uiTestingEduPageTwoFactor"]))
    }

    @Test func normalizesEduPageSubdomainAndRejectsForeignHosts() throws {
        #expect(try EduPageURLNormalizer.normalizedBaseURL(from: "my-school").absoluteString == "https://my-school.edupage.org")
        #expect(try EduPageURLNormalizer.normalizedBaseURL(from: "https://my-school.edupage.org/login").absoluteString == "https://my-school.edupage.org")
        #expect(throws: SchoolAuthenticationError.invalidSchoolURL) {
            try EduPageURLNormalizer.normalizedBaseURL(from: "https://example.com")
        }
    }

    @Test func legacyStoredSessionDecodesAsBakalari() throws {
        let legacy = """
        {
          "accessToken": "access",
          "refreshToken": "refresh",
          "tokenType": "Bearer",
          "expiresAt": "2030-01-01T00:00:00Z",
          "baseURL": "https://school.example"
        }
        """
        let session = try JSONDecoder.sessionDecoder.decode(StoredSession.self, from: Data(legacy.utf8))
        #expect(session.provider == .bakalari)
        #expect(session.eduPage == nil)
    }

    @Test func decimalEduPageWeightsRemainExact() {
        let light = Mark(
            markDate: "2026-01-01",
            markText: "1",
            type: "grade",
            weight: 0.25,
            subjectID: "math",
            id: "light"
        )
        let regular = Mark(
            markDate: "2026-01-02",
            markText: "3",
            type: "grade",
            weight: 1,
            subjectID: "math",
            id: "regular"
        )
        #expect(abs((GradeMath.weightedAverage(for: [light, regular]) ?? 0) - 2.6) < 0.0001)
        #expect(GradeMath.formattedWeight(0.25) == "0.25")
    }

    @Test func repositoryPersistsEduPageCredentialsAndProvider() async throws {
        let sessionStore = InMemorySessionStore()
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            eduPageClient: MockEduPageClient(),
            sessionStore: sessionStore,
            marksCache: InMemoryMarksCache()
        )

        let step = try await repository.beginLogin(
            provider: .eduPage,
            schoolURL: "demo",
            username: "student",
            password: "secret"
        )
        guard case .signedIn(let session) = step else {
            Issue.record("Expected a completed EduPage login")
            return
        }

        #expect(session.provider == .eduPage)
        #expect(session.eduPage?.password == "secret")
        #expect(try sessionStore.loadSession()?.provider == .eduPage)
    }
}

private final class MockEduPageClient: EduPageClient, @unchecked Sendable {
    private let data = EduPageSessionData(
        sessionID: "php-session",
        username: "student",
        password: "secret",
        gsecHash: "gsec",
        userID: "Student1",
        schoolName: "EduPage School",
        activeStudent: SchoolStudentProfile(id: "Student1", fullName: "Test Student", classID: "1", className: "1.A"),
        linkedStudents: [],
        subjects: []
    )

    func beginLogin(baseURL: URL, username: String, password: String) async throws -> EduPageLoginResult {
        .authenticated(data)
    }

    func completeTwoFactor(code: String) async throws -> EduPageLoginResult { .authenticated(data) }
    func completeApprovedTwoFactor() async throws -> EduPageLoginResult { .authenticated(data) }
    func isTwoFactorConfirmed() async throws -> Bool { true }
    func resendTwoFactorNotification() async throws {}
    func selectStudent(_ studentID: String) async throws -> EduPageSessionData { data }
    func switchStudent(_ studentID: String, in session: EduPageSessionData, baseURL: URL) async throws -> EduPageSessionData { session }
    func restore(_ stored: EduPageSessionData, baseURL: URL) async throws -> EduPageSessionData { stored }
    func fetchMarks(baseURL: URL, session: EduPageSessionData) async throws -> MarksResponse { MarksResponse(subjects: []) }
    func fetchAbsences(baseURL: URL, session: EduPageSessionData) async throws -> AbsenceResponse {
        AbsenceResponse(percentageThreshold: nil, absences: [], absencesPerSubject: [])
    }
    func fetchUser(baseURL: URL, session: EduPageSessionData) async throws -> UserResponse {
        UserResponse(
            userUID: "Student1",
            fullName: "Test Student",
            userClass: nil,
            schoolName: "EduPage School",
            userType: "student",
            userTypeText: "Student",
            studyYear: 2026
        )
    }
    func fetchTimetable(baseURL: URL, session: EduPageSessionData, weekStart: Date) async throws -> TimetableResponse {
        TimetableResponse()
    }
}
