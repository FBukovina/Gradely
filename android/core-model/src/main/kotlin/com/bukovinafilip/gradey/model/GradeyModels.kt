@file:Suppress("LongParameterList")

package com.bukovinafilip.gradey.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Required
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.longOrNull
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.Normalizer
import java.util.Locale
import java.util.UUID
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
    @Serializable(with = NullAsEmptyListSerializer::class)
    val subjects: List<Subject> = emptyList(),
)

@Serializable
data class Subject(
    @SerialName("Marks")
    @Serializable(with = NullAsEmptyListSerializer::class)
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
    val markPredictionEnabled: Boolean = false,
) {
    val id: String get() = subjectInfo.id
    val displayName: String get() = subjectInfo.name.ifBlank { subjectInfo.abbrev.ifBlank { id } }
}

@Serializable
data class SubjectInfo(
    @SerialName("Id")
    val id: String,
    @SerialName("Abbrev")
    @Required
    val abbrev: String = "",
    @SerialName("Name")
    @Required
    val name: String = "",
)

@OptIn(ExperimentalSerializationApi::class)
internal object NullAsGeneratedMarkIDSerializer : KSerializer<String> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("NullAsGeneratedMarkID", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        if (decoder.decodeNotNullMark()) return decoder.decodeString()
        decoder.decodeNull()
        return UUID.randomUUID().toString()
    }

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}

@Serializable
data class Mark(
    @SerialName("MarkDate")
    @Serializable(with = NullAsEmptyStringSerializer::class)
    val markDate: String = "",
    @SerialName("EditDate")
    val editDate: String? = null,
    @SerialName("Caption")
    val caption: String? = null,
    @SerialName("Theme")
    val theme: String? = null,
    @SerialName("MarkText")
    val markText: String = "",
    @SerialName("TeacherId")
    val teacherID: String? = null,
    @SerialName("Type")
    @Serializable(with = NullAsEmptyStringSerializer::class)
    val type: String = "",
    @SerialName("TypeNote")
    val typeNote: String? = null,
    @SerialName("Weight")
    @Serializable(with = FlexibleNullableDoubleSerializer::class)
    val weight: Double? = null,
    @SerialName("SubjectId")
    val subjectID: String = "",
    @SerialName("IsNew")
    val isNew: Boolean = false,
    @SerialName("IsPoints")
    val isPoints: Boolean = false,
    @SerialName("Id")
    @Serializable(with = NullAsGeneratedMarkIDSerializer::class)
    val id: String = UUID.randomUUID().toString(),
    @SerialName("PointsText")
    val pointsText: String? = null,
    @SerialName("MaxPoints")
    val maxPoints: Int? = null,
    @SerialName("CalculatedMarkText")
    val calculatedMarkText: String? = null,
    @SerialName("ClassRankText")
    val classRankText: String? = null,
    @SerialName("ConfirmedWhen")
    val confirmedWhen: String? = null,
    @SerialName("ConfirmedBy")
    val confirmedBy: String? = null,
    @SerialName("MarkConfirmationState")
    val markConfirmationState: String? = null,
)

@Serializable
data class UserResponse(
    @SerialName("FullName")
    val fullName: String,
    @SerialName("SchoolName")
    val schoolName: String? = null,
    @SerialName("Class")
    @Serializable(with = FlexibleNullableClassInfoSerializer::class)
    val userClass: ClassInfo? = null,
    @SerialName("UserUID")
    val userUID: String? = null,
    @SerialName("SchoolOrganizationName")
    val schoolOrganizationName: String? = null,
    @SerialName("UserType")
    val userType: String? = null,
    @SerialName("UserTypeText")
    val userTypeText: String? = null,
    @SerialName("StudyYear")
    val studyYear: Int? = null,
) {
    val classAbbrev: String? get() = userClass?.abbrev
    val displaySchoolName: String? get() = schoolOrganizationName.displayableSchoolName()
        ?: schoolName.displayableSchoolName()
}

@Serializable
data class ClassInfo(
    @SerialName("Id")
    @Required
    val id: String = "",
    @SerialName("Abbrev")
    @Required
    val abbrev: String = "",
    @SerialName("Name")
    val name: String? = null,
)

