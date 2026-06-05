import Foundation

enum PreviewData {
    static let mathMarks = [
        Mark(
            markDate: "2026-05-31T09:30:00+02:00",
            caption: "Písemná práce",
            theme: "Lineární rovnice",
            markText: "1-",
            type: "written",
            typeNote: "Písemka",
            weight: 3,
            subjectID: "math",
            isNew: true,
            id: "math-1"
        ),
        Mark(
            markDate: "2026-05-17T12:00:00+02:00",
            caption: "Ústní zkoušení",
            theme: nil,
            markText: "2",
            type: "oral",
            typeNote: "Ústní",
            weight: 1,
            subjectID: "math",
            id: "math-2"
        ),
        Mark(
            markDate: "2026-05-03T10:00:00+02:00",
            caption: "Aktivita",
            theme: nil,
            markText: "8",
            type: "points",
            typeNote: "Body",
            weight: nil,
            subjectID: "math",
            isPoints: true,
            id: "math-3",
            pointsText: "8",
            maxPoints: 10
        )
    ]

    static let czechMarks = [
        Mark(
            markDate: "2026-05-29T08:00:00+02:00",
            caption: "Diktát",
            theme: "Vyjmenovaná slova",
            markText: "2+",
            type: "written",
            typeNote: "Diktát",
            weight: 2,
            subjectID: "czech",
            id: "czech-1"
        )
    ]

    static let subjects = [
        Subject(
            marks: mathMarks,
            subjectInfo: SubjectInfo(id: "math", abbrev: "M", name: "Matematika"),
            averageText: "1,78",
            markPredictionEnabled: true
        ),
        Subject(
            marks: czechMarks,
            subjectInfo: SubjectInfo(id: "czech", abbrev: "ČJ", name: "Český jazyk"),
            averageText: nil,
            markPredictionEnabled: true
        )
    ]

    static let marksResponse = MarksResponse(subjects: subjects)

    static let absenceResponse = AbsenceResponse(
        percentageThreshold: 25,
        absences: [],
        absencesPerSubject: [
            AbsencePerSubject(
                subjectName: "Matematika",
                lessonsCount: 42,
                base: 4,
                late: 1,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            ),
            AbsencePerSubject(
                subjectName: "Český jazyk",
                lessonsCount: 38,
                base: 7,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            )
        ]
    )

    static let userResponse = UserResponse(
        userUID: "mock-user",
        fullName: "Filip Bukovina",
        userClass: ClassInfo(id: "class-1", abbrev: "4.A", name: "4.A"),
        schoolName: "Demo škola",
        userType: "student",
        userTypeText: "Student",
        studyYear: 2026
    )

    static let schoolDirectorySchools = [
        SchoolDirectorySchool(
            id: "demo",
            name: "Demo Gymnazium",
            town: "Praha",
            schoolURL: "https://demo.bakalari.cz"
        ),
        SchoolDirectorySchool(
            id: "future",
            name: "Future School",
            town: "Brno",
            schoolURL: "https://future.bakalari.cz"
        ),
        SchoolDirectorySchool(
            id: "eden",
            name: "Zakladni skola Eden",
            town: "Praha",
            schoolURL: "https://zseden.bakalari.cz/bakaweb/"
        )
    ]

    // MARK: - Timetable

    static let timetableHours = [
        TimetableHour(id: 1, caption: "1", beginTime: "8:00", endTime: "8:45"),
        TimetableHour(id: 2, caption: "2", beginTime: "8:55", endTime: "9:40"),
        TimetableHour(id: 3, caption: "3", beginTime: "9:50", endTime: "10:35"),
        TimetableHour(id: 4, caption: "4", beginTime: "10:45", endTime: "11:30")
    ]

    static let timetableSubjects = [
        TimetableEntity(id: "math", abbrev: "M", name: "Matematika"),
        TimetableEntity(id: "czech", abbrev: "ČJ", name: "Český jazyk"),
        TimetableEntity(id: "bio", abbrev: "Bi", name: "Biologie"),
        TimetableEntity(id: "eng", abbrev: "AJ", name: "Angličtina"),
        TimetableEntity(id: "pe", abbrev: "Tv", name: "Tělesná výchova")
    ]

