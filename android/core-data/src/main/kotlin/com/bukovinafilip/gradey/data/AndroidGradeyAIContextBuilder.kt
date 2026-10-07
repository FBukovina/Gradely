package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeHistoryTrends
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.GradeyAIContextBuilding
import com.bukovinafilip.gradey.domain.GradeyAIContextError
import com.bukovinafilip.gradey.domain.GradeyAIContextException
import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.domain.MarkDateParser
import com.bukovinafilip.gradey.domain.SchoolRepository
import com.bukovinafilip.gradey.domain.SubjectGradeTrend
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import com.bukovinafilip.gradey.model.GradeyAIContextSection
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAILessonChangeKind
import com.bukovinafilip.gradey.model.GradeyAILessonContext
import com.bukovinafilip.gradey.model.GradeyAIMarkContext
import com.bukovinafilip.gradey.model.GradeyAISubjectContext
import com.bukovinafilip.gradey.model.GradeyAITrendContext
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableWeek
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

class AndroidGradeyAIContextBuilder(
    private val schoolRepository: SchoolRepository,
    private val historyRepository: GradeyHistoryRepository,
    private val scopeHasher: GradeyAISchoolScopeHasher,
    private val nowEpochMillis: () -> Long = System::currentTimeMillis,
) : GradeyAIContextBuilding {
    override suspend fun currentSchoolScope(): String = scopeHasher.schoolScope(
        schoolRepository.currentStoredSession()
            ?: throw GradeyAIContextException(GradeyAIContextError.NO_SCHOOL_ACCOUNT),
    )

    override suspend fun cachedContext(): GradeyAIContextSnapshot? {
        val session = schoolRepository.currentStoredSession()
            ?: throw GradeyAIContextException(GradeyAIContextError.NO_SCHOOL_ACCOUNT)
        val scope = scopeHasher.schoolScope(session)
        val now = nowEpochMillis()
        val currentWeekStart = weekStart(now)
        val nextWeekStart = TimetableDates.apiDateString(TimetableDates.monday(Instant.ofEpochMilli(now)
            .atZone(SchoolZone).toLocalDate()).plusWeeks(1))
        val dashboard = schoolRepository.loadCachedDashboard()
        val history = historyRepository.loadCachedGradeHistory(session.linkedAccountID)
        val currentWeek = schoolRepository.loadCachedTimetable(currentWeekStart)
        val nextWeek = schoolRepository.loadCachedTimetable(nextWeekStart)
        if (dashboard == null && history == null && currentWeek == null && nextWeek == null) return null

        val unavailable = buildList {
            if (dashboard == null) add(GradeyAIContextSection.MARKS)
            if (history == null) add(GradeyAIContextSection.TRENDS)
            if (currentWeek == null || nextWeek == null) add(GradeyAIContextSection.TIMETABLE)
        }
        return snapshot(
            scope = scope,
            generatedAt = now,
            unavailable = unavailable,
            subjects = GradeyAIContextMapper.subjects(dashboard?.marksResponse?.subjects.orEmpty()),
            trends = GradeyAIContextMapper.trends(GradeHistoryTrends.make(history?.events.orEmpty())),
            weeks = listOfNotNull(currentWeek, nextWeek),
        )
    }

    override suspend fun refreshContext(): GradeyAIContextSnapshot = coroutineScope {
        val session = schoolRepository.currentStoredSession()
            ?: throw GradeyAIContextException(GradeyAIContextError.NO_SCHOOL_ACCOUNT)
        val scope = scopeHasher.schoolScope(session)
        val now = nowEpochMillis()
        val currentWeekStart = weekStart(now)
        val nextWeekStart = TimetableDates.apiDateString(TimetableDates.monday(Instant.ofEpochMilli(now)
            .atZone(SchoolZone).toLocalDate()).plusWeeks(1))
        val cached = cachedContext()?.takeIf { it.schoolScope == scope }

        val dashboardAttempt = async { attempt { schoolRepository.loadDashboard() } }
        val historyAttempt = async {
            attempt {
                session.linkedAccountID?.trim()?.takeIf(String::isNotEmpty)?.let {
                    historyRepository.gradeHistory(it, 90)
                } ?: GradeHistoryResponse()
            }
        }
        val currentWeekAttempt = async { attempt { schoolRepository.loadTimetable(currentWeekStart) } }
        val nextWeekAttempt = async { attempt { schoolRepository.loadTimetable(nextWeekStart) } }

        val dashboard = dashboardAttempt.await()
        val history = historyAttempt.await()
        val currentWeek = currentWeekAttempt.await()
        val nextWeek = nextWeekAttempt.await()
        val unavailable = buildList {
            if (dashboard.isFailure) add(GradeyAIContextSection.MARKS)
            if (history.isFailure) add(GradeyAIContextSection.TRENDS)
            if (currentWeek.isFailure || nextWeek.isFailure) add(GradeyAIContextSection.TIMETABLE)
        }
        val subjects = dashboard.getOrNull()
            ?.marksResponse?.subjects
            ?.let(GradeyAIContextMapper::subjects)
            ?: cached?.subjects.orEmpty()
        val trends = history.getOrNull()
            ?.events
            ?.let(GradeHistoryTrends::make)
            ?.let(GradeyAIContextMapper::trends)
            ?: cached?.trends.orEmpty()
        val weeks = listOfNotNull(
            currentWeek.getOrNull() ?: schoolRepository.loadCachedTimetable(currentWeekStart),
            nextWeek.getOrNull() ?: schoolRepository.loadCachedTimetable(nextWeekStart),
        )
        val lessons = GradeyAIContextMapper.lessons(weeks)
        val finalSession = schoolRepository.currentStoredSession()
        if (finalSession == null || scopeHasher.schoolScope(finalSession) != scope) {
            throw GradeyAIContextException(GradeyAIContextError.SCHOOL_ACCOUNT_CHANGED)
        }
        if (unavailable.size == 3 && subjects.isEmpty() && trends.isEmpty() && lessons.isEmpty()) {
            throw GradeyAIContextException(GradeyAIContextError.NO_CONTEXT_AVAILABLE)
        }
        GradeyAIContextSnapshot(
            schoolScope = scope,
            generatedAtEpochMillis = now,
            isStale = unavailable.isNotEmpty(),
            unavailableSections = ordered(unavailable),
            subjects = subjects,
            trends = trends,
            timetable = lessons,
        )
    }

    private fun snapshot(
        scope: String,
        generatedAt: Long,
        unavailable: List<GradeyAIContextSection>,
        subjects: List<GradeyAISubjectContext>,
        trends: List<GradeyAITrendContext>,
        weeks: List<TimetableWeek>,
    ) = GradeyAIContextSnapshot(
        schoolScope = scope,
        generatedAtEpochMillis = generatedAt,
        isStale = true,
        unavailableSections = ordered(unavailable),
        subjects = subjects,
        trends = trends,
        timetable = GradeyAIContextMapper.lessons(weeks),
    )

    private fun weekStart(epochMillis: Long): String = TimetableDates.apiDateString(
        TimetableDates.monday(Instant.ofEpochMilli(epochMillis).atZone(SchoolZone).toLocalDate()),
    )

    private suspend fun <T> attempt(block: suspend () -> T): Result<T> = try {
        Result.success(block())
    } catch (error: CancellationException) {
        throw error
    } catch (error: Throwable) {
        Result.failure(error)
    }

    private fun ordered(values: List<GradeyAIContextSection>) = listOf(
        GradeyAIContextSection.MARKS,
        GradeyAIContextSection.TRENDS,
        GradeyAIContextSection.TIMETABLE,
    ).filter(values::contains)

    private companion object {
        val SchoolZone: ZoneId = ZoneId.of("Europe/Prague")
    }
}