@Serializable
data class AbsenceResponse(
    @SerialName("PercentageThreshold")
    val percentageThreshold: Double? = null,
    @SerialName("Absences")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val absences: List<Absence> = emptyList(),
    @SerialName("AbsencesPerSubject")
    @Serializable(with = NullAsEmptyListSerializer::class)
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
    @Serializable(with = NullAsEmptyListSerializer::class)
    val hours: List<TimetableHour> = emptyList(),
    @SerialName("Days")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val days: List<TimetableDayDTO> = emptyList(),
    @SerialName("Classes")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val classes: List<TimetableEntity> = emptyList(),
    @SerialName("Groups")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val groups: List<TimetableGroup> = emptyList(),
    @SerialName("Subjects")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val subjects: List<TimetableEntity> = emptyList(),
    @SerialName("Teachers")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val teachers: List<TimetableEntity> = emptyList(),
    @SerialName("Rooms")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val rooms: List<TimetableEntity> = emptyList(),
    @SerialName("Cycles")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val cycles: List<TimetableEntity> = emptyList(),
)

@Serializable
data class TimetableHour(
    @SerialName("Id")
    @Serializable(with = FlexibleStringSerializer::class)
    val id: String = "",
    @SerialName("Caption")
    val caption: String = "",
    @SerialName("BeginTime")
    val beginTime: String = "",
    @SerialName("EndTime")
    val endTime: String = "",
)

@Serializable
data class TimetableDayDTO(
    @SerialName("Atoms")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val atoms: List<TimetableAtom> = emptyList(),
    @SerialName("DayOfWeek")
    val dayOfWeek: Int = 0,
    @SerialName("Date")
    val date: String = "",
    @SerialName("DayDescription")
    val dayDescription: String = "",
    @SerialName("DayType")
    val dayType: String = "WorkDay",
)

@Serializable
data class TimetableAtom(
    @SerialName("HourId")
    @Serializable(with = FlexibleStringSerializer::class)
    val hourID: String = "",
    @SerialName("SubjectId")
    val subjectID: String? = null,
    @SerialName("TeacherId")
    val teacherID: String? = null,
    @SerialName("RoomId")
    val roomID: String? = null,
    @SerialName("GroupIds")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val groupIDs: List<String> = emptyList(),
    @SerialName("CycleIds")
    @Serializable(with = NullAsEmptyListSerializer::class)
    val cycleIDs: List<String> = emptyList(),
    @SerialName("Theme")
    val theme: String? = null,
    @SerialName("HomeworkIds")
    @Serializable(with = NullAsEmptyListSerializer::class)
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
    @SerialName("ChangeSubject")
    val changeSubject: String? = null,
    @SerialName("Day")
    val day: String? = null,
    @SerialName("Hours")
    val hours: String? = null,
    @SerialName("Time")
    val time: String? = null,
    @SerialName("TypeAbbrev")
    val typeAbbrev: String? = null,
    @SerialName("TypeName")
    val typeName: String? = null,
)

@Serializable
data class TimetableEntity(
    @SerialName("Id")
    val id: String = "",
    @SerialName("Abbrev")
    val abbrev: String? = null,
    @SerialName("Name")
    val name: String? = null,
)

