@file:Suppress("LongParameterList")

package com.bukovinafilip.gradey.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import kotlin.math.max

@Serializable
enum class SchoolProvider {
    @SerialName("bakalari")
    BAKALARI;

    val displayName: String
        get() = "Bakaláři"
}

@Serializable
data class SchoolDirectoryMunicipality(
    val name: String,
    val schoolCount: Int,
)

@Serializable
data class SchoolDirectorySchool(
    val id: String,
    val name: String,
    val town: String,
    val schoolURL: String,
) {
    val trimmedName: String get() = name.trim()
    val trimmedTown: String get() = town.trim()
    val trimmedSchoolURL: String get() = schoolURL.trim()
}

@Serializable
data class CachedSchoolDirectory(
    val schools: List<SchoolDirectorySchool>,
    val cachedAtEpochMillis: Long,
    val formatVersion: Int? = CURRENT_FORMAT_VERSION,
) {
    fun isStale(
        nowEpochMillis: Long = System.currentTimeMillis(),
        maxAgeMillis: Long = DEFAULT_MAX_AGE_MILLIS,
    ): Boolean = nowEpochMillis - cachedAtEpochMillis >= maxAgeMillis

    val isCurrentFormat: Boolean get() = formatVersion == CURRENT_FORMAT_VERSION

    companion object {
        const val CURRENT_FORMAT_VERSION = 2
        const val DEFAULT_MAX_AGE_MILLIS = 7L * 24 * 60 * 60 * 1_000
    }
}

@Serializable
data class BakalariCredentials(
    val username: String,
    val password: String,
)

@Serializable
data class StoredSession(
    var accessToken: String,
    var refreshToken: String,
    var tokenType: String,
    var expiresAtEpochMillis: Long,
    var baseURL: String,
    var provider: SchoolProvider = SchoolProvider.BAKALARI,
    var bakalari: BakalariCredentials? = null,
    var linkedAccountID: String? = null,
    var linkedAccountDisplayName: String? = null,
    var linkedAccountSchoolName: String? = null,
) {
    fun isExpired(nowEpochMillis: Long = System.currentTimeMillis()): Boolean =
        expiresAtEpochMillis <= nowEpochMillis + 60_000

    val cacheScope: String
        get() {
            val linked = linkedAccountID?.trim().orEmpty()
            if (linked.isNotEmpty()) return "linked-$linked"
            val host = baseURL
                .removePrefix("https://")
                .removePrefix("http://")
                .substringBefore("/")
                .lowercase(Locale.ROOT)
                .ifBlank { baseURL.lowercase(Locale.ROOT) }
            val username = bakalari?.username?.trim()?.lowercase(Locale.ROOT).orEmpty()
            val userScope = username
                .takeIf(String::isNotEmpty)
                ?.sha256Prefix()
                ?: "default"
            return "bakalari-$host-$userScope"
    }
}

@Serializable
data class StoredSchoolSessionEnvelope(
    val formatVersion: Int,
    val session: StoredSession,
)

private fun String.sha256Prefix(): String = MessageDigest
    .getInstance("SHA-256")
    .digest(toByteArray(StandardCharsets.UTF_8))
    .take(12)
    .joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }

@Serializable
data class LoginResponse(
    @SerialName("access_token")
    val accessToken: String,
    @SerialName("refresh_token")
    val refreshToken: String,
    @SerialName("token_type")
    val tokenType: String,
    @SerialName("expires_in")
    val expiresIn: Long,
    @SerialName("bak:ApiVersion")
    val apiVersion: String? = null,
    @SerialName("bak:AppVersion")
    val appVersion: String? = null,
    @SerialName("bak:UserId")
    val userID: String? = null,
)

@Serializable
data class MarksResponse(
    @SerialName("Subjects")
    val subjects: List<Subject> = emptyList(),
)

