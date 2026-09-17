package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.AbsencePerSubject
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.Absence
import com.bukovinafilip.gradey.model.ClassInfo
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.DemoFixture
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMenuDay
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.bukovinafilip.gradey.model.TimetableAtom
import com.bukovinafilip.gradey.model.TimetableDayDTO
import com.bukovinafilip.gradey.model.TimetableEntity
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableResponse
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import java.time.LocalDate

object DemoData {
    val math = Subject(
        subjectInfo = SubjectInfo(id = "math", abbrev = "M", name = "Matematika"),
        averageText = "1.78",
        marks = listOf(
            Mark(markDate = "2026-05-05", caption = "Písemka", theme = "Lineární funkce", markText = "2", weight = 3.0, subjectID = "math", id = "math-1"),
            Mark(markDate = "2026-05-20", caption = "Aktivita", theme = "Rovnice", markText = "1+", weight = 1.0, subjectID = "math", id = "math-2"),
            Mark(markDate = "2026-06-18", caption = "Test", theme = "Funkce", markText = "1-", weight = 2.0, subjectID = "math", id = "math-3"),
        ),
    )

    val czech = Subject(
        subjectInfo = SubjectInfo(id = "czech", abbrev = "ČJ", name = "Český jazyk"),
        averageText = "2.30",
        marks = listOf(
            Mark(markDate = "2026-05-29", caption = "Diktát", theme = "Vyjmenovaná slova", markText = "2+", weight = 2.0, subjectID = "czech", id = "cz-1"),
        ),
    )

    val marksResponse = MarksResponse(subjects = listOf(math, czech))

    val absenceResponse = AbsenceResponse(
        percentageThreshold = 25.0,
        absences = listOf(
            Absence(date = "2026-02-10T00:00:00+01:00", ok = 1),
            Absence(date = "2026-03-02T00:00:00+01:00", ok = 6),
            Absence(date = "2026-04-07T00:00:00+02:00", ok = 2, late = 1),
            Absence(date = "2026-05-04T00:00:00+02:00", ok = 6),
            Absence(date = "2026-06-03T00:00:00+02:00", unsolved = 6),
        ),
        absencesPerSubject = listOf(
            AbsencePerSubject(subjectName = "Český jazyk", lessonsCount = 38, base = 7),
            AbsencePerSubject(subjectName = "Matematika", lessonsCount = 42, base = 4),
        ),
    )

    val user = UserResponse(
        fullName = "Alex Novak",
        schoolName = "Gradey Demo School",
        userClass = ClassInfo(id = "3a", abbrev = "3.A", name = "3.A"),
        userUID = "demo-user",
    )

    private val timetableHours = listOf(
        TimetableHour("1", "1", "08:00", "08:45"),
        TimetableHour("2", "2", "08:55", "09:40"),
        TimetableHour("3", "3", "09:50", "10:35"),
        TimetableHour("4", "4", "10:45", "11:30"),
    )

    private val timetableSubjects = listOf(
        TimetableEntity(id = "math", abbrev = "M", name = "Matematika"),
        TimetableEntity(id = "czech", abbrev = "ČJ", name = "Český jazyk"),
        TimetableEntity(id = "biology", abbrev = "Bi", name = "Biologie"),
        TimetableEntity(id = "english", abbrev = "AJ", name = "Angličtina"),
    )

    private val timetableTeachers = listOf(
        TimetableEntity(id = "jan-novak", abbrev = "JN", name = "Jan Novák"),
        TimetableEntity(id = "eva-svobodova", abbrev = "ES", name = "Eva Svobodová"),
        TimetableEntity(id = "petr-dvorak", abbrev = "PD", name = "Petr Dvořák"),
    )

    private val timetableRooms = listOf(
        TimetableEntity(id = "room-12", abbrev = "12", name = "Učebna 12"),
    )

