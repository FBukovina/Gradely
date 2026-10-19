import Foundation

/// Fixtures shaped like vavruska.info's real output, dated relative to now so
/// the mock always has a lesson this week, a prodloužená soon and a live sale.
extension PreviewData {
    static let vavruskaCourse = VavruskaStoredCourse(
        courseCode: "M04",
        scheduleSummary: "neděle 16.30 - 18.10",
        calendarURL: VavruskaLinks.calendarURL(hash: "00000000000000000000000000000000"),
        pdfURL: VavruskaLinks.pdfURL(hash: "00000000000000000000000000000000"),
        connectedAt: Date(timeIntervalSince1970: 1_780_000_000)
    )

    /// Start of the current Monday-based week in Prague, offset by `days`.
    private static func vavruskaDay(_ days: Int, now: Date) -> DateComponents {
        var calendar = VavruskaDateInference.pragueCalendar
        calendar.firstWeekday = 2
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let date = calendar.date(byAdding: .day, value: days, to: weekStart) ?? now
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    private static func vavruskaStamp(_ day: DateComponents, _ hour: Int, _ minute: Int) -> String {
        String(format: "%04d%02d%02dT%02d%02d00", day.year ?? 0, day.month ?? 0, day.day ?? 0, hour, minute)
    }

    static func vavruskaICS(now: Date = Date()) -> String {
        let events: [(uid: Int, day: Int, start: (Int, Int), end: (Int, Int), summary: String, venue: String, address: String)] = [
            (1, -7, (16, 30), (18, 10), "Vyučovací lekce - TŠ Vavruška", "Obecní dům", "náměstí Republiky 5, Praha 1"),
            (2, 2, (19, 0), (20, 40), "Vyučovací lekce - TŠ Vavruška", "Obecní dům", "náměstí Republiky 5, Praha 1"),
            (3, 6, (16, 30), (18, 10), "Vyučovací lekce - TŠ Vavruška", "Obecní dům", "náměstí Republiky 5, Praha 1"),
            (4, 13, (11, 30), (14, 0), "Lekce stolování - TŠ Vavruška", "Hotel Pyramida", "Bělohorská 24, Praha 6"),
            (5, 20, (16, 0), (19, 0), "Prodloužená lekce - TŠ Vavruška", "Obecní dům", "náměstí Republiky 5, Praha 1"),
            (6, 27, (16, 30), (18, 10), "Latino lekce - TŠ Vavruška", "Obecní dům", "náměstí Republiky 5, Praha 1"),
            (7, 111, (14, 30), (18, 0), "Závěrečný Květinový ples - TŠ Vavruška", "Lucerna", "Štěpánská 61, Praha 1")
        ]
        var lines = ["BEGIN:VCALENDAR", "PRODID:-//Vavruska.info//Kalendář//CS", "VERSION:2.0",
                     "BEGIN:VTIMEZONE", "TZID:Europe/Prague", "BEGIN:STANDARD", "DTSTART:19701025T030000", "END:STANDARD", "END:VTIMEZONE"]
        for event in events {
            let day = vavruskaDay(event.day, now: now)
            lines += [
                "BEGIN:VEVENT",
                "UID:preview-\(event.uid)@vavruska.info",
                "SUMMARY:\(event.summary)",
                "DESCRIPTION: \(event.venue)",
                "LOCATION:\(event.address)",
                "DTSTART;TZID=Europe/Prague:\(vavruskaStamp(day, event.start.0, event.start.1))",
                "DTEND;TZID=Europe/Prague:\(vavruskaStamp(day, event.end.0, event.end.1))",
                "END:VEVENT"
            ]
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\n")
    }

    static let vavruskaNoticeBoardHTML = """
    <div class="article__body">
        <p class="article__meta">Aktualizováno: 6. 10. 2026</p>
        <h4>Podzimní prodloužené</h4>
        <p>První větší akcí bude "podzimní prodloužená". Všechny informace <a href="/akce/plesy/prodlouzena-mladez">najdete zde.</a>
        Prodej vstupenek bude probíhat <a href="/vstupenky">on-line zde</a>.</p>
        <hr class="article-divider">
        <h4>Oblečení do tanečních</h4>
        <p>Všichni naši klienti získávají slevy:<br>
        <strong>Slečny:</strong> 10% slevu na šaty.<br>
        <strong>Všichni:</strong> 10% slevu na obuv od <a href="https://www.hellerdance.cz" target="_blank">Heller dance</a>.</p>
    </div>
    <div class="values-strip"></div>
    """

    private static let vavruskaCzechMonths = [
        "ledna", "února", "března", "dubna", "května", "června",
        "července", "srpna", "září", "října", "listopadu", "prosince"
    ]

    static func vavruskaEventPageHTML(now: Date = Date()) -> String {
        let event = vavruskaDay(20, now: now)
        let otherEvent = vavruskaDay(21, now: now)
        let sale = Calendar.current.dateComponents(in: VavruskaDateInference.prague, from: now.addingTimeInterval(2 * 24 * 60 * 60))
        func eventText(_ day: DateComponents) -> String {
            "\(day.day ?? 1). \(vavruskaCzechMonths[(day.month ?? 1) - 1])"
        }
        return """
        <h1 class="page-head__title">Prodloužená kurzů pro mládež</h1>
        <ul>
            <li><span>v neděli \(eventText(event)) od 16:00 do 19:00</span> v <a href="/tanecni-saly/obecni-dum">Obecním domě</a> pro kurz <span>M04</span>.<br>Prodej vstupenek začíná \(sale.day ?? 1). \(sale.month ?? 1). v 18.00.</li>
            <li><span>v pondělí \(eventText(otherEvent)) od 16:30 do 19:30</span> v <a href="/tanecni-saly/lucerna">paláci Lucerna</a> pro kurzy <span>M13 a M14</span>.<br>Prodej vstupenek začíná 12. 10. ve 12.00.</li>
        </ul>
        <div class="values-strip"></div>
        """
    }

    static func vavruskaTicketListingHTML(now: Date = Date()) -> String {
        let event = vavruskaDay(20, now: now)
        return """
        <a href="/vstupenky/prodlouzena-\(event.day ?? 1)-\(event.month ?? 1)-\(event.year ?? 2026)-od-1600/#obsah">Přejít k zakoupení vstupenky</a>
        """
    }
}
