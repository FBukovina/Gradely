import Foundation

struct LoginResponse: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let apiVersion: String?
    let appVersion: String?
    let userID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case apiVersion = "bak:ApiVersion"
        case appVersion = "bak:AppVersion"
        case userID = "bak:UserId"
    }
}

struct UserResponse: Codable, Equatable {
    let userUID: String
    let fullName: String
    let userClass: ClassInfo?
    let schoolName: String?
    let userType: String
    let userTypeText: String
    let studyYear: Int?

    enum CodingKeys: String, CodingKey {
        case userUID = "UserUID"
        case fullName = "FullName"
        case userClass = "Class"
        case schoolOrganizationName = "SchoolOrganizationName"
        case schoolName = "SchoolName"
        case userType = "UserType"
        case userTypeText = "UserTypeText"
        case studyYear = "StudyYear"
    }

    init(
        userUID: String,
        fullName: String,
        userClass: ClassInfo?,
        schoolName: String?,
        userType: String,
        userTypeText: String,
        studyYear: Int?
    ) {
        self.userUID = userUID
        self.fullName = fullName
        self.userClass = userClass
        self.schoolName = schoolName
        self.userType = userType
        self.userTypeText = userTypeText
        self.studyYear = studyYear
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userUID = try container.decode(String.self, forKey: .userUID)
        fullName = try container.decode(String.self, forKey: .fullName)
        userClass = try container.decodeIfPresent(ClassInfo.self, forKey: .userClass)
        schoolName = try container.decodeIfPresent(String.self, forKey: .schoolOrganizationName)
            ?? container.decodeIfPresent(String.self, forKey: .schoolName)
        userType = try container.decode(String.self, forKey: .userType)
        userTypeText = try container.decode(String.self, forKey: .userTypeText)
        studyYear = try container.decodeIfPresent(Int.self, forKey: .studyYear)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userUID, forKey: .userUID)
        try container.encode(fullName, forKey: .fullName)
        try container.encodeIfPresent(userClass, forKey: .userClass)
        try container.encodeIfPresent(schoolName, forKey: .schoolOrganizationName)
        try container.encode(userType, forKey: .userType)
        try container.encode(userTypeText, forKey: .userTypeText)
        try container.encodeIfPresent(studyYear, forKey: .studyYear)
    }
}

struct ClassInfo: Codable, Equatable, Hashable {
    let id: String
    let abbrev: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }
}

struct MarksResponse: Codable, Equatable {
    let subjects: [Subject]

    enum CodingKeys: String, CodingKey {
        case subjects = "Subjects"
    }

    init(subjects: [Subject]) {
        self.subjects = subjects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subjects = try container.decodeIfPresent([Subject].self, forKey: .subjects) ?? []
    }
}

struct Subject: Codable, Equatable, Hashable, Identifiable {
    let marks: [Mark]
    let subjectInfo: SubjectInfo
    let averageText: String?
    let temporaryMark: String?
    let subjectNote: String?
    let temporaryMarkNote: String?
    let pointsOnly: Bool
    let markPredictionEnabled: Bool

