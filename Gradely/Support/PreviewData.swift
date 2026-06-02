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

    static let expiredSession = StoredSession(
        accessToken: "expired-access",
        refreshToken: "mock-refresh",
        tokenType: "Bearer",
        expiresAt: Date(timeIntervalSince1970: 0),
        baseURL: URL(string: "https://demo.bakalari.cz/")!
    )
}