@Serializable
data class Subject(
    @SerialName("Marks")
    val marks: List<Mark> = emptyList(),
    @SerialName("Subject")
    val subjectInfo: SubjectInfo,
    @SerialName("AverageText")
    val averageText: String? = null,
    @SerialName("TemporaryMark")
    val temporaryMark: String? = null,
    @SerialName("SubjectNote")
    val subjectNote: String? = null,
    @SerialName("TemporaryMarkNote")
    val temporaryMarkNote: String? = null,
    @SerialName("PointsOnly")
    val pointsOnly: Boolean = false,
    @SerialName("MarkPredictionEnabled")
    val markPredictionEnabled: Boolean = true,
) {
    val id: String get() = subjectInfo.id
    val displayName: String get() = subjectInfo.name.ifBlank { subjectInfo.abbrev.ifBlank { id } }
}

@Serializable
data class SubjectInfo(
    @SerialName("Id")
    val id: String,
    @SerialName("Abbrev")
    val abbrev: String = "",
    @SerialName("Name")
    val name: String = "",
)

@Serializable
data class Mark(
    @SerialName("MarkDate")
    val markDate: String? = null,
    @SerialName("Caption")
    val caption: String? = null,
    @SerialName("Theme")
    val theme: String? = null,
    @SerialName("MarkText")
    val markText: String,
    @SerialName("TeacherId")
    val teacherID: String? = null,
    @SerialName("Type")
    val type: String? = null,
    @SerialName("TypeNote")
    val typeNote: String? = null,
    @SerialName("Weight")
    val weight: Double? = null,
    @SerialName("SubjectId")
    val subjectID: String,
    @SerialName("IsPoints")
    val isPoints: Boolean = false,
    @SerialName("Id")
    val id: String,
    @SerialName("PointsText")
    val pointsText: String? = null,
    @SerialName("MaxPoints")
    val maxPoints: Int? = null,
)

@Serializable
data class UserResponse(
    @SerialName("FullName")
    val fullName: String,
    @SerialName("SchoolName")
    val schoolName: String? = null,
    @SerialName("Class")
    val classAbbrev: String? = null,
    @SerialName("UserUID")
    val userUID: String? = null,
)

@Serializable
data class AbsenceResponse(
    @SerialName("PercentageThreshold")
    val percentageThreshold: Double? = null,
    @SerialName("Absences")
    val absences: List<Absence> = emptyList(),
    @SerialName("AbsencesPerSubject")
    val absencesPerSubject: List<AbsencePerSubject> = emptyList(),
)

@Serializable
data class Absence(
    @SerialName("Date")
    val date: String,
    @SerialName("Hour")
    val hour: String? = null,
    @SerialName("Type")
    val type: String? = null,
    @SerialName("Subject")
    val subject: String? = null,
    @SerialName("Unsolved")
    val unsolved: Int = 0,
    @SerialName("Ok")
    val ok: Int = 0,
    @SerialName("Missed")
    val missed: Int = 0,
    @SerialName("Late")
    val late: Int = 0,
    @SerialName("Soon")
    val soon: Int = 0,
    @SerialName("School")
    val school: Int = 0,
    @SerialName("DistanceTeaching")
    val distanceTeaching: Int = 0,
)

@Serializable
data class AbsencePerSubject(
    @SerialName("SubjectName")
    val subjectName: String,
    @SerialName("LessonsCount")
    val lessonsCount: Int,
    @SerialName("Base")
    val base: Int,
    @SerialName("Late")
    val late: Int = 0,
    @SerialName("Soon")
    val soon: Int = 0,
    @SerialName("School")
    val school: Int = 0,
    @SerialName("DistanceTeaching")
    val distanceTeaching: Int = 0,
)

@Serializable
data class AbsenceCounts(
    val ok: Int = 0,
    val late: Int = 0,
    val soon: Int = 0,
    val school: Int = 0,
    val distanceTeaching: Int = 0,
    val unsolved: Int = 0,
    val missed: Int = 0,
) {
    val total: Int get() = ok + late + soon + school + distanceTeaching + unsolved + missed
}

