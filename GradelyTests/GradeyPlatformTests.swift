import Foundation
import Testing
@testable import Gradely

struct GradeyPlatformTests {
    @Test func markFingerprintUsesProviderIDWhenAvailable() {
        let subject = testSubject(id: "subj-tv", abbrev: "TVY")
        let mark = testMark(id: "mark-123", subjectID: "subj-tv", markText: "1")

        let fingerprint = MarkFingerprintBuilder.fingerprint(
            for: mark,
            subject: subject,
            provider: .bakalari,
            linkedAccountID: "account-1"
        )

        #expect(fingerprint.source == .providerID)
        #expect(fingerprint.providerMarkID == "mark-123")
        #expect(fingerprint.value == "bakalari:account-1:subj-tv:provider:mark-123")
    }

    @Test func markFingerprintFallsBackToStableContentHashWithoutProviderID() {
        let subject = testSubject(id: "subj-tv", abbrev: "TVY")
        let first = testMark(id: "", subjectID: "subj-tv", markText: "1")
        let second = testMark(id: "", subjectID: "subj-tv", markText: "1")

        let firstFingerprint = MarkFingerprintBuilder.fingerprint(
            for: first,
            subject: subject,
            provider: .bakalari,
            linkedAccountID: "account-1"
        )
        let secondFingerprint = MarkFingerprintBuilder.fingerprint(
            for: second,
            subject: subject,
            provider: .bakalari,
            linkedAccountID: "account-1"
        )

        #expect(firstFingerprint.source == .contentHash)
        #expect(firstFingerprint.providerMarkID == nil)
        #expect(firstFingerprint.value == secondFingerprint.value)
    }

    @Test func schoolProviderSecretPayloadNeverIncludesPasswords() throws {
        let eduPageData = EduPageSessionData(
            sessionID: "session",
            username: "student",
            password: "super-secret-password",
            gsecHash: "hash",
            userID: "user",
            schoolName: "School",
            activeStudent: nil,
            linkedStudents: [],
            subjects: []
        )
        let session = StoredSession(
            accessToken: "session",
            refreshToken: "",
            tokenType: "Cookie",
            expiresAt: .distantFuture,
            baseURL: URL(string: "https://school.edupage.org")!,
            provider: .eduPage,
            eduPage: eduPageData
        )

        let payload = ProviderSecretSanitizer.schoolPayload(from: session)
        let data = try JSONEncoder.sessionEncoder.encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        #expect(!json.contains("super-secret-password"))
        #expect(json.contains("session"))
        #expect(json.contains("hash"))
    }

    @Test func newMarkNotificationUsesLockedDefaultCopy() {
        let event = NewMarkEvent(
            id: "event",
            linkedAccountID: "account",
            provider: .bakalari,
            subjectID: "subj-tv",
            subjectAbbrev: "TVY",
            subjectName: "Telesna vychova",
            markText: "1",
            fingerprint: MarkFingerprint(
                provider: .bakalari,
                linkedAccountID: "account",
                subjectID: "subj-tv",
                providerMarkID: "mark",
                value: "fingerprint",
                source: .providerID
            ),
            createdAt: Date(),
            deliveredAt: nil
        )

        #expect(NewMarkNotificationFormatter.title(for: event) == "New mark")
        #expect(NewMarkNotificationFormatter.body(for: event, preferences: .default) == "1 from TVY")
    }

    @MainActor
    @Test func debugBypassSkipsGradeyGateAndShowsSchoolLoginState() async {
        let gradeyAuthClient = MockGradeyAuthClient(session: nil)
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache()
        )
        let linkedAccountRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!),
            client: MockLinkedAccountClient(),
            authClient: gradeyAuthClient
        )
        let viewModel = AppViewModel(
            repository: repository,
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(),
            gradeyAuthClient: gradeyAuthClient,
            linkedAccountRepository: linkedAccountRepository,
            requiresGradeyID: true
        )

        await viewModel.bootstrap()
        #expect(viewModel.usesGradeyIDGate)
        #expect(viewModel.phase == .signedOut)

        await viewModel.bypassGradeyIDForTesting()
        #expect(!viewModel.usesGradeyIDGate)
        #expect(viewModel.phase == .signedInNeedsSchool)
    }

    private func testSubject(id: String, abbrev: String) -> Subject {
        Subject(
            marks: [],
            subjectInfo: SubjectInfo(id: id, abbrev: abbrev, name: "Subject"),
            averageText: nil
        )
    }

    private func testMark(id: String, subjectID: String, markText: String) -> Mark {
        Mark(
            markDate: "2026-06-30T00:00:00+02:00",
            caption: "Test",
            markText: markText,
            type: "grade",
            weight: 1,
            subjectID: subjectID,
            id: id
        )
    }
}