@Serializable
data class TimetableGroup(
    @SerialName("Id")
    val id: String = "",
    @SerialName("Abbrev")
    val abbrev: String? = null,
    @SerialName("Name")
    val name: String? = null,
    @SerialName("ClassId")
    val classID: String? = null,
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
    val change: TimetableChange? = null,
) {
    /**
     * The best subject label supplied by Bakaláři, or null when the payload has no label.
     * Human-readable fallbacks belong at the localized UI boundary.
     */
    val title: String? get() = subjectAbbrev.nonBlankValue() ?: subjectName.nonBlankValue()
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
enum class GradeHistoryEventType {
    @SerialName("baseline")
    BASELINE,

    @SerialName("changed")
    CHANGED,
}

@Serializable
data class GradeHistoryEvent(
    val id: String,
    @SerialName("linked_account_id")
    val linkedAccountID: String,
    val provider: LinkedAccountProvider,
    @SerialName("subject_id")
    val subjectID: String,
    @SerialName("subject_abbrev")
    val subjectAbbrev: String? = null,
    @SerialName("subject_name")
    val subjectName: String? = null,
    @SerialName("average_value")
    val averageValue: Double? = null,
    @SerialName("mark_count")
    val markCount: Int = 0,
    @SerialName("average_delta")
    val averageDelta: Double? = null,
    @SerialName("mark_count_delta")
    val markCountDelta: Int = 0,
    @SerialName("event_type")
    val eventType: GradeHistoryEventType,
    @SerialName("captured_at")
    val capturedAt: String,
)

@Serializable
data class NewMarkEvent(
    val id: String,
    @SerialName("linked_account_id")
    val linkedAccountID: String,
    val provider: LinkedAccountProvider,
    @SerialName("subject_id")
    val subjectID: String,
    @SerialName("subject_abbrev")
    val subjectAbbrev: String? = null,
    @SerialName("subject_name")
    val subjectName: String? = null,
    @SerialName("mark_text")
    val markText: String,
    @SerialName("created_at")
    val createdAt: String,
    @SerialName("delivered_at")
    val deliveredAt: String? = null,
)

@Serializable
data class GradeHistoryResponse(
    val events: List<GradeHistoryEvent> = emptyList(),
    @Serializable(with = LenientNewMarkEventListSerializer::class)
    val recentNewMarkEvents: List<NewMarkEvent> = emptyList(),
)

object LenientNewMarkEventListSerializer : KSerializer<List<NewMarkEvent>> {
    private val delegate = ListSerializer(NewMarkEvent.serializer())

    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun deserialize(decoder: Decoder): List<NewMarkEvent> {
        if (decoder !is JsonDecoder) return decoder.decodeSerializableValue(delegate)
        val elements = decoder.decodeJsonElement() as? JsonArray ?: return emptyList()
        return elements.mapNotNull { element ->
            runCatching {
                decoder.json.decodeFromJsonElement(NewMarkEvent.serializer(), element)
            }.getOrNull()
        }
    }

    override fun serialize(encoder: Encoder, value: List<NewMarkEvent>) {
        encoder.encodeSerializableValue(delegate, value)
    }
}

@Serializable
enum class LinkedAccountStatus {
    @SerialName("active")
    ACTIVE,

    @SerialName("action_required")
    ACTION_REQUIRED,

    @SerialName("paused")
    PAUSED,

    @SerialName("linking")
    LINKING,

    @SerialName("failed")
    FAILED,
}

@Serializable
enum class LinkedAccountProvider {
    @SerialName("bakalari")
    BAKALARI,

    @SerialName("eduPage")
    EDU_PAGE,

    @SerialName("stravaCZ")
    STRAVA_CZ;

    val displayName: String
        get() = when (this) {
            BAKALARI -> "Bakaláři"
            EDU_PAGE -> "EduPage"
            STRAVA_CZ -> "Strava.cz"
        }

    val isSupportedSchoolProvider: Boolean get() = this == BAKALARI

    companion object {
        fun from(provider: SchoolProvider): LinkedAccountProvider = when (provider) {
            SchoolProvider.BAKALARI -> BAKALARI
        }
    }
}

@Serializable
data class LinkedSchoolAccount(
    val id: String,
    val provider: LinkedAccountProvider,
    val providerUserID: String? = null,
    val displayName: String,
    val schoolName: String? = null,
    val canteenName: String? = null,
    val status: LinkedAccountStatus = LinkedAccountStatus.ACTIVE,
    val notificationsEnabled: Boolean = true,
    val lastPolledAt: String? = null,
    val lastSyncedAt: String? = null,
    val actionRequiredReason: String? = null,
)

@Serializable
data class LinkedSchoolTokenPayload(
    val provider: SchoolProvider,
    val baseURL: String,
    val accessToken: String,
    val refreshToken: String? = null,
    val tokenType: String,
    val expiresAt: String? = null,
    val bakalari: BakalariCredentials? = null,
) {
    fun makeStoredSession(account: LinkedSchoolAccount): StoredSession = StoredSession(
        accessToken = accessToken,
        refreshToken = refreshToken.orEmpty(),
        tokenType = tokenType,
        expiresAtEpochMillis = expiresAt
            ?.let { runCatching { java.time.Instant.parse(it).toEpochMilli() }.getOrNull() }
            ?: Long.MAX_VALUE,
        baseURL = baseURL,
        provider = provider,
        bakalari = bakalari,
        linkedAccountID = account.id,
        linkedAccountDisplayName = account.displayName,
        linkedAccountSchoolName = account.schoolName,
    )

    companion object {
        fun from(session: StoredSession): LinkedSchoolTokenPayload = LinkedSchoolTokenPayload(
            provider = session.provider,
            baseURL = session.baseURL,
            accessToken = session.accessToken,
            refreshToken = session.refreshToken.takeIf(String::isNotEmpty),
            tokenType = session.tokenType,
            expiresAt = session.expiresAtEpochMillis
                .takeUnless { it == Long.MAX_VALUE }
                ?.let { java.time.Instant.ofEpochMilli(it).toString() },
            bakalari = session.bakalari,
        )
    }
}

@Serializable
data class LinkedSchoolAccountActivation(
    val account: LinkedSchoolAccount,
    @SerialName("token_payload")
    val tokenPayload: LinkedSchoolTokenPayload,
)

@Serializable
data class GradeyAccountSettingsSnapshot(
    @SerialName("active_school_account_id")
    val activeSchoolAccountID: String? = null,
    @SerialName("linked_accounts")
    val linkedAccounts: List<LinkedSchoolAccount> = emptyList(),
    @SerialName("notification_preferences")
    val notificationPreferences: NotificationPreferences = NotificationPreferences.Default,
)

@Serializable
enum class NotificationLockScreenDetail {
    @SerialName("private_summary")
    PRIVATE_SUMMARY,

    @SerialName("mark_and_subject")
    MARK_AND_SUBJECT,

    @SerialName("full_details")
    FULL_DETAILS,
}

@Serializable
data class NotificationPreferences(
    @SerialName("new_marks_enabled")
    val newMarksEnabled: Boolean = true,
    @SerialName("lock_screen_detail")
    val lockScreenDetail: NotificationLockScreenDetail = NotificationLockScreenDetail.MARK_AND_SUBJECT,
    @SerialName("quiet_hours_enabled")
    val quietHoursEnabled: Boolean = false,
    @SerialName("quiet_hours_start_minute")
    val quietHoursStartMinute: Int = 22 * 60,
    @SerialName("quiet_hours_end_minute")
    val quietHoursEndMinute: Int = 6 * 60,
    @SerialName("quiet_hours_time_zone")
    val quietHoursTimeZone: String = "Europe/Prague",
) {
    companion object {
        val Default = NotificationPreferences()
    }
}

@Serializable
data class GradeyAIStatus(
    val enabled: Boolean,
    val consentRequired: Boolean,
    val termsVersion: String,
    val dailyLimit: Int,
    val dailyUsed: Int,
    val remaining: Int,
    val resetAtEpochMillis: Long? = null,
    val tier: GradeyAIIdentityTier = GradeyAIIdentityTier.ANONYMOUS,
) {
    val canSend: Boolean get() = enabled && !consentRequired && remaining > 0
}

@Serializable
enum class GradeyAIIdentityTier {
    @SerialName("anonymous")
    ANONYMOUS,

    @SerialName("linked")
    LINKED,
}

@Serializable
data class GradeyAIConsent(
    val consented: Boolean,
    val termsVersion: String? = null,
)

@Serializable
data class StravaCZStoredSession(
    val sessionID: String,
    val serviceURL: String,
    val canteenNumber: String,
    val username: String,
    val fullName: String = "",
    val email: String? = null,
    val balance: Double = 0.0,
    val currency: String = "Kč",
    val canteenName: String? = null,
    val savedAtEpochMillis: Long = System.currentTimeMillis(),
) {
    val displayName: String get() = fullName.trim().ifEmpty { username }
}

@Serializable
data class StravaCZMenu(
    val days: List<StravaCZMenuDay> = emptyList(),
) {
    val allMeals: List<StravaCZMeal> get() = days.flatMap(StravaCZMenuDay::meals)
    val orderedMeals: List<StravaCZMeal> get() = allMeals.filter(StravaCZMeal::ordered)
}

@Serializable
data class StravaCZMenuDay(
    val id: String,
    val title: String,
    val date: String,
    val ordered: Boolean = false,
    val meals: List<StravaCZMeal> = emptyList(),
) {
    val orderedMainMeal: StravaCZMeal?
        get() = meals.firstOrNull { it.type == StravaCZMealType.MAIN && it.ordered }
}

@Serializable
enum class StravaCZMealType {
    @SerialName("soup")
    SOUP,

    @SerialName("main")
    MAIN,

    @SerialName("unknown")
    UNKNOWN,
}

@Serializable
enum class StravaCZOrderType {
    @SerialName("normal")
    NORMAL,

    @SerialName("restricted")
    RESTRICTED,

    @SerialName("optional")
    OPTIONAL,
}

@Serializable
data class StravaCZAllergen(
    val code: String,
    val name: String = "",
) {
    val displayText: String get() = name.trim().let { if (it.isEmpty()) code else "$code $it" }
}

@Serializable
data class StravaCZMeal(
    val id: Int,
    val dateKey: String,
    val type: StravaCZMealType = StravaCZMealType.UNKNOWN,
    val orderType: StravaCZOrderType = StravaCZOrderType.NORMAL,
    val typeDescription: String = "",
    val name: String,
    val forbiddenAllergens: String? = null,
    val allergens: List<StravaCZAllergen> = emptyList(),
    val ordered: Boolean = false,
    val price: Double = 0.0,
) {
    val canModify: Boolean get() = type == StravaCZMealType.MAIN && orderType != StravaCZOrderType.RESTRICTED
    val allergenText: String get() = allergens.joinToString(", ", transform = StravaCZAllergen::displayText)
}

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
    val title: String? get() = subjectAbbrev.nonBlankValue() ?: subjectName.nonBlankValue()
    val detailTitle: String? get() = subjectName.nonBlankValue() ?: subjectAbbrev.nonBlankValue()
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
    val supportTier: GradeySupportTier = GradeySupportTier.NONE,
    val auth: GradeyWearAuth? = null,
    val user: GradeyWearUser? = null,
    val timetable: GradeyWearTimetable? = null,
) {
    companion object {
        const val CURRENT_SCHEMA_VERSION = 3

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
    val title: String? get() = subjectAbbrev.nonBlankValue() ?: subjectName.nonBlankValue()
    val detailTitle: String? get() = subjectName.nonBlankValue() ?: subjectAbbrev.nonBlankValue()
    val sortEpochMillis: Long get() = startEpochMillis ?: dayStartEpochMillis
}

private fun String?.nonBlankValue(): String? = this?.trim()?.takeIf(String::isNotEmpty)

sealed interface GradeyWearLessonSelection {
    data class Lesson(val lesson: GradeyWearTimetableLesson, val timing: NextLessonWidgetTiming) : GradeyWearLessonSelection
    data object NoTimetable : GradeyWearLessonSelection
    data object NoLessons : GradeyWearLessonSelection
    data object Stale : GradeyWearLessonSelection
}

object GradeyWearSyncContract {
    const val DATA_PATH = "/gradey/sync/v2"
    const val PAYLOAD_KEY = "payload"
    const val GENERATED_AT_KEY = "generatedAtEpochMillis"
}

@Serializable
data class DemoFixture(
    val dashboard: DashboardData,
    val timetable: TimetableWeek,
    val stravaCZMenu: StravaCZMenu,
)

fun Mark.normalizedWeight(): Double = max(0.0001, weight ?: 1.0)

private fun String?.displayableSchoolName(): String? {
    val trimmed = this
        ?.replace(unicodeWhitespaceEdges, "")
        ?.takeIf(String::isNotEmpty)
        ?: return null
    val normalized = Normalizer.normalize(trimmed, Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
        .lowercase(Locale.ROOT)
        .replace(unicodeWhitespace, " ")
    return trimmed.takeUnless { normalized == "nazev skoly" }
}

// Android's ICU-backed java.util.regex rejects Java's inline `(?U)` flag. Keep the
// Unicode White_Space set explicit so loading this file cannot break session scope creation.
private const val unicodeWhitespaceCharacters =
    "\\u0009-\\u000D\\u0020\\u0085\\u00A0\\u1680" +
        "\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000"
private val unicodeWhitespace = Regex("[$unicodeWhitespaceCharacters]+")
private val unicodeWhitespaceEdges = Regex(
    "^[$unicodeWhitespaceCharacters]+|[$unicodeWhitespaceCharacters]+$",
)

object FlexibleStringSerializer : KSerializer<String> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("FlexibleString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        val jsonDecoder = decoder as? JsonDecoder ?: return decoder.decodeString()
        val value = jsonDecoder.decodeJsonElement()
        return when {
            value is JsonNull -> ""
            value !is JsonPrimitive -> throw SerializationException("Expected a string or numeric identifier")
            value.isString -> value.content
            value.booleanOrNull != null -> throw SerializationException("Boolean identifiers are not supported")
            value.longOrNull != null || value.doubleOrNull != null -> value.content
            else -> throw SerializationException("Expected a string or numeric identifier")
        }
    }

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}

@OptIn(ExperimentalSerializationApi::class)
object NullAsEmptyStringSerializer : KSerializer<String> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("NullAsEmptyString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        val jsonDecoder = decoder as? JsonDecoder ?: return decoder.decodeString()
        return when (val value = jsonDecoder.decodeJsonElement()) {
            JsonNull -> ""
            is JsonPrimitive -> value.content.takeIf { value.isString }
                ?: throw SerializationException("Expected a string or null")
            else -> throw SerializationException("Expected a string or null")
        }
    }

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}

