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
        absences: [
            AbsenceDay(
                date: "2026-02-10T00:00:00+01:00",
                unsolved: 0,
                ok: 1,
                missed: 0,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            ),
            AbsenceDay(
                date: "2026-03-02T00:00:00+01:00",
                unsolved: 0,
                ok: 6,
                missed: 0,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            ),
            AbsenceDay(
                date: "2026-04-07T00:00:00+02:00",
                unsolved: 0,
                ok: 2,
                missed: 0,
                late: 1,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            ),
            AbsenceDay(
                date: "2026-05-04T00:00:00+02:00",
                unsolved: 0,
                ok: 6,
                missed: 0,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            ),
            AbsenceDay(
                date: "2026-06-03T00:00:00+02:00",
                unsolved: 6,
                ok: 0,
                missed: 0,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            )
        ],
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

    static let absenceResponseWithoutSubjectRows = AbsenceResponse(
        percentageThreshold: absenceResponse.percentageThreshold,
        absences: absenceResponse.absences,
        absencesPerSubject: []
    )

    static let largeSubjectAbsenceResponseWithoutSubjectRows = AbsenceResponse(
        percentageThreshold: absenceResponse.percentageThreshold,
        absences: [
            AbsenceDay(
                date: "2026-02-02T00:00:00+01:00",
                unsolved: 0,
                ok: 48,
                missed: 0,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            )
        ],
        absencesPerSubject: []
    )

    static let manualSubjectAbsenceResponseWithoutSubjectRows = AbsenceResponse(
        percentageThreshold: absenceResponse.percentageThreshold,
        absences: [
            AbsenceDay(
                date: "2026-02-02T00:00:00+01:00",
                unsolved: 0,
                ok: 1,
                missed: 0,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            )
        ],
        absencesPerSubject: []
    )

    static let userResponse = UserResponse(
        userUID: "mock-user",
        fullName: "Alex Novak",
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

    static let largeSubjectTimetableResponse: TimetableResponse = {
        let subjectCount = 48
        let hours = (1...subjectCount).map {
            TimetableHour(id: $0, caption: "\($0)", beginTime: "8:00", endTime: "8:45")
        }
        let subjects = (0..<subjectCount).map {
            TimetableEntity(id: "ui-large-subject-\($0)", abbrev: "S\($0)", name: "Large Subject \($0)")
        }
        let atoms = (0..<subjectCount).map {
            TimetableAtom(hourID: $0 + 1, subjectID: "ui-large-subject-\($0)")
        }

        return TimetableResponse(
            hours: hours,
            days: [
                TimetableDayDTO(
                    atoms: atoms,
                    dayOfWeek: 1,
                    date: "2026-02-02T00:00:00+01:00"
                )
            ],
            subjects: subjects,
            teachers: timetableTeachers,
            rooms: timetableRooms
        )
    }()

    static let manualSubjectTimetableResponse = TimetableResponse(
        hours: [
            TimetableHour(id: 1, caption: "1", beginTime: "8:00", endTime: "8:45"),
            TimetableHour(id: 2, caption: "2", beginTime: "8:55", endTime: "9:40")
        ],
        days: [
            TimetableDayDTO(
                atoms: [
                    TimetableAtom(hourID: 1, subjectID: "math"),
                    TimetableAtom(hourID: 2, subjectID: "tev")
                ],
                dayOfWeek: 1,
                date: "2026-02-02T00:00:00+01:00"
            )
        ],
        subjects: [
            TimetableEntity(id: "math", abbrev: "M", name: "Matematika"),
            TimetableEntity(id: "tev", abbrev: "TV", name: "Tělesná výchova")
        ],
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

    static let stravaCZLoginResponse = StravaCZLoginResponse(
        sessionID: "MOCK_STRAVACZ_SID",
        serviceURL: "https://wss5.strava.cz/WSStravne5_15/WSStravne5.svc",
        canteenNumber: "1234",
        username: "student",
        user: StravaCZLoginUser(
            fullName: "Student One",
            email: "student@example.com",
            balance: 100,
            id: "student",
            currency: "Kč",
            canteenName: "Demo jídelna"
        )
    )

    static let stravaCZSession = StravaCZStoredSession(
        sessionID: "MOCK_STRAVACZ_SID",
        serviceURL: "https://wss5.strava.cz/WSStravne5_15/WSStravne5.svc",
        canteenNumber: "1234",
        username: "student",
        fullName: "Student One",
        email: "student@example.com",
        balance: 100,
        currency: "Kč",
        canteenName: "Demo jídelna",
        savedAt: Date()
    )

    static let stravaCZMenuResponse: StravaCZMenuResponse = {
        let json = """
        {
          "table0": [
            {
              "id": 0,
              "datum": "15.09.2025",
              "druh_popis": "Polévka",
              "delsiPopis": "Vývar se zeleninou",
              "nazev": "Vývar se zeleninou",
              "zakazaneAlergeny": null,
              "alergeny": [["01", "Obiloviny"], ["09", "Celer"]],
              "omezeniObj": {"den": ""},
              "pocet": 0,
              "veta": "75",
              "cena": "0"
            },
            {
              "id": 1,
              "datum": "15.09.2025",
              "druh_popis": "Oběd 1",
              "delsiPopis": "Rajská omáčka s těstovinami",
              "nazev": "Rajská omáčka s těstovinami",
              "zakazaneAlergeny": null,
              "alergeny": [["01", "Obiloviny"], ["07", "Mléko"]],
              "omezeniObj": {"den": ""},
              "pocet": 0,
              "veta": "1",
              "cena": "40.00"
            },
            {
              "id": 2,
              "datum": "15.09.2025",
              "druh_popis": "Oběd 2",
              "delsiPopis": "Zeleninové rizoto se sýrem",
              "nazev": "Zeleninové rizoto se sýrem",
              "zakazaneAlergeny": null,
              "alergeny": [["07", "Mléko"]],
              "omezeniObj": {"den": ""},
              "pocet": 0,
              "veta": "2",
              "cena": "42.00"
            }
          ],
          "table1": [
            {
              "id": 3,
              "datum": "16-09.2025",
              "druh_popis": "Oběd 1",
              "delsiPopis": "Kuřecí řízek, bramborová kaše",
              "nazev": "Kuřecí řízek, bramborová kaše",
              "zakazaneAlergeny": null,
              "alergeny": [["01", "Obiloviny"], ["03", "Vejce"], ["07", "Mléko"]],
              "omezeniObj": {"den": "CO"},
              "pocet": 0,
              "veta": "3",
              "cena": "45.00"
            },
            {
              "id": 4,
              "datum": "16-09.2025",
              "druh_popis": "Oběd 2",
              "delsiPopis": "Těstovinový salát",
              "nazev": "Těstovinový salát",
              "zakazaneAlergeny": null,
              "alergeny": [["01", "Obiloviny"]],
              "omezeniObj": {"den": "T"},
              "pocet": 0,
              "veta": "4",
              "cena": "35.00"
            }
          ]
        }
        """
        return try! JSONDecoder().decode(StravaCZMenuResponse.self, from: Data(json.utf8))
    }()

    static let stravaCZMenuAfterOrderResponse: StravaCZMenuResponse = {
        let json = """
        {
          "table0": [
            {
              "id": 0,
              "datum": "15.09.2025",
              "druh_popis": "Polévka",
              "delsiPopis": "Vývar se zeleninou",
              "nazev": "Vývar se zeleninou",
              "zakazaneAlergeny": null,
              "alergeny": [["01", "Obiloviny"], ["09", "Celer"]],
              "omezeniObj": {"den": ""},
              "pocet": 0,
              "veta": "75",
              "cena": "0"
            },
            {
              "id": 1,
              "datum": "15.09.2025",
              "druh_popis": "Oběd 1",
              "delsiPopis": "Rajská omáčka s těstovinami",
              "nazev": "Rajská omáčka s těstovinami",
              "zakazaneAlergeny": null,
              "alergeny": [["01", "Obiloviny"], ["07", "Mléko"]],
              "omezeniObj": {"den": ""},
              "pocet": 1,
              "veta": "1",
              "cena": "40.00"
            },
            {
              "id": 2,
              "datum": "15.09.2025",
              "druh_popis": "Oběd 2",
              "delsiPopis": "Zeleninové rizoto se sýrem",
              "nazev": "Zeleninové rizoto se sýrem",
              "zakazaneAlergeny": null,
              "alergeny": [["07", "Mléko"]],
              "omezeniObj": {"den": ""},
              "pocet": 0,
              "veta": "2",
              "cena": "42.00"
            }
          ]
        }
        """
        return try! JSONDecoder().decode(StravaCZMenuResponse.self, from: Data(json.utf8))
    }()

    static let gradeHistoryResponse: GradeHistoryResponse = {
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let events = [
            GradeHistoryEvent(
                id: "history-math-0a",
                linkedAccountID: "bakalari-demo.bakalari.cz-default",
                provider: .bakalari,
                subjectID: "math",
                subjectAbbrev: "M",
                subjectName: "Matematika",
                averageValue: 2.4,
                markCount: 1,
                averageDelta: nil,
                markCountDelta: 0,
                eventType: .baseline,
                capturedAt: calendar.date(byAdding: .day, value: -120, to: now) ?? now
            ),
            GradeHistoryEvent(
                id: "history-math-0b",
                linkedAccountID: "bakalari-demo.bakalari.cz-default",
                provider: .bakalari,
                subjectID: "math",
                subjectAbbrev: "M",
                subjectName: "Matematika",
                averageValue: 2.15,
                markCount: 1,
                averageDelta: -0.25,
                markCountDelta: 0,
                eventType: .changed,
                capturedAt: calendar.date(byAdding: .day, value: -90, to: now) ?? now
            ),
            GradeHistoryEvent(
                id: "history-math-0c",
                linkedAccountID: "bakalari-demo.bakalari.cz-default",
                provider: .bakalari,
                subjectID: "math",
                subjectAbbrev: "M",
                subjectName: "Matematika",
                averageValue: 2.3,
                markCount: 2,
                averageDelta: 0.15,
                markCountDelta: 1,
                eventType: .changed,
                capturedAt: calendar.date(byAdding: .day, value: -60, to: now) ?? now
            ),
            GradeHistoryEvent(
                id: "history-math-0d",
                linkedAccountID: "bakalari-demo.bakalari.cz-default",
                provider: .bakalari,
                subjectID: "math",
                subjectAbbrev: "M",
                subjectName: "Matematika",
                averageValue: 2.0,
                markCount: 2,
                averageDelta: -0.3,
                markCountDelta: 0,
                eventType: .changed,
                capturedAt: calendar.date(byAdding: .day, value: -20, to: now) ?? now
            ),
            GradeHistoryEvent(
                id: "history-math-1",
                linkedAccountID: "bakalari-demo.bakalari.cz-default",
                provider: .bakalari,
                subjectID: "math",
                subjectAbbrev: "M",
                subjectName: "Matematika",
                averageValue: 1.95,
                markCount: 2,
                averageDelta: nil,
                markCountDelta: 0,
                eventType: .baseline,
                capturedAt: calendar.date(byAdding: .day, value: -45, to: now) ?? now
            ),
            GradeHistoryEvent(
                id: "history-math-2",
                linkedAccountID: "bakalari-demo.bakalari.cz-default",
                provider: .bakalari,
                subjectID: "math",
                subjectAbbrev: "M",
                subjectName: "Matematika",
                averageValue: 1.78,
                markCount: 3,
                averageDelta: -0.17,
                markCountDelta: 1,
                eventType: .changed,
                capturedAt: calendar.date(byAdding: .day, value: -7, to: now) ?? now
            ),
            GradeHistoryEvent(
                id: "history-czech-1",
                linkedAccountID: "bakalari-demo.bakalari.cz-default",
                provider: .bakalari,
                subjectID: "czech",
                subjectAbbrev: "ČJ",
                subjectName: "Český jazyk",
                averageValue: 1.6,
                markCount: 1,
                averageDelta: nil,
                markCountDelta: 0,
                eventType: .baseline,
                capturedAt: calendar.date(byAdding: .day, value: -45, to: now) ?? now
            ),
            GradeHistoryEvent(
                id: "history-czech-2",
                linkedAccountID: "bakalari-demo.bakalari.cz-default",
                provider: .bakalari,
                subjectID: "czech",
                subjectAbbrev: "ČJ",
                subjectName: "Český jazyk",
                averageValue: 2.0,
                markCount: 2,
                averageDelta: 0.4,
                markCountDelta: 1,
                eventType: .changed,
                capturedAt: calendar.date(byAdding: .day, value: -4, to: now) ?? now
            )
        ]
        return GradeHistoryResponse(events: events, recentNewMarkEvents: [])
    }()

    static var subjectGradeTrends: [SubjectGradeTrend] {
        gradeHistoryResponse.trends
    }

    /// Absence fixture spanning every risk level (threshold 25 %):
    /// safe ~9.5 %, watch ~18.4 %, high ~23.7 %, over limit 27.5 %.
    static let riskAbsenceResponse = AbsenceResponse(
        percentageThreshold: 25,
        absences: absenceResponse.absences,
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
            ),
            AbsencePerSubject(
                subjectName: "Fyzika",
                lessonsCount: 38,
                base: 9,
                late: 0,
                soon: 1,
                school: 0,
                distanceTeaching: 0
            ),
            AbsencePerSubject(
                subjectName: "Tělesná výchova",
                lessonsCount: 40,
                base: 11,
                late: 0,
                soon: 0,
                school: 2,
                distanceTeaching: 0
            )
        ]
    )

    /// Subject graded purely in points — the detail chart must hide for it.
    static let pointsOnlySubject = Subject(
        marks: [
            Mark(
                markDate: "2026-05-20T10:00:00+02:00",
                caption: "Projekt",
                theme: nil,
                markText: "18",
                type: "points",
                typeNote: "Body",
                weight: nil,
                subjectID: "informatics",
                isPoints: true,
                id: "informatics-1",
                pointsText: "18",
                maxPoints: 20
            ),
            Mark(
                markDate: "2026-04-12T10:00:00+02:00",
                caption: "Aktivita",
                theme: nil,
                markText: "9",
                type: "points",
                typeNote: "Body",
                weight: nil,
                subjectID: "informatics",
                isPoints: true,
                id: "informatics-2",
                pointsText: "9",
                maxPoints: 10
            )
        ],
        subjectInfo: SubjectInfo(id: "informatics", abbrev: "INF", name: "Informatika"),
        averageText: nil,
        pointsOnly: true,
        markPredictionEnabled: false
    )
}
