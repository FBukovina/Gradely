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
                    date = "2026-08-24",
                    atoms = listOf(
                        TimetableAtom(hourID = "1", subjectID = " math ", teacherID = "teacher", roomID = "room", groupIDs = listOf("group")),
                        TimetableAtom(hourID = "2", subjectID = "biology", change = TimetableChange("Canceled", "Teacher absent")),
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
        assertThat(day.lessons.map { it.hour.id }).containsExactly("2", "1", "1", "9").inOrder()
        assertThat(day.lessons.map { it.id }.distinct()).hasSize(4)
        assertThat(day.lessons.first().changeKind).isEqualTo(LessonChangeKind.CANCELED)
        assertThat(day.lessons.first().changeDescription).isEqualTo("Teacher absent")
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
}