    /**
     * A Bakaláři-shaped demo response for any requested school week. Keeping the
     * fixture in transport form means the demo account exercises the same mapper
     * and hour ordering as a live account.
     */
    fun timetableResponse(weekContaining: String): TimetableResponse {
        val monday = demoMonday(weekContaining)

        fun atom(
            hour: String,
            subject: String,
            teacher: String,
            theme: String? = null,
            hasHomework: Boolean = false,
        ) = TimetableAtom(
            hourID = hour,
            subjectID = subject,
            teacherID = teacher,
            roomID = "room-12",
            theme = theme,
            homeworkIDs = if (hasHomework) listOf("homework-$hour") else emptyList(),
        )

        val lessonsByDay = listOf(
            listOf(
                atom("1", "math", "jan-novak", "Lineární rovnice"),
                atom("2", "czech", "eva-svobodova", "Vyjmenovaná slova"),
                atom("3", "biology", "petr-dvorak"),
                atom("4", "english", "eva-svobodova"),
            ),
            listOf(
                atom("1", "english", "eva-svobodova", "Past simple", hasHomework = true),
                atom("2", "math", "jan-novak", "Soustavy rovnic"),
                atom("3", "biology", "petr-dvorak", "Lidské tělo"),
                atom("4", "czech", "eva-svobodova", "Větné členy"),
            ),
            listOf(
                atom("1", "czech", "eva-svobodova", "Sloh", hasHomework = true),
                atom("2", "english", "eva-svobodova", "Travel"),
                atom("3", "math", "jan-novak", "Funkce"),
                atom("4", "biology", "petr-dvorak", "Ekosystémy"),
            ),
            listOf(
                atom("1", "math", "jan-novak", "Opakování", hasHomework = true),
                atom("2", "biology", "petr-dvorak", "Genetika"),
                atom("3", "english", "eva-svobodova", "Conversation"),
                atom("4", "czech", "eva-svobodova", "Literatura"),
            ),
            listOf(
                atom("1", "biology", "petr-dvorak", "Laboratorní práce", hasHomework = true),
                atom("2", "czech", "eva-svobodova", "Čtenářská dílna"),
                atom("3", "math", "jan-novak", "Geometrie"),
                atom("4", "english", "eva-svobodova", "Revision"),
            ),
        )

        val dayNames = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
        return TimetableResponse(
            hours = timetableHours,
            days = lessonsByDay.mapIndexed { index, atoms ->
                TimetableDayDTO(
                    atoms = atoms,
                    dayOfWeek = index + 1,
                    date = monday.plusDays(index.toLong()).toString(),
                    dayDescription = dayNames[index],
                    dayType = if (index in 1..3) "notice" else "",
                )
            },
            subjects = timetableSubjects,
            teachers = timetableTeachers,
            rooms = timetableRooms,
        )
    }

    fun timetableFor(weekContaining: String): TimetableWeek {
        val monday = demoMonday(weekContaining)
        return TimetableMapper.makeWeek(
            response = timetableResponse(monday.toString()),
            weekStart = monday.toString(),
            today = TimetableDates.todayString(),
        )
    }

    private fun demoMonday(weekContaining: String): LocalDate =
        TimetableDates.monday(
            runCatching { LocalDate.parse(weekContaining) }
                .getOrDefault(LocalDate.of(2026, 7, 6)),
        )

    val timetable = timetableFor("2026-07-06")

    val stravaMenu = StravaCZMenu(
        days = listOf(
            StravaCZMenuDay(
                id = "2026-07-06",
                title = "Monday",
                date = "2026-07-06",
                meals = listOf(
                    StravaCZMeal(id = 1, dateKey = "2026-07-06", name = "Chicken with rice", ordered = true),
                    StravaCZMeal(id = 2, dateKey = "2026-07-06", name = "Vegetable pasta", ordered = false),
                ),
            ),
        ),
    )

    val fixture = DemoFixture(
        dashboard = DashboardData(marksResponse = marksResponse, absencesPerSubject = absenceResponse.absencesPerSubject, user = user),
        timetable = timetable,
        stravaCZMenu = stravaMenu,
    )
}
