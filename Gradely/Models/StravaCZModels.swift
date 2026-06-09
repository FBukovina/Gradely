import Foundation

enum StravaCZMealType: String, Codable, Equatable {
    case soup
    case main
    case unknown

    var localizedTitle: String {
        switch self {
        case .soup:
            String(localized: "stravacz.mealType.soup")
        case .main:
            String(localized: "stravacz.mealType.main")
        case .unknown:
            String(localized: "stravacz.mealType.unknown")
        }
    }
}

enum StravaCZOrderType: String, Codable, Equatable {
    case normal
    case restricted
    case optional

    var localizedTitle: String {
        switch self {
        case .normal:
            String(localized: "stravacz.orderType.normal")
        case .restricted:
            String(localized: "stravacz.orderType.restricted")
        case .optional:
            String(localized: "stravacz.orderType.optional")
        }
    }
}

struct StravaCZStoredSession: Codable, Equatable {
    var sessionID: String
    var serviceURL: String
    var canteenNumber: String
    var username: String
    var fullName: String
    var email: String?
    var balance: Double
    var currency: String
    var canteenName: String?
    var savedAt: Date

    var displayName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? username : fullName
    }

    var formattedBalance: String {
        StravaCZFormatters.balance(balance, currency: currency)
    }
}

struct StravaCZLoginResponse: Decodable, Equatable {
    let sessionID: String
    let serviceURL: String
    let canteenNumber: String
    let username: String
    let user: StravaCZLoginUser

    enum CodingKeys: String, CodingKey {
        case sessionID = "sid"
        case serviceURL = "s5url"
        case canteenNumber = "cislo"
        case username = "jmeno"
        case user = "uzivatel"
    }
}

struct StravaCZLoginUser: Decodable, Equatable {
    let fullName: String
    let email: String?
    let balance: Double
    let id: String
    let currency: String
    let canteenName: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "jmeno"
        case email
        case balance = "konto"
        case id
        case currency = "mena"
        case canteenName = "nazevJidelny"
    }

    init(
        fullName: String,
        email: String?,
        balance: Double,
        id: String,
        currency: String,
        canteenName: String?
    ) {
        self.fullName = fullName
        self.email = email
        self.balance = balance
        self.id = id
        self.currency = currency
        self.canteenName = canteenName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullName = (try? container.decode(String.self, forKey: .fullName)) ?? ""
        email = try? container.decodeIfPresent(String.self, forKey: .email)
        balance = container.decodeFlexibleDouble(forKey: .balance) ?? 0
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        currency = (try? container.decode(String.self, forKey: .currency)) ?? "Kč"
        canteenName = try? container.decodeIfPresent(String.self, forKey: .canteenName)
    }
}

struct StravaCZMenu: Codable, Equatable {
    let days: [StravaCZMenuDay]

    var allMeals: [StravaCZMeal] {
        days.flatMap(\.meals)
    }

    var orderedMeals: [StravaCZMeal] {
        allMeals.filter(\.ordered)
    }

    static func make(from response: StravaCZMenuResponse) -> StravaCZMenu {
        let meals = response.meals.compactMap(StravaCZMeal.make(from:))
        let grouped = Dictionary(grouping: meals, by: \.dateKey)
        let days = grouped
            .map { dateKey, meals in
                StravaCZMenuDay(
                    dateKey: dateKey,
                    displayDate: StravaCZFormatters.displayDate(from: dateKey),
                    ordered: meals.contains { $0.ordered },
                    meals: meals.sorted { lhs, rhs in
                        if lhs.type == rhs.type {
                            return lhs.id < rhs.id
                        }
                        return lhs.type.sortOrder < rhs.type.sortOrder
                    }
                )
            }
            .sorted { $0.dateKey < $1.dateKey }

        return StravaCZMenu(days: days)
    }
}

struct StravaCZMenuDay: Codable, Equatable, Identifiable {
    var id: String { dateKey }

    let dateKey: String
    let displayDate: String
    let ordered: Bool
    let meals: [StravaCZMeal]

    var orderedMainMeal: StravaCZMeal? {
        meals.first { $0.type == .main && $0.ordered }
    }
}

struct StravaCZMeal: Codable, Equatable, Identifiable {
    let id: Int
    let dateKey: String
    let type: StravaCZMealType
    let orderType: StravaCZOrderType
    let typeDescription: String
    let name: String
    let forbiddenAllergens: String?
    let allergens: [StravaCZAllergen]
    let ordered: Bool
    let price: Double

    var canModify: Bool {
        type == .main && orderType != .restricted
    }

    var formattedPrice: String {
        price > 0 ? StravaCZFormatters.price(price) : String(localized: "stravacz.price.included")
    }

    var allergenText: String {
        allergens.map(\.displayText).joined(separator: ", ")
    }

