import Foundation

/// Demo friends for `-uiTestingMockAPI -uiTestingFriends`.
extension PreviewData {
    static let friendAnnaID = UUID(uuidString: "6F1B1C1E-0000-4000-8000-00000000A001")!
    static let friendTomasID = UUID(uuidString: "6F1B1C1E-0000-4000-8000-00000000A002")!

    static var friends: [Friend] {
        [
            Friend(id: friendAnnaID, name: "Anna", source: .imported(fileName: "rozvrh-2B.pdf"), addedAt: Date()),
            Friend(
                id: friendTomasID, name: "Tomáš",
                source: .publicClass(
                    schoolURL: URL(string: "https://demo.gradely.app/")!, schoolName: "Gymnázium Gradey",
                    classID: "B2", className: "2.B", groups: nil
                ),
                addedAt: Date()
            )
        ]
    }

    /// A timetable as the PDF importer would read it.
    static var friendDraft: ImportedTimetableDraft {
        var draft = ImportedTimetableDraft.blank
        let week: [[(String, String, String, String)]] = [
            [("Ma", "E225", "Smi", ""), ("ČJL", "E225", "Gra", ""), ("AJ", "E307", "Hek", "AJ1"), ("AJ", "E302", "Kal", "AJ2"), ("Fy", "E225", "Gie", ""), ("Bi", "E225", "Keb", "")],
            [("D", "E225", "Štu", ""), ("Ma", "E225", "Smi", ""), ("TV", "TVH", "Gaš", "Dív"), ("TV", "TVS", "Rej", "Chl"), ("Geo", "E225", "Kal", "")],
            [("ZSV", "E225", "Gra", ""), ("Inf", "E302", "Gaš", ""), ("ČJL", "E225", "Gra", ""), ("Ch", "E225", "Iza", "")],
            [("NJ", "K409", "Lit", ""), ("AJ", "E307", "Hek", "AJ1"), ("AJ", "E225", "Kal", "AJ2"), ("MG", "E225", "Pav", ""), ("VV", "E225", "Hur", ""), ("VV", "E225", "Hur", "")],
            [("Ma", "E225", "Smi", ""), ("Bi", "E225", "Keb", ""), ("Ch", "E225", "Iza", "")]
        ]
        for (dayIndex, lessons) in week.enumerated() {
            var hour = 1
            var previousGroup = ""
            for lesson in lessons {
                // A second group in the same hour shares it.
                if !lesson.3.isEmpty, !previousGroup.isEmpty, lesson.3 != previousGroup { hour -= 1 }
                draft.lessons.append(ImportedTimetableDraft.Lesson(
                    dayOfWeek: dayIndex + 1, hourID: hour,
                    subject: lesson.0, room: lesson.1, teacher: lesson.2, group: lesson.3
                ))
                previousGroup = lesson.3
                hour += 1
            }
        }
        return draft
    }
}