    var id: String { subjectInfo.id }
    var trimmedName: String { subjectInfo.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedAbbrev: String { subjectInfo.abbrev.trimmingCharacters(in: .whitespacesAndNewlines) }

    enum CodingKeys: String, CodingKey {
        case marks = "Marks"
        case subjectInfo = "Subject"
        case averageText = "AverageText"
        case temporaryMark = "TemporaryMark"
        case subjectNote = "SubjectNote"
        case temporaryMarkNote = "TemporaryMarkNote"
        case pointsOnly = "PointsOnly"
        case markPredictionEnabled = "MarkPredictionEnabled"
    }

    init(
        marks: [Mark],
        subjectInfo: SubjectInfo,
        averageText: String?,
        temporaryMark: String? = nil,
        subjectNote: String? = nil,
        temporaryMarkNote: String? = nil,
        pointsOnly: Bool = false,
        markPredictionEnabled: Bool = false
    ) {
        self.marks = marks
        self.subjectInfo = subjectInfo
        self.averageText = averageText
        self.temporaryMark = temporaryMark
        self.subjectNote = subjectNote
        self.temporaryMarkNote = temporaryMarkNote
        self.pointsOnly = pointsOnly
        self.markPredictionEnabled = markPredictionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marks = try container.decodeIfPresent([Mark].self, forKey: .marks) ?? []
        subjectInfo = try container.decode(SubjectInfo.self, forKey: .subjectInfo)
        averageText = try container.decodeIfPresent(String.self, forKey: .averageText)
        temporaryMark = try container.decodeIfPresent(String.self, forKey: .temporaryMark)
        subjectNote = try container.decodeIfPresent(String.self, forKey: .subjectNote)
        temporaryMarkNote = try container.decodeIfPresent(String.self, forKey: .temporaryMarkNote)
        pointsOnly = try container.decodeIfPresent(Bool.self, forKey: .pointsOnly) ?? false
        markPredictionEnabled = try container.decodeIfPresent(Bool.self, forKey: .markPredictionEnabled) ?? false
    }
}

struct SubjectInfo: Codable, Equatable, Hashable {
    let id: String
    let abbrev: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }
}

struct Mark: Codable, Equatable, Hashable, Identifiable {
    let markDate: String
    let editDate: String?
    let caption: String?
    let theme: String?
    let markText: String
    let teacherID: String?
    let type: String
    let typeNote: String?
    let weight: Int?
    let subjectID: String
    let isNew: Bool
    let isPoints: Bool
    let calculatedMarkText: String?
    let classRankText: String?
    let id: String
    let pointsText: String?
    let maxPoints: Int?
    let confirmedWhen: String?
    let confirmedBy: String?
    let markConfirmationState: String?

    var displayText: String {
        if isPoints, let pointsText, !pointsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let maxPoints {
            return "\(markText)/\(maxPoints)"
        }
        return markText
    }

    var displayCaption: String {
        if let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return caption.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let theme, !theme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return theme.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(localized: "mark.untitled")
    }

    var shouldShowTheme: Bool {
        guard let caption, let theme else { return false }
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedCaption.isEmpty && !trimmedTheme.isEmpty && trimmedCaption != trimmedTheme
    }

    enum CodingKeys: String, CodingKey {
        case markDate = "MarkDate"
        case editDate = "EditDate"
        case caption = "Caption"
        case theme = "Theme"
        case markText = "MarkText"
        case teacherID = "TeacherId"
        case type = "Type"
        case typeNote = "TypeNote"
        case weight = "Weight"
        case subjectID = "SubjectId"
        case isNew = "IsNew"
        case isPoints = "IsPoints"
        case calculatedMarkText = "CalculatedMarkText"
        case classRankText = "ClassRankText"
        case id = "Id"
        case pointsText = "PointsText"
        case maxPoints = "MaxPoints"
        case confirmedWhen = "ConfirmedWhen"
        case confirmedBy = "ConfirmedBy"
        case markConfirmationState = "MarkConfirmationState"
    }

