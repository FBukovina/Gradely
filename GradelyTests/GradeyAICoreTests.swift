import Foundation
import Testing
@testable import Gradely

struct GradeyAICoreTests {
    @Test func contextCapsRecentMarksPerSubjectAndGlobally() {
        let subjects = (0..<20).map { subjectIndex in
            Subject(
                marks: (0..<10).map { markIndex in
                    Mark(
                        markDate: String(format: "2026-06-%02dT08:00:00Z", max(1, 28 - markIndex)),
                        caption: "Assessment \(markIndex)",
                        markText: "\((markIndex % 5) + 1)",
                        type: "grade",
                        weight: 1,
                        subjectID: "subject-\(subjectIndex)",
                        id: "mark-\(subjectIndex)-\(markIndex)"
                    )
                },
                subjectInfo: SubjectInfo(
                    id: "subject-\(subjectIndex)",
                    abbrev: "S\(subjectIndex)",
                    name: "Subject \(subjectIndex)"
                ),
                averageText: "2.0"
            )
        }

        let context = GradeyAIContextBuilder.makeSubjects(from: subjects)

        #expect(context.reduce(0) { $0 + $1.recentMarks.count } == 80)
        #expect(context.allSatisfy { $0.recentMarks.count <= 5 })
        #expect(context.allSatisfy { $0.totalMarkCount == 10 })
    }

    @Test func contextPayloadContainsOnlyMinimizedAcademicFields() throws {
        let subject = Subject(
            marks: [
                Mark(
                    markDate: "2026-07-01T08:00:00Z",
                    caption: "Quiz",
                    markText: "1",
                    teacherID: "teacher-id",
                    type: "grade",
                    typeNote: "must-not-leak",
                    weight: 2,
                    subjectID: "math",
                    id: "mark"
                )
            ],
            subjectInfo: SubjectInfo(id: "math", abbrev: "M", name: "Math"),
            averageText: "1.5",
            subjectNote: "private-note"
        )

        let snapshot = GradeyAIContextSnapshot(
            schoolScope: "school_test_scope",
            generatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            unavailableSections: [],
            subjects: GradeyAIContextBuilder.makeSubjects(from: [subject]),
            trends: [],
            timetable: []
        )
        let json = String(data: try JSONEncoder.sessionEncoder.encode(snapshot), encoding: .utf8) ?? ""

        #expect(!json.contains("teacher-id"))
        #expect(!json.contains("must-not-leak"))
        #expect(!json.contains("private-note"))
        #expect(!json.localizedCaseInsensitiveContains("password"))
        #expect(!json.localizedCaseInsensitiveContains("access_token"))
        #expect(!json.localizedCaseInsensitiveContains("refresh_token"))
    }

