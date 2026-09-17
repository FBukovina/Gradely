package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.AbsenceLessonSelections
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.NextLessonWidgetLesson
import com.bukovinafilip.gradey.model.NextLessonWidgetSnapshot
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import org.junit.Test

class RoomGradeyCacheTest {
    @Test
    fun `scope copy retains every school cache family and global projection`() = runTest {
        val dao = ScopeCacheDao()
        val cache = RoomGradeyCache(dao, GradeyJson)
        val source = "linked-account-a"
        val destination = "bakalari-school.example-local-a"
        val dashboard = DashboardData(MarksResponse(), user = UserResponse("Student A"))
        val marks = MarksResponse()
        val absence = AbsenceResponse(percentageThreshold = 25.0)
        val legacyAbsence = AbsenceResponse(percentageThreshold = 20.0)
        val selections = AbsenceLessonSelections(mapOf("2026-08-31" to listOf("lesson-1")))
        val firstWeek = TimetableWeek("2026-08-31", emptyList(), emptyList())
        val secondWeek = TimetableWeek("2026-09-07", emptyList(), emptyList())
        val firstRaw = TimetableResponse()
        val secondRaw = TimetableResponse()
        val widget = NextLessonWidgetSnapshot(
            cachedAtEpochMillis = 10,
            lessons = listOf(NextLessonWidgetLesson("lesson-1", 100)),
        )

        cache.saveDashboard(source, dashboard)
        cache.saveMarks(source, marks)
        cache.saveAbsence(source, absence)
        cache.saveAbsenceLessonSelections(source, selections)
        cache.saveTimetable(source, firstWeek.weekStart, firstWeek)
        cache.saveTimetable(source, secondWeek.weekStart, secondWeek)
        cache.saveRawTimetable(source, firstWeek.weekStart, firstRaw)
        cache.saveRawTimetable(source, secondWeek.weekStart, secondRaw)
        cache.saveNextLessonSnapshot(widget)
        cache.saveGradeHistory(source, GradeHistoryResponse())
        dao.save(
            CacheEntryEntity(
                key = "absence:$source",
                payload = GradeyJson.encodeToString(AbsenceResponse.serializer(), legacyAbsence),
                cachedAtEpochMillis = 5,
            ),
        )

        cache.copySchoolScope(source, destination)

        assertThat(cache.loadDashboard(destination)).isEqualTo(dashboard)
        assertThat(cache.loadMarks(destination)).isEqualTo(marks)
        assertThat(cache.loadAbsence(destination)).isEqualTo(absence)
        assertThat(cache.loadAbsenceLessonSelections(destination)).isEqualTo(selections)
        assertThat(cache.loadTimetable(destination, firstWeek.weekStart)).isEqualTo(firstWeek)
        assertThat(cache.loadTimetable(destination, secondWeek.weekStart)).isEqualTo(secondWeek)
        assertThat(cache.loadRawTimetable(destination, firstWeek.weekStart)).isEqualTo(firstRaw)
        assertThat(cache.loadRawTimetable(destination, secondWeek.weekStart)).isEqualTo(secondRaw)
        assertThat(dao.load("absence:$destination")?.payload)
            .isEqualTo(dao.load("absence:$source")?.payload)
        assertThat(cache.loadNextLessonSnapshot()).isEqualTo(widget)
        assertThat(cache.loadGradeHistory(destination)).isNull()
        assertThat(cache.loadDashboard(source)).isEqualTo(dashboard)
        assertThat(cache.loadTimetable(source, secondWeek.weekStart)).isEqualTo(secondWeek)
    }

