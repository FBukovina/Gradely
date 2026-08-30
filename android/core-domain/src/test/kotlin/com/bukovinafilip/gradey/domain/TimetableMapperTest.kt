package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.TimetableAtom
import com.bukovinafilip.gradey.model.TimetableChange
import com.bukovinafilip.gradey.model.TimetableDayDTO
import com.bukovinafilip.gradey.model.TimetableEntity
import com.bukovinafilip.gradey.model.TimetableGroup
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableResponse
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class TimetableMapperTest {
    @Test
    fun mapsRawReferencesChangesAndDuplicateAtomsWithoutLosingLessons() {
        val response = TimetableResponse(
            hours = listOf(
                TimetableHour("2", "2", "08:55", "09:40"),
                TimetableHour("1", "1", "08:00", "08:45"),
            ),
            days = listOf(
                TimetableDayDTO(
                    dayOfWeek = 1,
                    date = "2026-08-24T00:00:00+02:00",
                    atoms = listOf(
                        TimetableAtom(hourID = "1", subjectID = " math ", teacherID = "teacher", roomID = "room", groupIDs = listOf("group")),
                        TimetableAtom(
                            hourID = "2",
                            subjectID = "biology",
                            change = TimetableChange(
                                changeType = "Canceled",
                                description = "Teacher absent",
                                changeSubject = "Biology",
                                hours = "2nd lesson",
                                typeName = "Cancellation",
                            ),
                        ),
                        TimetableAtom(hourID = "1", subjectID = " math "),
                        TimetableAtom(hourID = "9", subjectID = "missing"),
                    ),
                ),
            ),
            subjects = listOf(
                TimetableEntity(" math ", " M ", " Mathematics "),
                TimetableEntity("biology", "Bi", "Biology"),
            ),
            teachers = listOf(TimetableEntity("teacher", " JS ", " Jane Smith ")),
            rooms = listOf(TimetableEntity("room", " 12 ", " Room 12 ")),
            groups = listOf(TimetableGroup("group", " A ", "Group A")),
        )

        val week = TimetableMapper.makeWeek(response, "2026-08-24", today = "2026-08-24")
        val day = week.days.single()

        assertThat(day.isToday).isTrue()
        assertThat(day.date).isEqualTo("2026-08-24")
        assertThat(day.lessons.map { it.hour.id }).containsExactly("2", "1", "1", "9").inOrder()
        assertThat(day.lessons.map { it.id }.distinct()).hasSize(4)
        assertThat(day.lessons.first().changeKind).isEqualTo(LessonChangeKind.CANCELED)
        assertThat(day.lessons.first().changeDescription).isEqualTo("Teacher absent")
        assertThat(day.lessons.first().change?.changeSubject).isEqualTo("Biology")
        assertThat(day.lessons.first().change?.hours).isEqualTo("2nd lesson")
        assertThat(day.lessons.first().change?.typeName).isEqualTo("Cancellation")
        assertThat(day.lessons[1].subjectName).isEqualTo("Mathematics")
        assertThat(day.lessons[1].teacherTitle).isEqualTo("JS")
        assertThat(day.lessons[1].roomTitle).isEqualTo("12")
        assertThat(day.lessons[1].groups).containsExactly("A")
        assertThat(day.lessons.last().title).isEqualTo("Lesson")
    }

    @Test
    fun emptyDateAndMissingHourProduceSafeFallbacks() {
        val response = TimetableResponse(
            days = listOf(TimetableDayDTO(dayOfWeek = 3, atoms = listOf(TimetableAtom(hourID = "7")))),
        )

        val day = TimetableMapper.makeWeek(response, "2026-08-24", today = "2026-08-26").days.single()

        assertThat(day.id).isEqualTo("dow-3")
        assertThat(day.date).isNull()
        assertThat(day.isToday).isFalse()
        assertThat(day.lessons.single().hour.caption).isEqualTo("7")
    }

    @Test
    fun parsesSupportedDatesRejectsMalformedValuesAndClassifiesEveryChangeVariant() {
        assertThat(TimetableDates.parseApiDate("2026-10-28T00:00:00+01:00"))
            .isEqualTo(java.time.LocalDate.of(2026, 10, 28))
        assertThat(TimetableDates.parseApiDate("2026-10-28")).isEqualTo(java.time.LocalDate.of(2026, 10, 28))
        assertThat(TimetableDates.parseApiDate("not-a-date")).isNull()
        assertThat(TimetableDates.parseApiDate("")).isNull()

        assertThat(LessonChangeKind.fromApi("removed")).isEqualTo(LessonChangeKind.CANCELED)
        assertThat(LessonChangeKind.fromApi("Cancelled")).isEqualTo(LessonChangeKind.CANCELED)
        assertThat(LessonChangeKind.fromApi("RoomChanged")).isEqualTo(LessonChangeKind.ROOM_CHANGED)
        assertThat(LessonChangeKind.fromApi("Added")).isEqualTo(LessonChangeKind.ADDED)
        assertThat(LessonChangeKind.fromApi("Substitution")).isEqualTo(LessonChangeKind.SUBSTITUTION)
        assertThat(LessonChangeKind.fromApi("server-specific-change")).isEqualTo(LessonChangeKind.SUBSTITUTION)
        assertThat(LessonChangeKind.fromApi(null)).isEqualTo(LessonChangeKind.NONE)
    }

    @Test
    fun unusualDayNumberAndMalformedDateRemainSafeAndDoNotBecomeToday() {
        val day = TimetableMapper.makeWeek(
            TimetableResponse(
                days = listOf(
                    TimetableDayDTO(
                        dayOfWeek = 9,
                        date = "malformed",
                        atoms = listOf(TimetableAtom(hourID = "10", subjectID = "unknown")),
                    ),
                ),
            ),
            weekStart = "2026-08-24",
            today = "2026-08-24",
        ).days.single()

        assertThat(day.dayOfWeek).isEqualTo(9)
        assertThat(day.date).isNull()
        assertThat(day.isToday).isFalse()
        assertThat(day.lessons.single().title).isEqualTo("Lesson")
    }
}
