import Foundation

// MARK: - Bakaláři payload

/// `GET api/3/marks/final`: every report card since the student started.
struct FinalMarksResponse: Codable, Equatable {
    static let cachePrefix = "report-card-cache"

    var terms: [CertificateTermDTO]

    enum CodingKeys: String, CodingKey {
        case terms = "CertificateTerms"
    }

    init(terms: [CertificateTermDTO]) {
        self.terms = terms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        terms = try container.decodeIfPresent([CertificateTermDTO].self, forKey: .terms) ?? []
    }
}

struct CertificateTermDTO: Codable, Equatable {
    let finalMarks: [FinalMarkDTO]
    let subjects: [FinalMarkSubjectDTO]
    /// "2025/26".
    let schoolYear: String?
    /// "1" or "2".
    let semester: String?
    let closed: Bool
    let achievementText: String?
    let marksAverage: Double?
    let absentHours: Double?
    let notExcusedHours: Double?
    let certificateDate: String?

    enum CodingKeys: String, CodingKey {
        case finalMarks = "FinalMarks"
        case subjects = "Subjects"
        case schoolYear = "SchoolYear"
        case semester = "Semester"
        case closed = "Closed"
        case achievementText = "AchievementText"
        case marksAverage = "MarksAverage"
        case absentHours = "AbsentHours"
        case notExcusedHours = "NotExcusedHours"
        case certificateDate = "CertificateDate"
    }

    init(
        finalMarks: [FinalMarkDTO],
        subjects: [FinalMarkSubjectDTO],
        schoolYear: String?,
        semester: String?,
        closed: Bool = true,
        achievementText: String? = nil,
        marksAverage: Double? = nil,
        absentHours: Double? = nil,
        notExcusedHours: Double? = nil,
        certificateDate: String? = nil
    ) {
        self.finalMarks = finalMarks
        self.subjects = subjects
        self.schoolYear = schoolYear
        self.semester = semester
        self.closed = closed
        self.achievementText = achievementText
        self.marksAverage = marksAverage
        self.absentHours = absentHours
        self.notExcusedHours = notExcusedHours
        self.certificateDate = certificateDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finalMarks = try container.decodeIfPresent([FinalMarkDTO].self, forKey: .finalMarks) ?? []
        subjects = try container.decodeIfPresent([FinalMarkSubjectDTO].self, forKey: .subjects) ?? []
        schoolYear = container.lossyString(forKey: .schoolYear)
        semester = container.lossyString(forKey: .semester)
        closed = (try? container.decodeIfPresent(Bool.self, forKey: .closed)) ?? true
        achievementText = try? container.decodeIfPresent(String.self, forKey: .achievementText)
        marksAverage = container.lossyDouble(forKey: .marksAverage)
        absentHours = container.lossyDouble(forKey: .absentHours)
        notExcusedHours = container.lossyDouble(forKey: .notExcusedHours)
        certificateDate = try? container.decodeIfPresent(String.self, forKey: .certificateDate)
    }
}

struct FinalMarkDTO: Codable, Equatable {
    let id: String?
    let subjectID: String
    let markText: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case subjectID = "SubjectId"
        case markText = "MarkText"
    }

    init(id: String? = nil, subjectID: String, markText: String) {
        self.id = id
        self.subjectID = subjectID
        self.markText = markText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lossyString(forKey: .id)
        subjectID = container.lossyString(forKey: .subjectID) ?? ""
        markText = (try? container.decodeIfPresent(String.self, forKey: .markText)) ?? ""
    }
}

struct FinalMarkSubjectDTO: Codable, Equatable {
    let id: String
    let abbrev: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case abbrev = "Abbrev"
        case name = "Name"
    }

    init(id: String, abbrev: String?, name: String?) {
        self.id = id
        self.abbrev = abbrev
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lossyString(forKey: .id) ?? ""
        abbrev = try? container.decodeIfPresent(String.self, forKey: .abbrev)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
    }
}

private extension KeyedDecodingContainer {
    /// Bakaláři versions differ on numbers versus strings for ids and terms.
    func lossyString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    func lossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        return (try? decodeIfPresent(String.self, forKey: key)).flatMap { GradeMath.parseAverageText($0) }
    }
}

// MARK: - App model

/// The school year and semester a day falls in: September to January is the first.
struct ReportCardPeriod: Equatable, Hashable {
    let startYear: Int
    let semester: Int

    init(startYear: Int, semester: Int) {
        self.startYear = startYear
        self.semester = semester
    }

    init(containing date: Date) {
        let parts = Homework.schoolCalendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 2026
        let month = parts.month ?? 9
        semester = month >= 9 || month == 1 ? 1 : 2
        startYear = month >= 9 ? year : year - 1
    }

    /// "2026/27", the way Bakaláři writes it.
    var schoolYear: String {
        "\(startYear)/" + String(format: "%02d", (startYear + 1) % 100)
    }
}

/// One report card: a semester and the marks written on it.
struct ReportCardTerm: Identifiable, Hashable {
    let schoolYear: String
    let semester: String
    let isClosed: Bool
    let achievementText: String?
    let average: Double?
    let absentHours: Double?
    let unexcusedHours: Double?
    let issuedOn: Date?
    /// In the school's subject order, as printed on the report card.
    let marks: [ReportCardMark]

