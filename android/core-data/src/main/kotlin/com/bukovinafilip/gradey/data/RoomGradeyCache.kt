package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.CachedSchoolDirectory
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.NextLessonWidgetSnapshot
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.domain.NextLessonSnapshotBuilder
import com.bukovinafilip.gradey.domain.AbsenceLessonSelections
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

class RoomGradeyCache(
    private val dao: CacheEntryDao,
    private val json: Json,
) {
    suspend fun loadDashboard(scope: String): DashboardData? = load(key("dashboard", scope), DashboardData.serializer())
    suspend fun saveDashboard(scope: String, data: DashboardData) = save(key("dashboard", scope), data, DashboardData.serializer())

    suspend fun loadMarks(scope: String): MarksResponse? = load(key("marks", scope), MarksResponse.serializer())
    suspend fun saveMarks(scope: String, data: MarksResponse) = save(key("marks", scope), data, MarksResponse.serializer())

    suspend fun loadAbsence(scope: String): AbsenceResponse? = load(key("absence-v2", scope), AbsenceResponse.serializer())
    suspend fun saveAbsence(scope: String, data: AbsenceResponse) = save(key("absence-v2", scope), data, AbsenceResponse.serializer())

    suspend fun loadAbsenceLessonSelections(scope: String): AbsenceLessonSelections? =
        load(key("absence-lesson-selections-v1", scope), AbsenceLessonSelections.serializer())

    suspend fun saveAbsenceLessonSelections(scope: String, selections: AbsenceLessonSelections) =
        save(key("absence-lesson-selections-v1", scope), selections, AbsenceLessonSelections.serializer())

    suspend fun loadTimetable(scope: String, weekStart: String): TimetableWeek? =
        load(key("timetable-week", "$scope-$weekStart"), TimetableWeek.serializer())

    suspend fun saveTimetable(scope: String, weekStart: String, data: TimetableWeek) =
        save(key("timetable-week", "$scope-$weekStart"), data, TimetableWeek.serializer())

    suspend fun loadRawTimetable(scope: String, weekStart: String): TimetableResponse? =
        load(key("timetable-raw", "$scope-$weekStart"), TimetableResponse.serializer())

    suspend fun saveRawTimetable(scope: String, weekStart: String, data: TimetableResponse) =
        save(key("timetable-raw", "$scope-$weekStart"), data, TimetableResponse.serializer())

    suspend fun loadStravaMenu(scope: String): StravaCZMenu? = load(key("strava-menu", scope), StravaCZMenu.serializer())
    suspend fun saveStravaMenu(scope: String, menu: StravaCZMenu) = save(key("strava-menu", scope), menu, StravaCZMenu.serializer())
    suspend fun clearStravaMenu(scope: String) = dao.clear(key("strava-menu", scope))

    suspend fun loadGradeHistory(scope: String): GradeHistoryResponse? =
        load(key("grade-history", scope), GradeHistoryResponse.serializer())

    suspend fun saveGradeHistory(scope: String, history: GradeHistoryResponse) =
        save(key("grade-history", scope), history, GradeHistoryResponse.serializer())

    suspend fun clearGradeHistory(scope: String) = dao.clear(key("grade-history", scope))

    suspend fun clearAllGradeHistory() = dao.clearPrefix("grade-history:")

    suspend fun loadSchoolDirectory(): CachedSchoolDirectory? =
        load("school-directory-v2", CachedSchoolDirectory.serializer())

    suspend fun saveSchoolDirectory(directory: CachedSchoolDirectory) =
        save("school-directory-v2", directory, CachedSchoolDirectory.serializer())

    suspend fun loadNextLessonSnapshot(): NextLessonWidgetSnapshot? =
        load("next-lesson-widget-snapshot", NextLessonWidgetSnapshot.serializer())

    suspend fun saveNextLessonSnapshot(snapshot: NextLessonWidgetSnapshot) =
        save("next-lesson-widget-snapshot", snapshot, NextLessonWidgetSnapshot.serializer())

    suspend fun updateNextLessonSnapshot(week: TimetableWeek, cachedAtEpochMillis: Long = System.currentTimeMillis()) =
        saveNextLessonSnapshot(
            NextLessonSnapshotBuilder.update(loadNextLessonSnapshot(), week, cachedAtEpochMillis),
        )

    suspend fun clearNextLessonSnapshot() = dao.clear("next-lesson-widget-snapshot")

    suspend fun clearSchool(scope: String) {
        dao.clearPrefix("dashboard:$scope")
        dao.clearPrefix("marks:$scope")
        dao.clearPrefix("absence:$scope")
        dao.clearPrefix("absence-v2:$scope")
        dao.clearPrefix("absence-lesson-selections-v1:$scope")
        dao.clearPrefix("timetable-week:$scope")
        dao.clearPrefix("timetable-raw:$scope")
    }

    suspend fun clearAllSchoolData() {
        listOf(
            "dashboard:",
            "marks:",
            "absence:",
            "absence-v2:",
            "absence-lesson-selections-v1:",
            "timetable-week:",
            "timetable-raw:",
        ).forEach { dao.clearPrefix(it) }
        clearNextLessonSnapshot()
    }

    private suspend fun <T> load(key: String, serializer: KSerializer<T>): T? {
        val entity = dao.load(key) ?: return null
        return runCatching { json.decodeFromString(serializer, entity.payload) }.getOrNull()
    }

    private suspend fun <T> save(key: String, value: T, serializer: KSerializer<T>) {
        dao.save(
            CacheEntryEntity(
                key = key,
                payload = json.encodeToString(serializer, value),
                cachedAtEpochMillis = System.currentTimeMillis(),
            ),
        )
    }

    private fun key(prefix: String, scope: String): String = "$prefix:$scope"
}