class NullAsEmptyListSerializer<Element>(
    elementSerializer: KSerializer<Element>,
) : KSerializer<List<Element>> {
    private val delegate = ListSerializer(elementSerializer)

    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun deserialize(decoder: Decoder): List<Element> {
        val jsonDecoder = decoder as? JsonDecoder ?: return decoder.decodeSerializableValue(delegate)
        val value = jsonDecoder.decodeJsonElement()
        return if (value is JsonNull) {
            emptyList()
        } else {
            jsonDecoder.json.decodeFromJsonElement(delegate, value)
        }
    }

    override fun serialize(encoder: Encoder, value: List<Element>) {
        encoder.encodeSerializableValue(delegate, value)
    }
}

@OptIn(ExperimentalSerializationApi::class)
object FlexibleNullableDoubleSerializer : KSerializer<Double?> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("FlexibleNullableDouble", PrimitiveKind.DOUBLE)

    override fun deserialize(decoder: Decoder): Double? {
        val jsonDecoder = decoder as? JsonDecoder ?: return decoder.decodeDouble()
        val value = jsonDecoder.decodeJsonElement()
        if (value !is JsonPrimitive || value is JsonNull) return null
        return value.doubleOrNull ?: value.content.replace(',', '.').toDoubleOrNull()
    }

    override fun serialize(encoder: Encoder, value: Double?) {
        if (value == null) encoder.encodeNull() else encoder.encodeDouble(value)
    }
}

