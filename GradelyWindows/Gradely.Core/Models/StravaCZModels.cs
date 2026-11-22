using System.Globalization;
using System.Text;
using System.Text.Json.Serialization;

namespace Gradely.Core.Models;

public enum StravaCZMealType
{
    Soup = 0,
    Main = 1,
    Unknown = 2
}

public enum StravaCZOrderType
{
    Normal,
    Optional,
    Restricted
}

public sealed record StravaCZSession(
    string CanteenNumber,
    string Username,
    string SessionId,
    string ServiceUrl,
    double Balance,
    string Currency,
    string? CanteenName,
    string? UserEmail
);

public sealed record StravaCZAllergen(string Code, string Name);

public sealed class StravaCZMeal
{
    public string Id { get; init; } = string.Empty;
    public string DateKey { get; init; } = string.Empty;
    public DateOnly Date { get; init; }
    public string TypeDescription { get; init; } = string.Empty;
    public StravaCZMealType Type { get; init; }
    public string Name { get; init; } = string.Empty;
    public string LongDescription { get; init; } = string.Empty;
    public double Price { get; init; }
    public bool IsOrdered { get; set; }
    public StravaCZOrderType OrderType { get; init; }
    public IReadOnlyList<StravaCZAllergen> Allergens { get; init; } = [];

    public string DisplayName => string.IsNullOrWhiteSpace(LongDescription) ? Name : LongDescription;
    public bool CanModify => Type == StravaCZMealType.Main && OrderType != StravaCZOrderType.Restricted;
}

public sealed record StravaCZDayMenu(
    string DateKey,
    DateOnly Date,
    IReadOnlyList<StravaCZMeal> Meals
);

public sealed class StravaCZRestrictionDto
{
    [JsonPropertyName("den")]
    public string? Den { get; set; }
}

public sealed class StravaCZMealDto
{
    [JsonPropertyName("datum")]
    public string? Datum { get; set; }

    [JsonPropertyName("druh_popis")]
    public string? DruhPopis { get; set; }

    [JsonPropertyName("nazev")]
    public string? Nazev { get; set; }

    [JsonPropertyName("delsiPopis")]
    public string? DelsiPopis { get; set; }

    [JsonPropertyName("alergeny")]
    public List<List<string>>? Alergeny { get; set; }

    [JsonPropertyName("omezeniObj")]
    public StravaCZRestrictionDto? OmezeniObj { get; set; }

    [JsonPropertyName("pocet")]
    [JsonConverter(typeof(FlexibleIntConverter))]
    public int Pocet { get; set; }

    [JsonPropertyName("veta")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? Veta { get; set; }

    [JsonPropertyName("cena")]
    [JsonConverter(typeof(FlexibleNullableDoubleConverter))]
    public double? Cena { get; set; }

    public StravaCZMeal? ToDomain()
    {
        var name = Nazev?.Trim() ?? string.Empty;
        var typeDesc = DruhPopis?.Trim() ?? string.Empty;
        var longDesc = DelsiPopis?.Trim() ?? string.Empty;
        var restriction = OmezeniObj?.Den?.Trim() ?? string.Empty;
        var mealId = Veta?.Trim();

        var allergens = (Alergeny ?? [])
            .Where(a => a.Count > 0 && !string.IsNullOrWhiteSpace(a[0]))
            .Select(a => new StravaCZAllergen(a[0].Trim(), a.Count > 1 ? a[1].Trim() : a[0].Trim()))
            .ToList();

        if (string.IsNullOrEmpty(name)) return null;
        if (string.Equals(name, typeDesc, StringComparison.OrdinalIgnoreCase)) return null;
        if (string.IsNullOrEmpty(longDesc) && allergens.Count == 0) return null;
        if (restriction.Contains("VP", StringComparison.OrdinalIgnoreCase)) return null;
        if (string.IsNullOrEmpty(mealId)) return null;
        if (!TryParseDate(Datum, out var parsedDate)) return null;

        var foldedType = Fold(typeDesc);
        var mealType = foldedType.Contains("polevka")
            ? StravaCZMealType.Soup
            : (foldedType.Contains("obed") ? StravaCZMealType.Main : StravaCZMealType.Unknown);

        var orderType = restriction.Contains("CO", StringComparison.OrdinalIgnoreCase)
            ? StravaCZOrderType.Restricted
            : (restriction.Contains('T', StringComparison.OrdinalIgnoreCase)
                ? StravaCZOrderType.Optional
                : StravaCZOrderType.Normal);

        return new StravaCZMeal
        {
            Id = mealId,
            DateKey = parsedDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            Date = parsedDate,
            TypeDescription = typeDesc,
            Type = mealType,
            Name = name,
            LongDescription = longDesc,
            Price = Cena ?? 0.0,
            IsOrdered = Pocet > 0,
            OrderType = orderType,
            Allergens = allergens
        };
    }

    private static bool TryParseDate(string? raw, out DateOnly date)
    {
        date = default;
        if (string.IsNullOrWhiteSpace(raw)) return false;
        var trimmed = raw.Trim();
        string[] formats = ["dd.MM.yyyy", "dd-MM-yyyy", "yyyy-MM-dd", "d.M.yyyy"];
        return DateOnly.TryParseExact(trimmed, formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out date);
    }

    private static string Fold(string s)
    {
        var norm = s.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(norm.Length);
        foreach (var c in norm)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sb.Append(char.ToLowerInvariant(c));
        }
        return sb.ToString();
    }
}