@Serializable
data class TimetableResponse(
    @SerialName("Hours")
    val hours: List<TimetableHour> = emptyList(),
    @SerialName("Days")
    val days: List<TimetableDayDTO> = emptyList(),
    @SerialName("Classes")
    val classes: List<TimetableEntity> = emptyList(),
    @SerialName("Groups")
    val groups: List<TimetableGroup> = emptyList(),
    @SerialName("Subjects")
    val subjects: List<TimetableEntity> = emptyList(),
    @SerialName("Teachers")
    val teachers: List<TimetableEntity> = emptyList(),
    @SerialName("Rooms")
    val rooms: List<TimetableEntity> = emptyList(),
    @SerialName("Cycles")
    val cycles: List<TimetableEntity> = emptyList(),
)

@Serializable
data class TimetableHour(
    @SerialName("Id")
    val id: String,
    @SerialName("Caption")
    val caption: String,
    @SerialName("BeginTime")
    val beginTime: String,
    @SerialName("EndTime")
    val endTime: String,
)

@Serializable
data class TimetableDayDTO(
    @SerialName("Atoms")
    val atoms: List<TimetableAtom> = emptyList(),
    @SerialName("DayOfWeek")
    val dayOfWeek: Int,
    @SerialName("Date")
    val date: String,
    @SerialName("DayDescription")
    val dayDescription: String = "",
    @SerialName("DayType")
    val dayType: String = "",
)

@Serializable
data class TimetableAtom(
    @SerialName("HourId")
    val hourID: String,
    @SerialName("SubjectId")
    val subjectID: String? = null,
    @SerialName("TeacherId")
    val teacherID: String? = null,
    @SerialName("RoomId")
    val roomID: String? = null,
    @SerialName("GroupIds")
    val groupIDs: List<String> = emptyList(),
    @SerialName("Theme")
    val theme: String? = null,
    @SerialName("HomeworkIds")
    val homeworkIDs: List<String> = emptyList(),
    @SerialName("Change")
    val change: TimetableChange? = null,
)

@Serializable
data class TimetableChange(
    @SerialName("ChangeType")
    val changeType: String? = null,
    @SerialName("Description")
    val description: String? = null,
)

@Serializable
data class TimetableEntity(
    @SerialName("Id")
    val id: String,
    @SerialName("Abbrev")
    val abbrev: String? = null,
    @SerialName("Name")
    val name: String? = null,
)

@Serializable
data class TimetableGroup(
    @SerialName("Id")
    val id: String,
    @SerialName("Abbrev")
    val abbrev: String? = null,
    @SerialName("Name")
    val name: String? = null,
)

@Serializable
enum class LessonChangeKind {
    NONE,
    CANCELED,
    SUBSTITUTION,
    ROOM_CHANGED,
    ADDED;

    companion object {
        fun fromApi(changeType: String?): LessonChangeKind {
            val normalized = changeType?.trim()?.lowercase().orEmpty()
            return when {
                normalized.contains("removed") || normalized.contains("canceled") || normalized.contains("cancelled") -> CANCELED
                normalized.contains("room") -> ROOM_CHANGED
                normalized.contains("added") -> ADDED
                normalized.isNotBlank() -> SUBSTITUTION
                else -> NONE
            }
        }
    }
}

@Serializable
data class TimetableWeek(
    val weekStart: String,
    val days: List<ScheduledDay>,
    val hours: List<TimetableHour>,
)

@Serializable
data class ScheduledDay(
    val id: String,
    val date: String?,
    val dayOfWeek: Int,
    val dayDescription: String,
    val dayType: String,
    val lessons: List<ScheduledLesson>,
    val isToday: Boolean,
)