    static let timetableTeachers = [
        TimetableEntity(id: "t-novak", abbrev: "No", name: "Jan Novák"),
        TimetableEntity(id: "t-svobodova", abbrev: "Sv", name: "Eva Svobodová"),
        TimetableEntity(id: "t-dvorak", abbrev: "Dv", name: "Petr Dvořák")
    ]

    static let timetableRooms = [
        TimetableEntity(id: "r-12", abbrev: "12", name: "Učebna 12"),
        TimetableEntity(id: "r-aula", abbrev: "Aula", name: "Aula"),
        TimetableEntity(id: "r-tv", abbrev: "TV", name: "Tělocvična")
    ]

    static let timetableDays: [TimetableDayDTO] = [
        TimetableDayDTO(
            atoms: [
                timetableAtom(1, "math", "t-novak", "r-12", theme: "Lineární rovnice"),
                timetableAtom(2, "czech", "t-svobodova", "r-12", theme: "Vyjmenovaná slova"),
                timetableAtom(3, "bio", "t-dvorak", "r-12"),
                timetableAtom(4, "eng", "t-svobodova", "r-12")
            ],
            dayOfWeek: 1,
            date: timetableDayDate(1)
        ),
        TimetableDayDTO(
            atoms: [
                timetableAtom(1, "eng", "t-svobodova", "r-12"),
                timetableAtom(2, "math", "t-novak", "r-12", change: TimetableChange(
                    changeType: "Canceled",
                    description: "Hodina odpadá – učitel na školení."
                )),
                timetableAtom(3, "pe", "t-dvorak", "r-tv"),
                timetableAtom(4, "czech", "t-svobodova", "r-12")
            ],
            dayOfWeek: 2,
            date: timetableDayDate(2)
        ),
        TimetableDayDTO(
            atoms: [
                timetableAtom(1, "bio", "t-dvorak", "r-aula", change: TimetableChange(
                    changeType: "RoomChanged",
                    description: "Změna učebny: Aula."
                )),
                timetableAtom(2, "math", "t-novak", "r-12"),
                timetableAtom(3, "eng", "t-svobodova", "r-12")
            ],
            dayOfWeek: 3,
            date: timetableDayDate(3)
        ),
        TimetableDayDTO(
            atoms: [
                timetableAtom(1, "czech", "t-svobodova", "r-12"),
                timetableAtom(2, "math", "t-novak", "r-12", theme: "Goniometrie"),
                timetableAtom(3, "pe", "t-novak", "r-tv", change: TimetableChange(
                    changeType: "Substitution",
                    description: "Supluje Novák za Dvořáka."
                )),
                timetableAtom(4, "bio", "t-dvorak", "r-12")
            ],
            dayOfWeek: 4,
            date: timetableDayDate(4)
        ),
        TimetableDayDTO(
            atoms: [
                timetableAtom(1, "math", "t-novak", "r-12"),
                timetableAtom(2, "eng", "t-svobodova", "r-12"),
                timetableAtom(3, "czech", "t-svobodova", "r-12")
            ],
            dayOfWeek: 5,
            date: timetableDayDate(5)
        )
    ]

    static let timetableResponse = TimetableResponse(
        hours: timetableHours,
        days: timetableDays,
        subjects: timetableSubjects,
        teachers: timetableTeachers,
        rooms: timetableRooms
    )

    private static let timetableWeekMonday = TimetableDates.monday(of: Date())

    private static func timetableDayDate(_ dayOfWeek: Int) -> String {
        let date = TimetableDates.weekCalendar.date(byAdding: .day, value: dayOfWeek - 1, to: timetableWeekMonday)
            ?? timetableWeekMonday
        return TimetableDates.apiDateString(date)
    }

    private static func timetableAtom(
        _ hour: Int,
        _ subject: String,
        _ teacher: String,
        _ room: String,
        theme: String? = nil,
        change: TimetableChange? = nil
    ) -> TimetableAtom {
        TimetableAtom(
            hourID: hour,
            subjectID: subject,
            teacherID: teacher,
            roomID: room,
            change: change,
            theme: theme
        )
    }

    static let expiredSession = StoredSession(
        accessToken: "expired-access",
        refreshToken: "mock-refresh",
        tokenType: "Bearer",
        expiresAt: Date(timeIntervalSince1970: 0),
        baseURL: URL(string: "https://demo.bakalari.cz/")!
    )
}