    @Test
    fun `active readable source wins conflicts while malformed source cannot replace readable destination`() = runTest {
        val dao = ScopeCacheDao()
        val cache = RoomGradeyCache(dao, GradeyJson)
        val source = "linked-account-a"
        val destination = "bakalari-school.example-local-a"
        val activeDashboard = DashboardData(MarksResponse(), user = UserResponse("Active student"))
        val dormantDashboard = DashboardData(MarksResponse(), user = UserResponse("Dormant alias"))
        val readableAbsence = AbsenceResponse(percentageThreshold = 30.0)
        val activeWeek = TimetableWeek("2026-08-31", emptyList(), emptyList())

        dao.save(entity("dashboard:$source", activeDashboard, DashboardData.serializer(), cachedAt = 1))
        dao.save(entity("dashboard:$destination", dormantDashboard, DashboardData.serializer(), cachedAt = 999))
        dao.save(CacheEntryEntity("absence-v2:$source", "{malformed", 1_000))
        dao.save(entity("absence-v2:$destination", readableAbsence, AbsenceResponse.serializer(), cachedAt = 2))
        dao.save(entity("timetable-week:$source-2026-08-31", activeWeek, TimetableWeek.serializer(), cachedAt = 3))
        dao.save(CacheEntryEntity("timetable-week:$destination-2026-08-31", "not-json", 4_000))

        cache.copySchoolScope(source, destination)

        assertThat(cache.loadDashboard(destination)).isEqualTo(activeDashboard)
        assertThat(dao.load("dashboard:$destination")?.cachedAtEpochMillis).isEqualTo(1)
        assertThat(cache.loadAbsence(destination)).isEqualTo(readableAbsence)
        assertThat(dao.load("absence-v2:$destination")?.cachedAtEpochMillis).isEqualTo(2)
        assertThat(cache.loadTimetable(destination, "2026-08-31")).isEqualTo(activeWeek)
        assertThat(dao.load("timetable-week:$destination-2026-08-31")?.cachedAtEpochMillis).isEqualTo(3)
    }

    @Test
    fun `scope operations do not match prefix account collisions or non-date timetable suffixes`() = runTest {
        val dao = ScopeCacheDao()
        val cache = RoomGradeyCache(dao, GradeyJson)
        val source = "linked-a"
        val collidingScope = "linked-a-other"
        val destination = "local-a"
        val sourceDashboard = DashboardData(MarksResponse(), user = UserResponse("A"))
        val otherDashboard = DashboardData(MarksResponse(), user = UserResponse("Other"))
        val sourceWeek = TimetableWeek("2026-08-31", emptyList(), emptyList())
        val otherWeek = TimetableWeek("2026-09-07", emptyList(), emptyList())

        cache.saveDashboard(source, sourceDashboard)
        cache.saveDashboard(collidingScope, otherDashboard)
        cache.saveTimetable(source, sourceWeek.weekStart, sourceWeek)
        cache.saveTimetable(collidingScope, otherWeek.weekStart, otherWeek)

        cache.copySchoolScope(source, destination)
        cache.clearSchool(source)

        assertThat(cache.loadDashboard(destination)).isEqualTo(sourceDashboard)
        assertThat(cache.loadTimetable(destination, sourceWeek.weekStart)).isEqualTo(sourceWeek)
        assertThat(cache.loadDashboard(source)).isNull()
        assertThat(cache.loadTimetable(source, sourceWeek.weekStart)).isNull()
        assertThat(cache.loadDashboard(collidingScope)).isEqualTo(otherDashboard)
        assertThat(cache.loadTimetable(collidingScope, otherWeek.weekStart)).isEqualTo(otherWeek)
        assertThat(cache.loadTimetable(destination, otherWeek.weekStart)).isNull()
    }

    private fun <T> entity(
        key: String,
        value: T,
        serializer: kotlinx.serialization.KSerializer<T>,
        cachedAt: Long,
    ) = CacheEntryEntity(
        key = key,
        payload = GradeyJson.encodeToString(serializer, value),
        cachedAtEpochMillis = cachedAt,
    )
}

private class ScopeCacheDao : CacheEntryDao {
    private val entries = linkedMapOf<String, CacheEntryEntity>()

    override suspend fun load(key: String): CacheEntryEntity? = entries[key]

    override suspend fun loadExactPrefix(prefix: String): List<CacheEntryEntity> =
        entries.values.filter { it.key.startsWith(prefix) }

    override suspend fun save(entity: CacheEntryEntity) {
        entries[entity.key] = entity
    }

    override suspend fun clear(key: String) {
        entries.remove(key)
    }

    override suspend fun clearPrefix(prefix: String) {
        entries.keys.filter { it.startsWith(prefix) }.forEach(entries::remove)
    }

    override suspend fun clearAll() {
        entries.clear()
    }
}