@Serializable
data class ScheduledLesson(
    val id: String,
    val hour: TimetableHour,
    val subjectName: String?,
    val subjectAbbrev: String?,
    val teacherName: String?,
    val teacherAbbrev: String?,
    val roomAbbrev: String?,
    val roomName: String?,
    val groups: List<String>,
    val theme: String?,
    val hasHomework: Boolean,
    val changeDescription: String? = null,
    val changeKind: LessonChangeKind = LessonChangeKind.NONE,
) {
    val title: String get() = subjectAbbrev ?: subjectName ?: "Lesson"
    val roomTitle: String? get() = roomAbbrev ?: roomName
    val teacherTitle: String? get() = teacherAbbrev ?: teacherName
    val timeRange: String get() = listOf(hour.beginTime, hour.endTime).filter { it.isNotBlank() }.joinToString("-")
}

@Serializable
data class DashboardData(
    val marksResponse: MarksResponse,
    val absencesPerSubject: List<AbsencePerSubject> = emptyList(),
    val user: UserResponse? = null,
)

@Serializable
data class GradeyAccount(
    val id: String,
    val email: String? = null,
    var fullName: String? = null,
    val avatarURL: String? = null,
    val createdAtEpochMillis: Long = System.currentTimeMillis(),
)

@Serializable
data class GradeyAuthSession(
    val accessToken: String,
    val refreshToken: String? = null,
    val tokenType: String = "Bearer",
    val expiresAtEpochMillis: Long? = null,
    val account: GradeyAccount,
) {
    val authorizationHeader: String get() = "$tokenType $accessToken"
}

@Serializable
data class LinkedSchoolAccount(
    val id: String,
    val provider: SchoolProvider,
    val displayName: String,
    val schoolName: String? = null,
    val status: String = "active",
    val notificationsEnabled: Boolean = true,
)

@Serializable
data class NotificationPreferences(
    val newMarksEnabled: Boolean = true,
    val quietHoursEnabled: Boolean = false,
    val quietHoursStart: String = "22:00",
    val quietHoursEnd: String = "06:00",
) {
    companion object {
        val Default = NotificationPreferences()
    }
}

@Serializable
data class StravaCZStoredSession(
    val sessionID: String,
    val canteenNumber: String,
    val username: String,
    val balance: String? = null,
    val savedAtEpochMillis: Long = System.currentTimeMillis(),
)

@Serializable
data class StravaCZMenu(
    val days: List<StravaCZMenuDay> = emptyList(),
)

@Serializable
data class StravaCZMenuDay(
    val id: String,
    val title: String,
    val date: String,
    val meals: List<StravaCZMeal> = emptyList(),
)

@Serializable
data class StravaCZMeal(
    val id: Int,
    val title: String,
    val description: String? = null,
    val ordered: Boolean = false,
    val canModify: Boolean = true,
)

@Serializable
enum class NextLessonWidgetChangeKind {
    @SerialName("none")
    NONE,

    @SerialName("canceled")
    CANCELED,

    @SerialName("substitution")
    SUBSTITUTION,

    @SerialName("roomChanged")
    ROOM_CHANGED,

    @SerialName("added")
    ADDED,
}

@Serializable
enum class NextLessonWidgetTiming {
    @SerialName("current")
    CURRENT,

    @SerialName("upcoming")
    UPCOMING,
}

@Serializable
data class NextLessonWidgetSnapshot(
    val cachedAtEpochMillis: Long,
    val lessons: List<NextLessonWidgetLesson>,
)

@Serializable
data class NextLessonWidgetLesson(
    val id: String,
    val dayStartEpochMillis: Long,
    val startEpochMillis: Long? = null,
    val endEpochMillis: Long? = null,
    val subjectName: String? = null,
    val subjectAbbrev: String? = null,
    val timeRange: String? = null,
    val room: String? = null,
    val teacher: String? = null,
    val changeKind: NextLessonWidgetChangeKind = NextLessonWidgetChangeKind.NONE,
) {
    val title: String get() = subjectAbbrev?.ifBlank { null } ?: subjectName?.ifBlank { null } ?: "Lesson"
    val detailTitle: String get() = subjectName?.ifBlank { null } ?: subjectAbbrev?.ifBlank { null } ?: "Lesson"
    val sortEpochMillis: Long get() = startEpochMillis ?: dayStartEpochMillis
}

