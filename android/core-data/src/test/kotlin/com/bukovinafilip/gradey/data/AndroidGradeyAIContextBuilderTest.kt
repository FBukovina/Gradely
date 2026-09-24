package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.AbsenceLessonCandidate
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolution
import com.bukovinafilip.gradey.domain.GradeyAIContextError
import com.bukovinafilip.gradey.domain.GradeyAIContextException
import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.domain.SchoolRepository
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeHistoryEvent
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import com.bukovinafilip.gradey.model.GradeHistoryEventType
import com.bukovinafilip.gradey.model.GradeyAIContextSection
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableWeek
import com.google.common.truth.Truth.assertThat
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Test

class AndroidGradeyAIContextBuilderTest {
    private val now = Instant.parse("2026-08-31T10:00:00Z").toEpochMilli()
    private val session = StoredSession(
        accessToken = "access-must-not-leak",
        refreshToken = "refresh-must-not-leak",
        tokenType = "Bearer",
        expiresAtEpochMillis = Long.MAX_VALUE,
        baseURL = "https://school.example.cz",
        bakalari = BakalariCredentials("student", "password-must-not-leak"),
        linkedAccountID = "account",
    )

    @Test
    fun `cached context is stale partial school scoped and contains only minimized school data`() = runTest {
        val school = FakeAISchoolRepository(session).apply {
            cachedDashboard = dashboard()
            cachedWeeks["2026-08-31"] = week("2026-08-31", "lesson-current")
        }
        val builder = builder(school, FakeAIHistoryRepository())

        val context = builder.cachedContext()

        assertThat(context).isNotNull()
        assertThat(context!!.isStale).isTrue()
        assertThat(context.unavailableSections).containsExactly(
            GradeyAIContextSection.TRENDS,
            GradeyAIContextSection.TIMETABLE,
        ).inOrder()
        assertThat(context.subjects.single().recentMarks).hasSize(1)
        assertThat(context.timetable.single().id).isEqualTo("2026-08-31#lesson-current")
        assertThat(context.schoolScope).startsWith("school_")
        val rendered = context.toString()
        assertThat(rendered).doesNotContain("access-must-not-leak")
        assertThat(rendered).doesNotContain("refresh-must-not-leak")
        assertThat(rendered).doesNotContain("password-must-not-leak")
        assertThat(rendered).doesNotContain("teacher-private-id")
    }

    @Test
    fun `refresh retains cached marks when that section fails and publishes fresh history and timetable`() = runTest {
        val school = FakeAISchoolRepository(session).apply {
            cachedDashboard = dashboard()
            dashboardFailure = java.io.IOException("offline")
            freshWeeks["2026-08-31"] = week("2026-08-31", "lesson-current")
            freshWeeks["2026-09-07"] = week("2026-09-07", "lesson-next")
        }
        val history = FakeAIHistoryRepository(
            fresh = GradeHistoryResponse(
                events = listOf(
                    historyEvent("first", "2026-08-01T10:00:00Z", 2.5, 2),
                    historyEvent("last", "2026-08-30T10:00:00Z", 2.0, 4),
                ),
            ),
        )

        val context = builder(school, history).refreshContext()

        assertThat(context.isStale).isTrue()
        assertThat(context.unavailableSections).containsExactly(GradeyAIContextSection.MARKS)
        assertThat(context.subjects.single().name).isEqualTo("Mathematics")
        assertThat(context.trends.single().averageDelta).isWithin(0.001).of(-0.5)
        assertThat(context.timetable.map { it.id }).containsExactly(
            "2026-08-31#lesson-current",
            "2026-09-07#lesson-next",
        ).inOrder()
    }

    @Test
    fun `refresh reports no context only when every section fails without cached content`() = runTest {
        val school = FakeAISchoolRepository(session).apply {
            dashboardFailure = java.io.IOException("offline")
            timetableFailure = java.io.IOException("offline")
        }
        val history = FakeAIHistoryRepository(failure = java.io.IOException("offline"))

        val failure = runCatching { builder(school, history).refreshContext() }.exceptionOrNull()

        assertThat(failure).isInstanceOf(GradeyAIContextException::class.java)
        assertThat((failure as GradeyAIContextException).error)
            .isEqualTo(GradeyAIContextError.NO_CONTEXT_AVAILABLE)
    }

    @Test
    fun `mapper enforces iOS mark trend and lesson limits`() {
        val subjects = (0 until 20).map { subjectIndex ->
            Subject(
                subjectInfo = SubjectInfo("subject-$subjectIndex", "S$subjectIndex", "Subject $subjectIndex"),
                marks = (0 until 10).map { markIndex ->
                    Mark(
                        id = "$subjectIndex-$markIndex",
                        markText = "1",
                        markDate = "2026-08-${(markIndex + 1).toString().padStart(2, '0')}T10:00:00Z",
                    )
                },
            )
        }
        val mapped = GradeyAIContextMapper.subjects(subjects)

        assertThat(mapped.sumOf { it.recentMarks.size }).isEqualTo(GradeyAIContextMapper.MaximumTotalMarks)
        assertThat(mapped.all { it.recentMarks.size <= GradeyAIContextMapper.MaximumMarksPerSubject }).isTrue()
    }

    private fun builder(school: SchoolRepository, history: GradeyHistoryRepository) =
        AndroidGradeyAIContextBuilder(
            schoolRepository = school,
            historyRepository = history,
            scopeHasher = GradeyAISchoolScopeHasher(ByteArray(32) { 7 }),
            nowEpochMillis = { now },
        )