internal object GradeyAIContextMapper {
    const val MaximumMarksPerSubject = 5
    const val MaximumTotalMarks = 80
    const val MaximumTrends = 20
    const val MaximumLessons = 120

    fun subjects(values: List<Subject>): List<GradeyAISubjectContext> {
        data class Candidate(val subjectIndex: Int, val markIndex: Int, val mark: Mark)
        val candidates = values.flatMapIndexed { subjectIndex, subject ->
            subject.marks.mapIndexed { markIndex, mark -> Candidate(subjectIndex, markIndex, mark) }
        }.sortedWith(
            compareByDescending<Candidate> { MarkDateParser.instant(it.mark.markDate) ?: Instant.MIN }
                .thenBy(Candidate::subjectIndex)
                .thenBy(Candidate::markIndex),
        )
        val selected = mutableMapOf<Int, MutableList<Mark>>()
        candidates.forEach { candidate ->
            if (selected.values.sumOf { it.size } >= MaximumTotalMarks) return@forEach
            val marks = selected.getOrPut(candidate.subjectIndex, ::mutableListOf)
            if (marks.size < MaximumMarksPerSubject) marks += candidate.mark
        }
        return values.mapIndexed { index, subject ->
            GradeyAISubjectContext(
                id = subject.id.take(128),
                name = trimmed(subject.subjectInfo.name, 120)
                    ?: trimmed(subject.subjectInfo.abbrev, 32)
                    ?: subject.id.take(128),
                abbreviation = trimmed(subject.subjectInfo.abbrev, 32),
                average = GradeMath.subjectAverage(subject),
                pointsOnly = subject.pointsOnly,
                totalMarkCount = subject.marks.size,
                recentMarks = selected[index].orEmpty().map(::mark),
            )
        }.sortedBy { it.name.lowercase() }
    }