sealed interface NextLessonWidgetSelection {
    data class Lesson(val lesson: NextLessonWidgetLesson, val timing: NextLessonWidgetTiming) : NextLessonWidgetSelection
    data object NoSnapshot : NextLessonWidgetSelection
    data object NoLessons : NextLessonWidgetSelection
    data object Stale : NextLessonWidgetSelection
}

@Serializable
data class GradeyWearSyncPayload(
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
    val generatedAtEpochMillis: Long,
    val isSignedIn: Boolean,
    val auth: GradeyWearAuth? = null,
    val user: GradeyWearUser? = null,
    val timetable: GradeyWearTimetable? = null,
) {
    companion object {
        const val CURRENT_SCHEMA_VERSION = 2

        fun signedOut(nowEpochMillis: Long = System.currentTimeMillis()) = GradeyWearSyncPayload(
            generatedAtEpochMillis = nowEpochMillis,
            isSignedIn = false,
        )
    }
}

@Serializable
data class GradeyWearAuth(
    val baseURL: String,
    val accessToken: String,
    val refreshToken: String,
    val tokenType: String,
    val expiresAtEpochMillis: Long,
    val provider: SchoolProvider = SchoolProvider.BAKALARI,
    val username: String? = null,
    val password: String? = null,
    val sessionID: String? = null,
    val selectedStudentID: String? = null,
    val gsecHash: String? = null,
) {
    fun expiresSoon(nowEpochMillis: Long = System.currentTimeMillis(), leewayMillis: Long = 60_000): Boolean =
        expiresAtEpochMillis <= nowEpochMillis + leewayMillis
}

@Serializable
data class GradeyWearUser(
    val fullName: String,
    val schoolName: String? = null,
    val classAbbrev: String? = null,
)

@Serializable
data class GradeyWearTimetable(
    val weekStart: String,
    val cachedAtEpochMillis: Long,
    val days: List<GradeyWearTimetableDay>,
)

@Serializable
data class GradeyWearTimetableDay(
    val id: String,
    val date: String? = null,
    val dayStartEpochMillis: Long,
    val weekdayTitle: String,
    val detailTitle: String? = null,
    val isToday: Boolean,
    val isSchoolDay: Boolean,
    val lessons: List<GradeyWearTimetableLesson> = emptyList(),
)

@Serializable
data class GradeyWearTimetableLesson(
    val id: String,
    val dayStartEpochMillis: Long,
    val startEpochMillis: Long? = null,
    val endEpochMillis: Long? = null,
    val subjectName: String? = null,
    val subjectAbbrev: String? = null,
    val timeRange: String? = null,
    val room: String? = null,
    val teacher: String? = null,
    val changeKind: NextLessonWidgetChangeKind = NextLessonWidgetChangeKind.NONE,
) {
    val title: String get() = subjectAbbrev?.ifBlank { null } ?: subjectName?.ifBlank { null } ?: "Lesson"
    val detailTitle: String get() = subjectName?.ifBlank { null } ?: subjectAbbrev?.ifBlank { null } ?: "Lesson"
    val sortEpochMillis: Long get() = startEpochMillis ?: dayStartEpochMillis
}

sealed interface GradeyWearLessonSelection {
    data class Lesson(val lesson: GradeyWearTimetableLesson, val timing: NextLessonWidgetTiming) : GradeyWearLessonSelection
    data object NoTimetable : GradeyWearLessonSelection
    data object NoLessons : GradeyWearLessonSelection
    data object Stale : GradeyWearLessonSelection
}

@Serializable
data class DemoFixture(
    val dashboard: DashboardData,
    val timetable: TimetableWeek,
    val stravaCZMenu: StravaCZMenu,
)

fun Mark.normalizedWeight(): Double = max(0.0001, weight ?: 1.0)