    var id: String { schoolYear + "-" + semester }

    init(_ dto: CertificateTermDTO) {
        schoolYear = dto.schoolYear?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        semester = dto.semester?.trimmingCharacters(in: CharacterSet(charactersIn: " .")) ?? ""
        isClosed = dto.closed
        achievementText = dto.achievementText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        average = dto.marksAverage.flatMap { $0 > 0 ? $0 : nil }
        absentHours = dto.absentHours
        unexcusedHours = dto.notExcusedHours
        issuedOn = Homework.schoolDate(dto.certificateDate)
        let marksBySubject = Dictionary(dto.finalMarks.map { ($0.subjectID, $0) }, uniquingKeysWith: { first, _ in first })
        var marks = dto.subjects.compactMap { subject -> ReportCardMark? in
            guard let mark = marksBySubject[subject.id],
                  let text = mark.markText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
            return ReportCardMark(
                subjectID: subject.id,
                subjectName: subject.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? subject.id,
                subjectAbbrev: subject.abbrev?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                markText: text
            )
        }
        let listed = Set(marks.map(\.subjectID))
        for mark in dto.finalMarks where !listed.contains(mark.subjectID) {
            guard let text = mark.markText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { continue }
            marks.append(ReportCardMark(subjectID: mark.subjectID, subjectName: mark.subjectID, subjectAbbrev: nil, markText: text))
        }
        self.marks = marks
    }

    func matches(_ period: ReportCardPeriod) -> Bool {
        schoolYear == period.schoolYear && semester == String(period.semester)
    }

    /// The mark for one of this semester's subjects, by id and then by name.
    func mark(for subject: Subject) -> ReportCardMark? {
        marks.first { $0.subjectID == subject.id }
            ?? marks.first { $0.subjectAbbrev?.caseInsensitiveCompare(subject.trimmedAbbrev) == .orderedSame && !subject.trimmedAbbrev.isEmpty }
            ?? marks.first { $0.subjectName.caseInsensitiveCompare(subject.trimmedName) == .orderedSame }
    }

    /// Newest first.
    static func sorted(_ terms: [ReportCardTerm]) -> [ReportCardTerm] {
        terms.sorted { ($0.schoolYear, $0.semester) > ($1.schoolYear, $1.semester) }
    }
}

struct ReportCardMark: Identifiable, Hashable {
    let subjectID: String
    let subjectName: String
    let subjectAbbrev: String?
    /// Usually "1"–"5", but also verbal results such as "uvolněn".
    let markText: String

    var id: String { subjectID }
}

/// What this semester's report card would show if it closed today.
struct ReportCardEstimate: Identifiable, Equatable {
    struct Borderline: Equatable {
        /// The neighbouring mark the average is close to.
        let mark: Int
        /// How far the average is from the line between the two marks.
        let distance: Double
    }

    /// Averages this close to the line between two marks count as borderline.
    static let borderlineMargin = 0.1

    let subjectID: String
    let subjectName: String
    let average: Double?
    /// A mark the teacher already wrote in Bakaláři for this semester; it wins over the estimate.
    let writtenMarkText: String?
    let estimatedMark: Int?
    let borderline: Borderline?

    var id: String { subjectID }

    /// The mark the row shows: the written one if there is one.
    var markValue: Double? {
        if let writtenMarkText { return GradeMath.parseMarkValue(writtenMarkText) }
        return estimatedMark.map(Double.init)
    }

    /// The report card's subjects in school order, with the written mark or an estimate.
    static func estimates(
        subjects: [Subject],
        prepared: [String: PreparedGradeCalculation],
        written: ReportCardTerm?
    ) -> [ReportCardEstimate] {
        subjects.map { subject in
            let average = prepared[subject.id]?.displayAverage ?? GradeMath.subjectAverage(subject)
            let writtenMark = written?.mark(for: subject)?.markText
            let estimated = average.map { mark(for: $0) }
            var nearby: Borderline?
            if writtenMark == nil, let average, let estimated {
                nearby = Self.borderline(for: average, mark: estimated)
            }
            return ReportCardEstimate(
                subjectID: subject.id,
                subjectName: subject.trimmedName,
                average: average,
                writtenMarkText: writtenMark,
                estimatedMark: estimated,
                borderline: nearby
            )
        }
    }

    /// The report-card average: the mean of the marks, not of the subject averages.
    static func average(of estimates: [ReportCardEstimate]) -> Double? {
        let values = estimates.compactMap(\.markValue)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// x.50 still rounds to the better mark, matching `GradeMath.band`.
    static func mark(for average: Double) -> Int {
        min(5, max(1, Int((average - 0.5).rounded(.up))))
    }

    static func borderline(for average: Double, mark: Int) -> Borderline? {
        var candidates: [Borderline] = []
        if mark < 5 { candidates.append(Borderline(mark: mark + 1, distance: Double(mark) + 0.5 - average)) }
        if mark > 1 { candidates.append(Borderline(mark: mark - 1, distance: average - (Double(mark) - 0.5))) }
        return candidates
            .filter { $0.distance >= 0 && $0.distance <= borderlineMargin + 0.000_1 }
            .min { $0.distance < $1.distance }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
