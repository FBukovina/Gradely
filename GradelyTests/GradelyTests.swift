import Foundation
import Testing
@testable import Gradely

@MainActor
struct GradelyTests {
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

    @Test func decodesSchoolNameFallbacks() throws {
        let json = """
        {
          "UserUID": "student-1",
          "FullName": "Student One",
          "SchoolName": "Fallback Gymnázium",
          "UserType": "student",
          "UserTypeText": "Student"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let user = try JSONDecoder().decode(UserResponse.self, from: data)

        #expect(user.schoolName == "Fallback Gymnázium")
    }

    @Test func skipsPlaceholderSchoolNameWhenDecodingUser() throws {
        let json = """
        {
          "UserUID": "student-1",
          "FullName": "Student One",
          "SchoolOrganizationName": "název školy",
          "SchoolName": "Real Gymnázium",
          "UserType": "student",
          "UserTypeText": "Student"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let user = try JSONDecoder().decode(UserResponse.self, from: data)

        #expect(user.schoolName == "Real Gymnázium")
    }

    @Test func dashboardUsesDirectorySchoolNameWhenUserPayloadHasPlaceholder() async throws {
        let cachedDirectory = CachedSchoolDirectory(
            schools: [
                SchoolDirectorySchool(
                    id: "demo",
                    name: "Demo Gymnazium",
                    town: "Praha",
                    schoolURL: "https://demo.bakalari.cz"
                )
            ],
            cachedAt: Date()
        )
        let repository = BakalariRepository(
            client: MockBakalariClient(
                userResult: UserResponse(
                    userUID: "student-1",
                    fullName: "Student One",
                    userClass: nil,
                    schoolName: "nazev skoly",
                    userType: "student",
                    userTypeText: "Student",
                    studyYear: nil
                )
            ),
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache(),
            schoolDirectoryProvider: MockSchoolDirectoryProvider(cachedDirectory: cachedDirectory)
        )

        let dashboard = try await repository.loadDashboard()

        #expect(dashboard.user?.schoolName == "Demo Gymnazium")
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

    @Test func explicitWeightsRemainAuthoritativeWhenResolving() {
        let mark = testMark(markText: "2", typeNote: "Písemná práce", weight: 4, id: "explicit")
        let subject = testSubject(marks: [mark])

        let resolved = GradeMath.resolvedWeight(for: mark, in: subject)

        #expect(resolved == ResolvedMarkWeight(value: 4, source: .explicit))
    }

    @Test func hiddenWeightReusesConsistentExplicitSameLabel() {
        let visible = testMark(markText: "1", typeNote: "Pís. práce - malá", weight: 3, id: "visible")
        let hidden = testMark(markText: "5", typeNote: "Pís. práce - malá", weight: nil, id: "hidden")
        let subject = testSubject(marks: [visible, hidden])

        let resolved = GradeMath.resolvedWeight(for: hidden, in: subject)

        #expect(resolved == ResolvedMarkWeight(value: 3, source: .inferred))
    }

    @Test func hiddenWeightCanBeInferredFromOfficialAverageWhenUnique() {
        let visible = testMark(markText: "1", typeNote: "Ústní", weight: 1, id: "visible")
        let hidden = testMark(markText: "5", typeNote: "Písemná práce - velká", weight: nil, id: "hidden")
        let subject = testSubject(marks: [visible, hidden], averageText: "3,67")

        let resolved = GradeMath.resolvedWeight(for: hidden, in: subject)

        #expect(resolved == ResolvedMarkWeight(value: 2, source: .inferred))
    }

    @Test func ambiguousHiddenWeightFallsBackToOne() {
        let visible = testMark(markText: "2", typeNote: "Ústní", weight: 1, id: "visible")
        let hidden = testMark(markText: "2", typeNote: "Neznámý typ", weight: nil, id: "hidden")
        let subject = testSubject(marks: [visible, hidden], averageText: "2,00")

        let resolved = GradeMath.resolvedWeight(for: hidden, in: subject)

        #expect(resolved == ResolvedMarkWeight(value: 1, source: .fallback))
    }

    @Test func pointOnlyMarksAreIgnoredByWeightResolutionAverages() {
        let visible = testMark(markText: "1", typeNote: "Ústní", weight: 1, id: "visible")
        let points = testMark(
            markText: "5",
            type: "points",
            typeNote: "Body",
            weight: nil,
            isPoints: true,
            id: "points",
            maxPoints: 10
        )

        let average = GradeMath.weightedAverage(for: [visible, points])
        let resolvedPoints = GradeMath.resolvedWeights(for: [visible, points])["points"]

        #expect(average == 1)
        #expect(resolvedPoints == nil)
    }

    @Test func repositoryParsesWhatIfPredictionAverage() async throws {
        let predictedSubject = testSubject(marks: PreviewData.mathMarks, averageText: "2,59")
        let repository = BakalariRepository(
            client: MockBakalariClient(predictionResult: predictedSubject),
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache()
        )

        let average = try await repository.predictSubjectAverage(
            subject: PreviewData.subjects[0],
            markText: "3",
            weight: 2
        )

        #expect(abs((average ?? 0) - 2.59) < 0.001)
    }

    @Test func subjectDetailViewModelUsesExactPredictionWhenAvailable() async throws {
        let predictedSubject = testSubject(marks: PreviewData.mathMarks, averageText: "1,23")
        let repository = BakalariRepository(
            client: MockBakalariClient(predictionResult: predictedSubject),
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache()
        )
        let viewModel = SubjectDetailViewModel(
            subject: PreviewData.subjects[0],
            absence: nil,
            repository: repository
        )

        viewModel.updateTheoreticalMark("3")
        #expect(viewModel.theoreticalAverage != nil)

        try await waitForPrediction(viewModel, expectedAverage: 1.23)
    }

    @Test func subjectDetailViewModelKeepsLocalPredictionWhenExactPredictionFails() async throws {
        let repository = BakalariRepository(
            client: MockBakalariClient(predictionError: BakalariAPIError.httpStatus(403, nil)),
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache()
        )
        let viewModel = SubjectDetailViewModel(
            subject: PreviewData.subjects[0],
            absence: nil,
            repository: repository
        )

        viewModel.updateTheoreticalMark("3")
        viewModel.incrementWeight()

        try await waitForPredictionToFinish(viewModel)

        #expect(abs((viewModel.theoreticalAverage ?? 0) - 2.1833) < 0.001)
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
        let viewModel = LoginViewModel(
            repository: repository,
            schoolDirectoryProvider: MockSchoolDirectoryProvider()
        )
        viewModel.schoolURL = "demo.bakalari.cz"
        viewModel.username = "student"
        viewModel.password = "secret"

        let didLogin = await viewModel.login()

        #expect(didLogin)
        #expect(store.session?.baseURL.absoluteString == "https://demo.bakalari.cz/")
        #expect(viewModel.password.isEmpty)
    }

    @Test func demoAccountLoadsMockDashboardData() async throws {
        let store = InMemorySessionStore()
        let repository = BakalariRepository(
            client: DemoAwareBakalariClient(liveClient: MockBakalariClient(marksError: BakalariAPIError.httpStatus(418, nil))),
            sessionStore: store,
            marksCache: InMemoryMarksCache()
        )

        let session = try await repository.login(
            schoolURL: DemoAccount.schoolURL,
            username: DemoAccount.username,
            password: DemoAccount.password
        )
        let dashboard = try await repository.loadDashboard()

        #expect(session.accessToken == DemoAccount.accessToken)
        #expect(store.session?.baseURL.absoluteString == "https://demo.gradely.app/")
        #expect(dashboard.marksResponse.subjects == PreviewData.subjects)
        #expect(dashboard.user?.fullName == PreviewData.userResponse.fullName)
    }

    @Test func demoAccountRejectsWrongCredentials() async {
        let repository = BakalariRepository(
            client: DemoAwareBakalariClient(liveClient: MockBakalariClient()),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache()
        )

        do {
            _ = try await repository.login(
                schoolURL: DemoAccount.schoolURL,
                username: DemoAccount.username,
                password: "wrong-password"
            )
            #expect(Bool(false), "Expected demo account login to reject wrong credentials.")
        } catch {
            #expect((error as? DemoAccountError) == .invalidCredentials)
        }
    }

    @Test func supportTipViewModelLoadsTips() async {
        let service = MockSupportTipService()
        let viewModel = SupportTipViewModel(supportTipProvider: service)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.tips == MockSupportTipService.previewTips)
        #expect(viewModel.purchaseErrorMessage == nil)
    }

    @Test func supportTipViewModelShowsUnavailableWhenNotConfigured() async {
        let service = MockSupportTipService(
            loadResult: Result<[SupportTipOption], Error>.failure(SupportTipServiceError.notConfigured)
        )
        let viewModel = SupportTipViewModel(supportTipProvider: service)

        await viewModel.load()

        guard case .failed(let message) = viewModel.loadState else {
            Issue.record("Expected support loading to fail.")
            return
        }
        #expect(message == String(localized: "support.tips.error.notConfigured"))
        #expect(viewModel.tips.isEmpty)
    }

    @Test func supportTipViewModelShowsEmptyOfferingState() async {
        let service = MockSupportTipService(tips: [])
        let viewModel = SupportTipViewModel(supportTipProvider: service)

        await viewModel.load()

        #expect(viewModel.loadState == .empty)
        #expect(viewModel.tips.isEmpty)
    }

    @Test func supportTipViewModelShowsRevenueCatLoadError() async {
        let error = NSError(
            domain: "RevenueCat",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to fetch offerings."]
        )
        let service = MockSupportTipService(
            loadResult: Result<[SupportTipOption], Error>.failure(error)
        )
        let viewModel = SupportTipViewModel(supportTipProvider: service)

        await viewModel.load()

        #expect(viewModel.loadState == .failed("Unable to fetch offerings."))
    }

    @Test func supportTipViewModelCompletesSuccessfulPurchase() async {
        let service = MockSupportTipService()
        let viewModel = SupportTipViewModel(supportTipProvider: service)
        let tip = MockSupportTipService.previewTips[0]

        await viewModel.purchase(tip)

        #expect(viewModel.didCompletePurchase)
        #expect(viewModel.purchaseErrorMessage == nil)
        #expect(service.purchasedTipIDs == [tip.id])
    }

    @Test func supportTipViewModelTreatsPurchaseCancellationSilently() async {
        let service = MockSupportTipService(purchaseResult: .success(.cancelled))
        let viewModel = SupportTipViewModel(supportTipProvider: service)

        await viewModel.purchase(MockSupportTipService.previewTips[1])

        #expect(!viewModel.didCompletePurchase)
        #expect(viewModel.purchaseErrorMessage == nil)
    }

    @Test func supportTipViewModelShowsPurchaseFailure() async {
        let service = MockSupportTipService(
            purchaseResult: .failure(SupportTipServiceError.purchaseFailed("The purchase could not be completed."))
        )
        let viewModel = SupportTipViewModel(supportTipProvider: service)

        await viewModel.purchase(MockSupportTipService.previewTips[2])

        #expect(!viewModel.didCompletePurchase)
        #expect(viewModel.purchaseErrorMessage == "The purchase could not be completed.")
    }

    private func testMark(
        markText: String,
        caption: String? = nil,
        type: String = "written",
        typeNote: String?,
        weight: Int?,
        isPoints: Bool = false,
        id: String,
        maxPoints: Int? = nil
    ) -> Mark {
        Mark(
            markDate: "2026-06-01T08:00:00+02:00",
            caption: caption,
            markText: markText,
            type: type,
            typeNote: typeNote,
            weight: weight,
            subjectID: "test",
            isPoints: isPoints,
            id: id,
            maxPoints: maxPoints
        )
    }

    private func testSubject(marks: [Mark], averageText: String? = nil) -> Subject {
        Subject(
            marks: marks,
            subjectInfo: SubjectInfo(id: "test", abbrev: "T", name: "Test"),
            averageText: averageText,
            markPredictionEnabled: true
        )
    }

    private func validSession() -> StoredSession {
        StoredSession(
            accessToken: "mock-access",
            refreshToken: "mock-refresh",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            baseURL: URL(string: "https://demo.bakalari.cz/")!
        )
    }

    private func waitForPrediction(_ viewModel: SubjectDetailViewModel, expectedAverage: Double) async throws {
        for _ in 0..<20 {
            if let average = viewModel.theoreticalAverage, abs(average - expectedAverage) < 0.001 {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(Bool(false), "Timed out waiting for exact prediction.")
    }

    private func waitForPredictionToFinish(_ viewModel: SubjectDetailViewModel) async throws {
        for _ in 0..<20 {
            if !viewModel.isPredictingExactAverage {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(Bool(false), "Timed out waiting for prediction to finish.")
    }
}