    init(
        markDate: String,
        editDate: String? = nil,
        caption: String? = nil,
        theme: String? = nil,
        markText: String,
        teacherID: String? = nil,
        type: String,
        typeNote: String? = nil,
        weight: Int? = nil,
        subjectID: String,
        isNew: Bool = false,
        isPoints: Bool = false,
        calculatedMarkText: String? = nil,
        classRankText: String? = nil,
        id: String,
        pointsText: String? = nil,
        maxPoints: Int? = nil,
        confirmedWhen: String? = nil,
        confirmedBy: String? = nil,
        markConfirmationState: String? = nil
    ) {
        self.markDate = markDate
        self.editDate = editDate
        self.caption = caption
        self.theme = theme
        self.markText = markText
        self.teacherID = teacherID
        self.type = type
        self.typeNote = typeNote
        self.weight = weight
        self.subjectID = subjectID
        self.isNew = isNew
        self.isPoints = isPoints
        self.calculatedMarkText = calculatedMarkText
        self.classRankText = classRankText
        self.id = id
        self.pointsText = pointsText
        self.maxPoints = maxPoints
        self.confirmedWhen = confirmedWhen
        self.confirmedBy = confirmedBy
        self.markConfirmationState = markConfirmationState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markDate = try container.decodeIfPresent(String.self, forKey: .markDate) ?? ""
        editDate = try container.decodeIfPresent(String.self, forKey: .editDate)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
        markText = try container.decodeIfPresent(String.self, forKey: .markText) ?? ""
        teacherID = try container.decodeIfPresent(String.self, forKey: .teacherID)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        typeNote = try container.decodeIfPresent(String.self, forKey: .typeNote)
        weight = try container.decodeIfPresent(Int.self, forKey: .weight)
        subjectID = try container.decodeIfPresent(String.self, forKey: .subjectID) ?? ""
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        isPoints = try container.decodeIfPresent(Bool.self, forKey: .isPoints) ?? false
        calculatedMarkText = try container.decodeIfPresent(String.self, forKey: .calculatedMarkText)
        classRankText = try container.decodeIfPresent(String.self, forKey: .classRankText)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        pointsText = try container.decodeIfPresent(String.self, forKey: .pointsText)
        maxPoints = try container.decodeIfPresent(Int.self, forKey: .maxPoints)
        confirmedWhen = try container.decodeIfPresent(String.self, forKey: .confirmedWhen)
        confirmedBy = try container.decodeIfPresent(String.self, forKey: .confirmedBy)
        markConfirmationState = try container.decodeIfPresent(String.self, forKey: .markConfirmationState)
    }
}

struct AbsenceResponse: Codable, Equatable {
    let percentageThreshold: Double
    let absences: [AbsenceDay]
    let absencesPerSubject: [AbsencePerSubject]

    enum CodingKeys: String, CodingKey {
        case percentageThreshold = "PercentageThreshold"
        case absences = "Absences"
        case absencesPerSubject = "AbsencesPerSubject"
    }

    init(percentageThreshold: Double, absences: [AbsenceDay], absencesPerSubject: [AbsencePerSubject]) {
        self.percentageThreshold = percentageThreshold
        self.absences = absences
        self.absencesPerSubject = absencesPerSubject
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        percentageThreshold = try container.decodeIfPresent(Double.self, forKey: .percentageThreshold) ?? 0
        absences = try container.decodeIfPresent([AbsenceDay].self, forKey: .absences) ?? []
        absencesPerSubject = try container.decodeIfPresent([AbsencePerSubject].self, forKey: .absencesPerSubject) ?? []
    }
}

struct AbsenceDay: Codable, Equatable, Hashable, Identifiable {
    let date: String
    let unsolved: Int
    let ok: Int
    let missed: Int
    let late: Int
    let soon: Int
    let school: Int
    let distanceTeaching: Int

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case unsolved = "Unsolved"
        case ok = "Ok"
        case missed = "Missed"
        case late = "Late"
        case soon = "Soon"
        case school = "School"
        case distanceTeaching = "DistanceTeaching"
    }
}

struct AbsencePerSubject: Codable, Equatable, Hashable, Identifiable {
    let subjectName: String
    let lessonsCount: Int
    let base: Int
    let late: Int
    let soon: Int
    let school: Int
    let distanceTeaching: Int

    var id: String { subjectName }

    var absencePercentage: Double {
        guard lessonsCount > 0 else { return 0 }
        return Double(base) / Double(lessonsCount) * 100
    }

    enum CodingKeys: String, CodingKey {
        case subjectName = "SubjectName"
        case lessonsCount = "LessonsCount"
        case base = "Base"
        case late = "Late"
        case soon = "Soon"
        case school = "School"
        case distanceTeaching = "DistanceTeaching"
    }
}
