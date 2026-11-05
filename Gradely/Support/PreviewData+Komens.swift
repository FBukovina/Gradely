import Foundation

/// Demo Komens messages and report cards for `-uiTestingMockAPI` and the demo account.
extension PreviewData {
    static var komensSnapshot: KomensSnapshot {
        func sent(daysAgo: Int, hour: Int) -> String {
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date())) ?? Date()
            let date = calendar.date(byAdding: .hour, value: hour, to: day) ?? day
            return ISO8601DateFormatter().string(from: date)
        }
        let classTeacher = KomensSenderDTO(id: "t-svobodova", type: "teacher", name: "Eva Svobodová")
        let office = KomensSenderDTO(id: "office", type: "administrator", name: "Ředitelství školy")
        return KomensSnapshot(
            received: [
                KomensMessageDTO(
                    id: "komens-trip",
                    title: "Exkurze do Národního technického muzea",
                    text: "<div>Dobrý den,</div><div>ve čtvrtek jedeme na exkurzi do <b>Národního technického muzea</b>. Sraz je v 7:45 před školou, návrat kolem 13:00.</div><ul><li>vstupné 120 Kč</li><li>svačina a pití</li></ul><div>Program najdete v příloze.</div><div>E. Svobodová</div>",
                    sentDate: sent(daysAgo: 0, hour: 8), sender: classTeacher,
                    attachments: [SchoolAttachmentDTO(id: "komens-att-trip", name: "Program exkurze.txt", type: "text/plain", size: 186)],
                    read: false
                ),
                KomensMessageDTO(
                    id: "komens-meeting",
                    title: "Třídní schůzky",
                    text: "<p>Třídní schůzky budou v úterý od 17:00 v učebně 12. Konzultace s vyučujícími od 17:30.</p>",
                    sentDate: sent(daysAgo: 2, hour: 15), sender: office,
                    read: false
                ),
                KomensMessageDTO(
                    id: "komens-math",
                    title: "Opravná písemka z matematiky",
                    text: "Opravnou písemku z lineárních rovnic můžete psát v pondělí 7. hodinu.<br>Kdo chce, napište mi předem.",
                    sentDate: sent(daysAgo: 6, hour: 11),
                    sender: KomensSenderDTO(id: "t-novak", type: "teacher", name: "Jan Novák")
                ),
                KomensMessageDTO(
                    id: "komens-excuse",
                    title: nil,
                    text: "Omluvenka: nemoc 12.–13. 10. Absence byla omluvena.",
                    sentDate: sent(daysAgo: 21, hour: 9), sender: classTeacher
                )
            ],
            noticeboard: [
                KomensMessageDTO(
                    id: "komens-board-holidays",
                    title: "Podzimní prázdniny",
                    text: "<div>Podzimní prázdniny jsou ve čtvrtek a pátek 29. a 30. 10. Školní jídelna bude zavřená.</div>",
                    sentDate: sent(daysAgo: 12, hour: 10), sender: office
                ),
                KomensMessageDTO(
                    id: "komens-board-library",
                    title: "Nová otevírací doba knihovny",
                    text: "<div>Školní knihovna má nově otevřeno každý den od 7:30 do 15:00. Více na <a href=\"https://www.example.com/knihovna\">webu školy</a>.</div>",
                    sentDate: sent(daysAgo: 30, hour: 12), sender: office
                )
            ]
        )
    }

    static let komensAttachmentData = Data(
        "Exkurze do Národního technického muzea\n\n7:45 sraz před školou\n8:30 prohlídka expozice Doprava\n10:30 dílna Jak funguje elektřina\n12:15 odjezd zpět\n".utf8
    )

    static let finalMarksResponse: FinalMarksResponse = {
        let subjects = [
            FinalMarkSubjectDTO(id: "conduct", abbrev: "Chv", name: "Chování"),
            FinalMarkSubjectDTO(id: "czech", abbrev: "ČJ", name: "Český jazyk"),
            FinalMarkSubjectDTO(id: "eng", abbrev: "AJ", name: "Angličtina"),
            FinalMarkSubjectDTO(id: "math", abbrev: "M", name: "Matematika"),
            FinalMarkSubjectDTO(id: "bio", abbrev: "Bi", name: "Biologie"),
            FinalMarkSubjectDTO(id: "pe", abbrev: "Tv", name: "Tělesná výchova")
        ]
        func term(_ year: String, _ semester: String, _ marks: [String], average: Double, absent: Double, date: String) -> CertificateTermDTO {
            CertificateTermDTO(
                finalMarks: zip(subjects, marks).map { FinalMarkDTO(subjectID: $0.id, markText: $1) },
                subjects: subjects,
                schoolYear: year,
                semester: semester,
                achievementText: average <= 1.5 && !marks.contains(where: { ["3", "4", "5"].contains($0) }) ? "prospěl s vyznamenáním" : "prospěl",
                marksAverage: average,
                absentHours: absent,
                notExcusedHours: 0,
                certificateDate: date
            )
        }
        return FinalMarksResponse(terms: [
            term("2024/25", "1", ["1", "2", "1", "2", "1", "1"], average: 1.4, absent: 31, date: "2025-01-30T00:00:00+01:00"),
            term("2024/25", "2", ["1", "2", "2", "2", "1", "1"], average: 1.6, absent: 18, date: "2025-06-27T00:00:00+02:00"),
            term("2025/26", "1", ["1", "1", "2", "3", "1", "1"], average: 1.6, absent: 42, date: "2026-01-30T00:00:00+01:00"),
            term("2025/26", "2", ["1", "2", "1", "2", "1", "1"], average: 1.4, absent: 22, date: "2026-06-26T00:00:00+02:00")
        ])
    }()
}