    @Test func schoolScopeChangesWhenAParentSwitchesEduPageStudents() {
        let hasher = GradeyAISchoolScopeHasher(salt: Data(repeating: 7, count: 32))

        func session(studentID: String) -> StoredSession {
            let student = SchoolStudentProfile(
                id: studentID,
                fullName: "Student \(studentID)",
                classID: nil,
                className: nil
            )
            return StoredSession(
                accessToken: "session",
                refreshToken: "",
                tokenType: "Cookie",
                expiresAt: .distantFuture,
                baseURL: URL(string: "https://school.edupage.org")!,
                provider: .eduPage,
                eduPage: EduPageSessionData(
                    sessionID: "session",
                    username: "parent",
                    password: "secret",
                    gsecHash: "hash",
                    userID: "parent-id",
                    schoolName: "School",
                    activeStudent: student,
                    linkedStudents: [student],
                    subjects: []
                ),
                linkedAccountID: "shared-linked-account"
            )
        }

        #expect(hasher.schoolScope(for: session(studentID: "child-a"))
            != hasher.schoolScope(for: session(studentID: "child-b")))
    }

    @Test func firebaseContextIsAlwaysMinimizedBelowServerLimit() throws {
        let long = String(repeating: "x", count: 300)
        let lessons = (0..<120).map { index in
            GradeyAILessonContext(
                id: "lesson-\(index)-\(long)",
                date: "2026-07-11",
                subject: long,
                subjectAbbreviation: String(long.prefix(32)),
                beginsAt: "08:00",
                endsAt: "08:45",
                teacher: long,
                room: long,
                groups: Array(repeating: String(long.prefix(64)), count: 12),
                changeKind: .substitution,
                changeDescription: long
            )
        }
        let snapshot = GradeyAIContextSnapshot(
            schoolScope: "school_test_scope",
            generatedAt: Date(timeIntervalSince1970: 0),
            isStale: false,
            unavailableSections: [],
            subjects: [],
            trends: [],
            timetable: lessons
        )

        let data = try FirebaseGradeyAIWireContract.encodeMinimizedContext(snapshot)

        #expect(data.count <= 96 * 1_024)
        #expect(data.count > 0)
    }

    @Test func assistantMarkdownSplitsHeadingsListsAndInlineEmphasis() {
        let markdown = """
        ## Marks summary
        Assuming the usual Czech scale where 1 is **best** and 5 is **weakest**:

        ## Strongest subjects
        - **English (ANJ):** 1.13
        - **Programming/software (PVY):** 1.25

        ## Middle range
        1. Natural sciences (ZPV): 1.88
        """

        #expect(GradeyAIMarkdown.blocks(from: markdown) == [
            .heading("Marks summary", level: 2),
            .paragraph("Assuming the usual Czech scale where 1 is **best** and 5 is **weakest**:"),
            .heading("Strongest subjects", level: 2),
            .list([
                "**English (ANJ):** 1.13",
                "**Programming/software (PVY):** 1.25",
            ]),
            .heading("Middle range", level: 2),
            .list(["Natural sciences (ZPV): 1.88"]),
        ])

        let attributed = GradeyAIMarkdown.inlineAttributed("1 is **best** and 5 is **weakest**")
        #expect(String(attributed.characters) == "1 is best and 5 is weakest")
        #expect(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test func firebaseStreamEventsDecodeStartedCompletedAndRefundedFailure() throws {
        let status = #"{"enabled":true,"consentRequired":false,"termsVersion":"beta","tier":"guest","dailyLimit":5,"dailyUsed":1,"remaining":4,"resetAt":1783814400000}"#
        let start = try FirebaseGradeyAIWireContract.decodeStreamEvent(
            Data("{\"type\":\"started\",\"assistantMessageID\":\"assistant\",\"status\":\(status)}".utf8),
            fallbackConversationID: "chat"
        )
        let done = try FirebaseGradeyAIWireContract.decodeStreamEvent(
            Data("{\"type\":\"completed\",\"message\":{\"id\":\"assistant\",\"chatID\":\"chat\",\"role\":\"assistant\",\"content\":\"Saved answer\",\"status\":\"complete\",\"createdAt\":1783810800000},\"usage\":{\"inputTokens\":120,\"outputTokens\":42},\"status\":\(status)}".utf8),
            fallbackConversationID: "chat"
        )
        let failed = try FirebaseGradeyAIWireContract.decodeStreamEvent(
            Data("{\"type\":\"failed\",\"message\":\"Try again\",\"code\":\"azure_timeout\",\"retryable\":true,\"status\":\(status)}".utf8),
            fallbackConversationID: "chat"
        )

        #expect(start == .start(assistantMessageID: "assistant", remaining: 4))
        #expect(done == .done(
            finishReason: "stop",
            remaining: 4,
            inputTokens: 120,
            outputTokens: 42,
            persistedMessage: GradeyAIMessage(
                id: "assistant",
                conversationID: "chat",
                clientMessageID: nil,
                role: .assistant,
                content: "Saved answer",
                status: .complete,
                createdAt: Date(timeIntervalSince1970: 1_783_810_800),
                contextGeneratedAt: nil
            )
        ))
        #expect(failed == .error(
            code: "azure_timeout",
            message: "Try again",
            retryable: true,
            remaining: 4
        ))
    }

    @MainActor
    @Test func bootstrapLoadsHistoryWhenGenerationIsDisabled() async {
        let snapshot = disabledContextSnapshot()
        let conversation = disabledConversation()
        let savedMessage = GradeyAIMessage(
            id: "saved-message",
            conversationID: conversation.id,
            clientMessageID: nil,
            role: .assistant,
            content: "A saved answer remains available.",
            status: .complete,
            createdAt: Date(timeIntervalSince1970: 1_783_810_800),
            contextGeneratedAt: snapshot.generatedAt
        )
        let client = MockGradeyAIClient(
            status: disabledStatus(consentRequired: false),
            conversations: [conversation],
            messagesByConversationID: [conversation.id: [savedMessage]]
        )
        let viewModel = GradeyAIViewModel(
            client: client,
            contextBuilder: MockGradeyAIContextBuilder(snapshot: snapshot)
        )

        await viewModel.bootstrap()

        #expect(viewModel.status?.enabled == false)
        #expect(viewModel.conversations.map(\.id) == [conversation.id])
        #expect(viewModel.contextSnapshot?.schoolScope == snapshot.schoolScope)
        #expect(viewModel.currentConversation == nil)
        viewModel.draft = "A message that cannot be sent yet"
        #expect(viewModel.canSend == false)

        await viewModel.open(conversation)
        #expect(viewModel.currentConversation?.id == conversation.id)
        #expect(viewModel.messages == [savedMessage])

        await viewModel.send("Do not send while disabled")
        #expect(viewModel.messages == [savedMessage])
    }

    @MainActor
    @Test func acceptingConsentLoadsHistoryWhenGenerationIsDisabled() async {
        let snapshot = disabledContextSnapshot()
        let conversation = disabledConversation()
        let client = MockGradeyAIClient(
            status: disabledStatus(consentRequired: true),
            conversations: [conversation]
        )
        let viewModel = GradeyAIViewModel(
            client: client,
            contextBuilder: MockGradeyAIContextBuilder(snapshot: snapshot)
        )

        await viewModel.bootstrap()
        #expect(viewModel.conversations.isEmpty)

        await viewModel.acceptConsent()

        #expect(viewModel.status?.enabled == false)
        #expect(viewModel.status?.consentRequired == false)
        #expect(viewModel.conversations.map(\.id) == [conversation.id])
        #expect(viewModel.canSend == false)
    }

    @MainActor
    @Test func viewModelStreamsReplyAndUpdatesQuota() async {
        let snapshot = GradeyAIContextSnapshot(
            schoolScope: "school_test_scope",
            generatedAt: Date(),
            isStale: false,
            unavailableSections: [],
            subjects: [],
            trends: [],
            timetable: []
        )
        let client = MockGradeyAIClient(responseText: "A useful answer")
        let contextBuilder = MockGradeyAIContextBuilder(snapshot: snapshot)
        let viewModel = GradeyAIViewModel(client: client, contextBuilder: contextBuilder)

        await viewModel.bootstrap()
        viewModel.draft = "Help me study"
        await viewModel.send()

        #expect(viewModel.messages.map(\.role) == [.user, .assistant])
        #expect(viewModel.messages.last?.content == "A useful answer")
        #expect(viewModel.messages.last?.status == .complete)
        #expect(viewModel.status?.remaining == 4)
        #expect(viewModel.isStreaming == false)
    }

    @MainActor
    @Test func newChatOpensALocalDraftWithoutCallingTheServer() async {
        let snapshot = GradeyAIContextSnapshot(
            schoolScope: "school_test_scope",
            generatedAt: Date(),
            isStale: false,
            unavailableSections: [],
            subjects: [],
            trends: [],
            timetable: []
        )
        let client = MockGradeyAIClient()
        let viewModel = GradeyAIViewModel(
            client: client,
            contextBuilder: MockGradeyAIContextBuilder(snapshot: snapshot)
        )

        await viewModel.bootstrap()
        viewModel.beginDraftChat()

        #expect(viewModel.isDraftChat)
        #expect(viewModel.currentConversation != nil)
        #expect(viewModel.conversations.isEmpty)
        #expect(client.conversations.isEmpty)
        #expect(viewModel.messages.isEmpty)

        viewModel.closeConversation()

        #expect(viewModel.currentConversation == nil)
        #expect(viewModel.isDraftChat == false)
        #expect(viewModel.conversations.isEmpty)
        #expect(client.conversations.isEmpty)
    }

    @MainActor
    @Test func sendingFromADraftCreatesTheRemoteChatAndKeepsTheUserMessage() async {
        let snapshot = GradeyAIContextSnapshot(
            schoolScope: "school_test_scope",
            generatedAt: Date(),
            isStale: false,
            unavailableSections: [],
            subjects: [],
            trends: [],
            timetable: []
        )
        let client = MockGradeyAIClient(responseText: "Start with mathematics.")
        let viewModel = GradeyAIViewModel(
            client: client,
            contextBuilder: MockGradeyAIContextBuilder(snapshot: snapshot)
        )

        await viewModel.bootstrap()
        viewModel.beginDraftChat()
        let draftID = viewModel.currentConversation?.id
        await viewModel.send("What should I study first?")

        #expect(viewModel.isDraftChat == false)
        #expect(viewModel.currentConversation?.id != draftID)
        #expect(viewModel.conversations.map(\.id) == [viewModel.currentConversation?.id].compactMap { $0 })
        #expect(viewModel.messages.map(\.role) == [.user, .assistant])
        #expect(viewModel.messages.first?.content == "What should I study first?")
        #expect(viewModel.messages.first?.conversationID == viewModel.currentConversation?.id)
    }

    @MainActor
    @Test func sendCreatesAChatWithoutClearingTheOutgoingMessage() async {
        let snapshot = GradeyAIContextSnapshot(
            schoolScope: "school_test_scope",
            generatedAt: Date(),
            isStale: false,
            unavailableSections: [],
            subjects: [],
            trends: [],
            timetable: []
        )
        let client = MockGradeyAIClient(responseText: "Focus on the next test.")
        let viewModel = GradeyAIViewModel(
            client: client,
            contextBuilder: MockGradeyAIContextBuilder(snapshot: snapshot)
        )

        await viewModel.bootstrap()
        #expect(viewModel.currentConversation == nil)
        await viewModel.send("What should I study first?")

        #expect(viewModel.currentConversation != nil)
        #expect(viewModel.messages.map(\.role) == [.user, .assistant])
        #expect(viewModel.messages.first?.content == "What should I study first?")
        #expect(viewModel.messages.first?.conversationID == viewModel.currentConversation?.id)
    }

    private func disabledContextSnapshot() -> GradeyAIContextSnapshot {
        GradeyAIContextSnapshot(
            schoolScope: "school_test_scope",
            generatedAt: Date(timeIntervalSince1970: 1_783_810_000),
            isStale: false,
            unavailableSections: [],
            subjects: [],
            trends: [],
            timetable: []
        )
    }

    private func disabledConversation() -> GradeyAIConversation {
        let timestamp = Date(timeIntervalSince1970: 1_783_810_400)
        return GradeyAIConversation(
            id: "disabled-chat",
            schoolScope: "school_test_scope",
            title: "Saved study chat",
            createdAt: timestamp,
            updatedAt: timestamp,
            lastMessageAt: timestamp
        )
    }

    private func disabledStatus(consentRequired: Bool) -> GradeyAIStatus {
        GradeyAIStatus(
            enabled: false,
            consentRequired: consentRequired,
            termsVersion: "2026-07-10.beta1",
            dailyLimit: 5,
            dailyUsed: 0,
            remaining: 5,
            resetAt: Date(timeIntervalSince1970: 1_783_814_400)
        )
    }
}