    fun trends(values: List<SubjectGradeTrend>): List<GradeyAITrendContext> = values
        .take(MaximumTrends)
        .map { trend ->
            GradeyAITrendContext(
                subjectID = trend.subjectID.take(128),
                subjectName = trimmed(trend.subjectName, 120)
                    ?: trimmed(trend.subjectAbbrev, 32)
                    ?: trend.subjectID.take(128),
                subjectAbbreviation = trimmed(trend.subjectAbbrev, 32),
                firstAverage = trend.firstAverage,
                latestAverage = trend.latestAverage,
                averageDelta = trend.averageDelta,
                firstMarkCount = trend.firstMarkCount,
                latestMarkCount = trend.latestMarkCount,
            )
        }

    fun lessons(weeks: List<TimetableWeek>): List<GradeyAILessonContext> {
        val seen = mutableSetOf<String>()
        val result = mutableListOf<GradeyAILessonContext>()
        weeks.sortedBy(TimetableWeek::weekStart).forEach { week ->
            week.days.sortedWith(compareBy({ it.date == null }, { it.date }, { it.dayOfWeek })).forEach { day ->
                val date = day.date ?: return@forEach
                day.lessons.forEach { lesson ->
                    if (result.size >= MaximumLessons) return result
                    val id = "$date#${lesson.id}"
                    if (!seen.add(id)) return@forEach
                    val subject = trimmed(lesson.subjectName, 120)
                        ?: trimmed(lesson.subjectAbbrev, 32)
                        ?: return@forEach
                    result += GradeyAILessonContext(
                        id = id.take(180),
                        date = date,
                        subject = subject,
                        subjectAbbreviation = trimmed(lesson.subjectAbbrev, 32),
                        beginsAt = lesson.hour.beginTime.take(16),
                        endsAt = lesson.hour.endTime.take(16),
                        teacher = trimmed(lesson.teacherName, 120) ?: trimmed(lesson.teacherAbbrev, 32),
                        room = trimmed(lesson.roomName, 120) ?: trimmed(lesson.roomAbbrev, 32),
                        groups = lesson.groups.mapNotNull { trimmed(it, 64) }.take(12),
                        changeKind = when (lesson.changeKind) {
                            LessonChangeKind.NONE -> GradeyAILessonChangeKind.NONE
                            LessonChangeKind.CANCELED -> GradeyAILessonChangeKind.CANCELLED
                            LessonChangeKind.SUBSTITUTION -> GradeyAILessonChangeKind.SUBSTITUTION
                            LessonChangeKind.ROOM_CHANGED -> GradeyAILessonChangeKind.ROOM_CHANGED
                            LessonChangeKind.ADDED -> GradeyAILessonChangeKind.ADDED
                        },
                        changeDescription = trimmed(lesson.changeDescription, 300),
                    )
                }
            }
        }
        return result
    }

    private fun mark(value: Mark) = GradeyAIMarkContext(
        value = value.markText.take(64),
        date = value.markDate.orEmpty().substringBefore('T').take(32),
        weight = value.weight,
        title = trimmed(value.caption, 200) ?: trimmed(value.theme, 200),
        isPoints = value.isPoints,
        pointsText = trimmed(value.pointsText, 64),
        maxPoints = value.maxPoints,
    )

    private fun trimmed(value: String?, maximumLength: Int): String? = value
        ?.trim()
        ?.takeIf(String::isNotEmpty)
        ?.take(maximumLength)
}
