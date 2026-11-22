using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Gradely.Core.Models;
using Gradely.Core.Support;

namespace Gradely.Core.Stores;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum AppThemePreference
{
    System,
    Light,
    Dark
}

public sealed class AppSettings
{
    public AppThemePreference Theme { get; set; } = AppThemePreference.System;
    public AppLanguagePreference Language { get; set; } = AppLanguagePreference.System;
    public bool ChronicallyOnline { get; set; }
    public bool ShowMealsTab { get; set; } = true;
    public bool ShowAbsenceSemesterAllowance { get; set; } = true;
}

public sealed class JsonFileStore
{
    private readonly string _rootDir;
    private readonly JsonSerializerOptions _options = new() { WriteIndented = true };

    public JsonFileStore(string? rootDirectory = null)
    {
        _rootDir = rootDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Gradey");
    }

    public string RootDirectory => _rootDir;

    public void Save<T>(string relativePath, T value)
    {
        var fullPath = Path.Combine(_rootDir, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        var json = JsonSerializer.Serialize(value, _options);
        var temp = fullPath + ".tmp";
        File.WriteAllText(temp, json, Encoding.UTF8);
        File.Move(temp, fullPath, overwrite: true);
    }

    public T? Load<T>(string relativePath)
    {
        var fullPath = Path.Combine(_rootDir, relativePath);
        if (!File.Exists(fullPath)) return default;
        try
        {
            var json = File.ReadAllText(fullPath, Encoding.UTF8);
            return JsonSerializer.Deserialize<T>(json, _options);
        }
        catch
        {
            return default;
        }
    }

    public void Delete(string relativePath)
    {
        var fullPath = Path.Combine(_rootDir, relativePath);
        if (File.Exists(fullPath)) File.Delete(fullPath);
    }

    public void DeleteScopeCaches(string scopeKey)
    {
        var cacheDir = Path.Combine(_rootDir, "cache", ScopeHash(scopeKey));
        if (Directory.Exists(cacheDir))
            Directory.Delete(cacheDir, recursive: true);
    }

    public static string ScopeHash(string scopeKey)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(scopeKey));
        return Convert.ToHexString(hash)[..16].ToLowerInvariant();
    }
}

public sealed class AppSettingsStore
{
    private const string FileName = "settings.json";
    private readonly JsonFileStore _store;

    public AppSettingsStore(JsonFileStore store) => _store = store;

    public AppSettings Load() => _store.Load<AppSettings>(FileName) ?? new AppSettings();
    public void Save(AppSettings settings) => _store.Save(FileName, settings);
}

public sealed class AbsenceOverrideStore
{
    private readonly JsonFileStore _store;

    public AbsenceOverrideStore(JsonFileStore store) => _store = store;

    private static string PathForScope(string scopeKey) =>
        Path.Combine("overrides", $"absence-overrides-v1-{JsonFileStore.ScopeHash(scopeKey)}.json");

    public List<AbsenceDayOverride> Load(string scopeKey) =>
        _store.Load<List<AbsenceDayOverride>>(PathForScope(scopeKey)) ?? [];

    public void Save(string scopeKey, List<AbsenceDayOverride> overrides) =>
        _store.Save(PathForScope(scopeKey), overrides);

    public void Upsert(string scopeKey, AbsenceDayOverride dayOverride)
    {
        var list = Load(scopeKey);
        list.RemoveAll(o => string.Equals(o.DateKey, dayOverride.DateKey, StringComparison.Ordinal));
        if (dayOverride.HiddenAllocationIds.Count > 0)
            list.Add(dayOverride);
        Save(scopeKey, list);
    }

    public void RemoveDate(string scopeKey, string dateKey)
    {
        var list = Load(scopeKey);
        list.RemoveAll(o => string.Equals(o.DateKey, dateKey, StringComparison.Ordinal));
        Save(scopeKey, list);
    }

    public void ClearAll(string scopeKey) => _store.Delete(PathForScope(scopeKey));
}

public sealed class PlannerStore
{
    private readonly JsonFileStore _store;

    public PlannerStore(JsonFileStore store) => _store = store;

    private static string PathForScope(string scopeKey) =>
        Path.Combine("planner", $"planner-v1-{JsonFileStore.ScopeHash(scopeKey)}.json");

    public List<PlannerItem> Load(string scopeKey)
    {
        var items = _store.Load<List<PlannerItem>>(PathForScope(scopeKey)) ?? [];
        return SortItems(items);
    }

    public void Upsert(string scopeKey, PlannerItem item)
    {
        item.Scope = scopeKey;
        item.UpdatedAt = DateTimeOffset.UtcNow;
        var items = _store.Load<List<PlannerItem>>(PathForScope(scopeKey)) ?? [];
        var idx = items.FindIndex(x => x.Id == item.Id);
        if (idx >= 0) items[idx] = item;
        else items.Add(item);
        _store.Save(PathForScope(scopeKey), SortItems(items));
    }

    public void Delete(string scopeKey, Guid id)
    {
        var items = _store.Load<List<PlannerItem>>(PathForScope(scopeKey)) ?? [];
        items.RemoveAll(x => x.Id == id);
        _store.Save(PathForScope(scopeKey), SortItems(items));
    }

    public static List<PlannerItem> SortItems(IEnumerable<PlannerItem> items) =>
        items.OrderBy(i => i.OrderingDate ?? DateTime.MaxValue)
             .ThenBy(i => i.CreatedAt)
             .ThenBy(i => i.Id)
             .ToList();
}
