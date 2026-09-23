import Foundation

enum PlannerEventProjection {
    static func events(from items: [PlannerItem], scope: SchoolDataScope?, subjectID: String? = nil) -> [SchoolEvent] {
        items.compactMap { item -> SchoolEvent? in
            guard !item.isCompleted, item.deletedAt == nil, let date = item.orderingDate else { return nil }
            // Conflicting references cannot safely be attributed to either school.
            if let subjectScope = item.subject?.scope, let lessonScope = item.lesson?.scope,
               subjectScope != lessonScope { return nil }
            let itemScope = item.subject?.scope ?? item.lesson?.scope
            guard itemScope == nil || itemScope == scope else { return nil }
            if let subjectID {
                // Unscoped personal entries remain visible on Today but are never matched by name.
                guard itemScope == scope, item.subject?.id == subjectID else { return nil }
            }
            guard let kind = SchoolEvent.Kind(rawValue: item.type.rawValue) else { return nil }
            return SchoolEvent(
                id: item.id, scope: itemScope, subjectID: item.subject?.id,
                subjectName: item.subject?.displayName, title: item.title, kind: kind,
                date: date, hasTime: item.dueDate != nil ? item.dueHasTime : item.lesson?.start != nil,
                timeZoneIdentifier: item.timeZoneIdentifier, updatedAt: item.updatedAt
            )
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