@OptIn(ExperimentalSerializationApi::class)
object FlexibleNullableClassInfoSerializer : KSerializer<ClassInfo?> {
    override val descriptor: SerialDescriptor = ClassInfo.serializer().descriptor

    override fun deserialize(decoder: Decoder): ClassInfo? {
        val jsonDecoder = decoder as? JsonDecoder
            ?: return decoder.decodeSerializableValue(ClassInfo.serializer())
        return when (val value = jsonDecoder.decodeJsonElement()) {
            JsonNull -> null
            is JsonPrimitive -> {
                if (!value.isString) throw SerializationException("Expected Class to be an object, string, or null")
                val abbrev = value.content.trim()
                if (abbrev.isEmpty()) throw SerializationException("Class string must not be blank")
                ClassInfo(id = "", abbrev = abbrev, name = abbrev)
            }
            is JsonObject -> jsonDecoder.json.decodeFromJsonElement(ClassInfo.serializer(), value)
            else -> throw SerializationException("Expected Class to be an object, string, or null")
        }
    }

    override fun serialize(encoder: Encoder, value: ClassInfo?) {
        if (value == null) {
            encoder.encodeNull()
            return
        }
        val jsonEncoder = encoder as? JsonEncoder
        if (jsonEncoder == null) {
            encoder.encodeSerializableValue(ClassInfo.serializer(), value)
        } else {
            jsonEncoder.encodeJsonElement(jsonEncoder.json.encodeToJsonElement(ClassInfo.serializer(), value))
        }
    }
}