    private fun dashboard() = DashboardData(
        MarksResponse(
            listOf(
                Subject(
                    subjectInfo = SubjectInfo("math", "M", "Mathematics"),
                    marks = listOf(
                        Mark(
                            id = "mark",
                            markText = "1",
                            markDate = "2026-08-30T10:00:00Z",
                            teacherID = "teacher-private-id",
                            caption = "Exam",
                        ),
                    ),
                ),
            ),
        ),
    )

    private fun week(start: String, lessonID: String) = TimetableWeek(
        weekStart = start,
        hours = listOf(TimetableHour("1", "1", "08:00", "08:45")),
        days = listOf(
            ScheduledDay(
                id = start,
                date = start,
                dayOfWeek = 1,
                dayDescription = "Monday",
                dayType = "WorkDay",
                lessons = listOf(
                    ScheduledLesson(
                        id = lessonID,
                        hour = TimetableHour("1", "1", "08:00", "08:45"),
                        subjectName = "Mathematics",
                        subjectAbbrev = "M",
                        teacherName = "Teacher",
                        teacherAbbrev = "T",
                        roomAbbrev = "101",
                        roomName = "Room 101",
                        groups = listOf("Group A"),
                        theme = "Algebra",
                        hasHomework = false,
                        changeKind = LessonChangeKind.NONE,
                    ),
                ),
                isToday = start == "2026-08-31",
            ),
        ),
    )

    private fun historyEvent(id: String, date: String, average: Double, count: Int) = GradeHistoryEvent(
        id = id,
        linkedAccountID = "account",
        provider = com.bukovinafilip.gradey.model.LinkedAccountProvider.BAKALARI,
        subjectID = "math",
        subjectAbbrev = "M",
        subjectName = "Mathematics",
        averageValue = average,
        markCount = count,
        eventType = if (id == "first") GradeHistoryEventType.BASELINE else GradeHistoryEventType.CHANGED,
        capturedAt = date,
    )
}

private class FakeAIHistoryRepository(
    private val cached: GradeHistoryResponse? = null,
    private val fresh: GradeHistoryResponse = GradeHistoryResponse(),
    private val failure: Throwable? = null,
) : GradeyHistoryRepository {
    override suspend fun loadCachedGradeHistory(accountID: String?): GradeHistoryResponse? = cached
    override suspend fun gradeHistory(accountID: String?, days: Int?): GradeHistoryResponse {
        failure?.let { throw it }
        return fresh
    }
}

private class FakeAISchoolRepository(
    private var session: StoredSession?,
) : SchoolRepository {
    var cachedDashboard: DashboardData? = null
    var dashboardFailure: Throwable? = null
    var timetableFailure: Throwable? = null
    val cachedWeeks = mutableMapOf<String, TimetableWeek>()
    val freshWeeks = mutableMapOf<String, TimetableWeek>()

    override suspend fun bootstrapSession(): StoredSession? = session
    override suspend fun currentStoredSession(): StoredSession? = session
    override suspend fun restoreSession(session: StoredSession): StoredSession = session.also { this.session = it }
    override suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession = restoreSession(session)
    override suspend fun associateCurrentSession(account: LinkedSchoolAccount): StoredSession = requireNotNull(session)
    override suspend fun disassociateCurrentSession(accountID: String): StoredSession? = session
    override suspend fun logout() { session = null }
    override suspend fun loadCachedDashboard(): DashboardData? = cachedDashboard
    override suspend fun loadCachedAbsence(): AbsenceResponse? = null
    override suspend fun loadDashboard(forceRefresh: Boolean): DashboardData {
        dashboardFailure?.let { throw it }
        return requireNotNull(cachedDashboard)
    }
    override suspend fun loadCachedTimetable(weekContaining: String): TimetableWeek? = cachedWeeks[weekContaining]
    override suspend fun loadTimetable(weekContaining: String): TimetableWeek {
        timetableFailure?.let { throw it }
        return requireNotNull(freshWeeks[weekContaining])
    }
    override suspend fun login(schoolURL: String, username: String, password: String): StoredSession = error("unused")
    override suspend fun authenticateSchoolSessionCandidate(
        schoolURL: String,
        username: String,
        password: String,
        cloudMutationToken: com.bukovinafilip.gradey.domain.SchoolCloudMutationToken,
    ): com.bukovinafilip.gradey.domain.AuthenticatedSchoolSessionCandidate = error("unused")
    override suspend fun promoteAuthenticatedSchoolSessionCandidate(
        candidate: com.bukovinafilip.gradey.domain.AuthenticatedSchoolSessionCandidate,
        account: LinkedSchoolAccount,
        cloudMutationToken: com.bukovinafilip.gradey.domain.SchoolCloudMutationToken,
    ): StoredSession = error("unused")
    override suspend fun loadAbsence(forceRefresh: Boolean): AbsenceResponse = error("unused")
    override suspend fun resolveAbsenceSubjects(
        response: AbsenceResponse,
        onProgress: suspend (com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionProgress) -> Unit,
    ): AbsenceSubjectResolution = error("unused")
    override suspend fun saveManualAbsenceLessonSelections(selections: Map<String, Set<String>>) = Unit
    override suspend fun loadAbsencePredictionLessons(on: String): List<AbsenceLessonCandidate> = emptyList()
    override suspend fun predictSubjectAverage(subject: Subject, markText: String, weight: Int): Double? = null
}