    nonisolated static func make(from dto: StravaCZMealDTO) -> StravaCZMeal? {
        let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeDescription = dto.typeDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let longDescription = dto.longDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let restriction = dto.restriction.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNoDetails = longDescription.isEmpty && dto.allergens.isEmpty

        guard !name.isEmpty,
              name.caseInsensitiveCompare(typeDescription) != .orderedSame,
              !hasNoDetails,
              !restriction.contains("VP"),
              let mealID = dto.mealID,
              let dateKey = StravaCZFormatters.normalizedDateKey(from: dto.date)
        else {
            return nil
        }

        let type = StravaCZMealType.make(from: typeDescription)
        let orderType = StravaCZOrderType.make(from: restriction)
        let displayName = longDescription.isEmpty ? name : longDescription

        return StravaCZMeal(
            id: mealID,
            dateKey: dateKey,
            type: type,
            orderType: orderType,
            typeDescription: typeDescription,
            name: displayName,
            forbiddenAllergens: dto.forbiddenAllergens,
            allergens: dto.allergens.map(StravaCZAllergen.make(from:)),
            ordered: dto.orderedCount > 0,
            price: dto.price
        )
    }
}

struct StravaCZAllergen: Codable, Equatable, Identifiable {
    var id: String { code }

    let code: String
    let name: String

    var displayText: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? code : "\(code) \(name)"
    }

    nonisolated static func make(from values: [String]) -> StravaCZAllergen {
        StravaCZAllergen(
            code: values.first ?? "",
            name: values.dropFirst().first ?? ""
        )
    }
}

struct StravaCZMenuResponse: Decodable, Equatable {
    let meals: [StravaCZMealDTO]

    init(meals: [StravaCZMealDTO]) {
        self.meals = meals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var decodedMeals: [StravaCZMealDTO] = []

        for key in container.allKeys where key.stringValue.hasPrefix("table") {
            if let tableMeals = try? container.decode([StravaCZMealDTO].self, forKey: key) {
                decodedMeals.append(contentsOf: tableMeals)
            }
        }

        meals = decodedMeals
    }
}

struct StravaCZMealDTO: Decodable, Equatable {
    let date: String
    let typeDescription: String
    let name: String
    let longDescription: String
    let forbiddenAllergens: String?
    let allergens: [[String]]
    let restriction: String
    let orderedCount: Int
    let mealID: Int?
    let price: Double

    enum CodingKeys: String, CodingKey {
        case date = "datum"
        case typeDescription = "druh_popis"
        case name = "nazev"
        case longDescription = "delsiPopis"
        case forbiddenAllergens = "zakazaneAlergeny"
        case allergens = "alergeny"
        case restriction = "omezeniObj"
        case orderedCount = "pocet"
        case mealID = "veta"
        case price = "cena"
    }

    enum RestrictionCodingKeys: String, CodingKey {
        case day = "den"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        typeDescription = (try? container.decode(String.self, forKey: .typeDescription)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        longDescription = (try? container.decode(String.self, forKey: .longDescription)) ?? ""
        forbiddenAllergens = container.decodeFlexibleString(forKey: .forbiddenAllergens)
        allergens = (try? container.decode([[String]].self, forKey: .allergens)) ?? []

        if let restrictionContainer = try? container.nestedContainer(keyedBy: RestrictionCodingKeys.self, forKey: .restriction) {
            restriction = (try? restrictionContainer.decode(String.self, forKey: .day)) ?? ""
        } else {
            restriction = ""
        }

        orderedCount = container.decodeFlexibleInt(forKey: .orderedCount) ?? 0
        mealID = container.decodeFlexibleInt(forKey: .mealID)
        price = container.decodeFlexibleDouble(forKey: .price) ?? 0
    }
}

struct StravaCZBalanceResponse: Decodable, Equatable {
    let balance: Double?

    enum CodingKeys: String, CodingKey {
        case balance = "konto"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balance = container.decodeFlexibleDouble(forKey: .balance)
    }
}

enum StravaCZFormatters {
    nonisolated private static func apiFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    nonisolated private static func displayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    nonisolated static func normalizedDateKey(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        for format in ["dd.MM.yyyy", "dd-MM.yyyy"] {
            let formatter = apiFormatter(format: format)
            if let date = formatter.date(from: trimmed) {
                return apiFormatter(format: "yyyy-MM-dd").string(from: date)
            }
        }

        if trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return trimmed
        }

        return nil
    }

    nonisolated static func displayDate(from dateKey: String) -> String {
        guard let date = apiFormatter(format: "yyyy-MM-dd").date(from: dateKey) else { return dateKey }
        return displayFormatter().string(from: date)
    }

    nonisolated static func price(_ value: Double) -> String {
        value.formatted(.currency(code: "CZK"))
    }

    nonisolated static func balance(_ value: Double, currency: String) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(2)))
        return "\(formatted) \(currency)"
    }
}

private extension StravaCZMealType {
    nonisolated var sortOrder: Int {
        switch self {
        case .soup: 0
        case .main: 1
        case .unknown: 2
        }
    }

    nonisolated static func make(from value: String) -> StravaCZMealType {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if folded.contains("polevka") {
            return .soup
        }
        if folded.contains("obed") {
            return .main
        }
        return .unknown
    }
}

private extension StravaCZOrderType {
    nonisolated static func make(from restriction: String) -> StravaCZOrderType {
        if restriction.contains("CO") {
            return .restricted
        }
        if restriction.contains("T") {
            return .optional
        }
        return .normal
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return "\(value)"
        }
        return nil
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        }
        return nil
    }
}
