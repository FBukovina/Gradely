import Foundation
import Testing
@testable import BakalariMarks

@MainActor
struct BakalariMarksTests {
    @Test func decodesMarksResponseFixture() throws {
        let json = """
        {
          "Subjects": [
            {
              "Marks": [
                {
                  "MarkDate": "2026-05-31T09:30:00+02:00",
                  "Caption": "Písemná práce",
                  "Theme": "Lineární rovnice",
                  "MarkText": "1-",
                  "Type": "written",
                  "TypeNote": "Písemka",
                  "Weight": 3,
                  "SubjectId": "math",
                  "IsNew": true,
                  "IsPoints": false,
                  "Id": "math-1"
                }
              ],
              "Subject": { "Id": "math", "Abbrev": "M", "Name": "Matematika" },
              "AverageText": "1,78",
              "PointsOnly": false,
              "MarkPredictionEnabled": true
            }
          ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(MarksResponse.self, from: data)

        #expect(response.subjects.count == 1)
        #expect(response.subjects[0].trimmedName == "Matematika")
        #expect(response.subjects[0].marks[0].markText == "1-")
        #expect(response.subjects[0].marks[0].weight == 3)
    }

    @Test func normalizesAndRequiresHTTPSBaseURL() throws {
        let normalized = try SchoolURLNormalizer.normalizedBaseURL(from: "skola.example.cz")

        #expect(normalized.absoluteString == "https://skola.example.cz/")
        #expect(throws: SchoolURLNormalizer.NormalizationError.insecure) {
            try SchoolURLNormalizer.normalizedBaseURL(from: "http://skola.example.cz")
        }
    }

    @Test func preservesAndroidGradeMathMapping() {
        #expect(GradeMath.parseMarkValue("1+") == 1.3)
        #expect(GradeMath.parseMarkValue("1-") == 1.7)
        #expect(GradeMath.parseMarkValue("5+") == 5.3)
        #expect(GradeMath.parseMarkValue("5-") == 5.7)

        let average = GradeMath.weightedAverage(for: PreviewData.mathMarks)
        #expect(average != nil)
        #expect(abs((average ?? 0) - 1.775) < 0.001)

        let theoretical = GradeMath.theoreticalAverage(
            existingMarks: PreviewData.mathMarks,
            markValue: 3,
            weight: 2
        )
        #expect(abs(theoretical - 2.1833) < 0.001)
    }

    @Test func refreshesExpiredSession() async throws {
        let store = InMemorySessionStore(session: PreviewData.expiredSession)
        let refreshed = LoginResponse(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            tokenType: "Bearer",
            expiresIn: 3600,
            apiVersion: nil,
            appVersion: nil,
            userID: "mock-user"
        )
        let repository = BakalariRepository(
            client: MockBakalariClient(refreshedResult: refreshed),
            sessionStore: store,
            marksCache: InMemoryMarksCache()
        )

        let session = try await repository.validSession()

        #expect(session.accessToken == "new-access")
        #expect(store.session?.refreshToken == "new-refresh")
    }

    @Test func subjectsViewModelKeepsCachedMarksWhenRefreshFails() async {
        let cache = InMemoryMarksCache(
            cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date())
        )
        let repository = BakalariRepository(
            client: MockBakalariClient(marksError: BakalariAPIError.httpStatus(500, nil)),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: cache
        )
        let viewModel = SubjectsViewModel(repository: repository)

        await viewModel.loadIfNeeded()

        #expect(viewModel.subjects == PreviewData.subjects)
        #expect(viewModel.errorMessage == nil)

        try? cache.clear()
        #expect((try? cache.load()) == nil)
    }

    @Test func loginViewModelSavesSessionWithNormalizedURL() async {
        let store = InMemorySessionStore()
        let repository = BakalariRepository(
            client: MockBakalariClient(),
            sessionStore: store,
            marksCache: InMemoryMarksCache()
        )
        let viewModel = LoginViewModel(repository: repository)
        viewModel.schoolURL = "demo.bakalari.cz"
        viewModel.username = "student"
        viewModel.password = "secret"

        let didLogin = await viewModel.login()

        #expect(didLogin)
        #expect(store.session?.baseURL.absoluteString == "https://demo.bakalari.cz/")
        #expect(viewModel.password.isEmpty)
    }
}
