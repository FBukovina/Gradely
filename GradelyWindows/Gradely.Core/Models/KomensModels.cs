using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Gradely.Core.Models;

public enum KomensBox
{
    Received,
    Noticeboard
}

public sealed class KomensResponse
{
    [JsonPropertyName("Messages")]
    public List<KomensMessageDto> Messages { get; set; } = [];
}

public sealed class KomensSenderDto
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string? Id { get; set; }

    [JsonPropertyName("Type")]
    public string? Type { get; set; }

    [JsonPropertyName("Name")]
    public string? Name { get; set; }
}

public sealed class KomensMessageDto
{
    [JsonPropertyName("Id")]
    [JsonConverter(typeof(FlexibleStringConverter))]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("Title")]
    public string? Title { get; set; }

    [JsonPropertyName("Text")]
    public string? Text { get; set; }

    [JsonPropertyName("SentDate")]
    public string? SentDate { get; set; }

    [JsonPropertyName("Sender")]
    public KomensSenderDto? Sender { get; set; }

    [JsonPropertyName("RelevantName")]
    public string? RelevantName { get; set; }

    [JsonPropertyName("Attachments")]
    public List<SchoolAttachmentDto> Attachments { get; set; } = [];

    [JsonPropertyName("Read")]
    public bool Read { get; set; } = true;

    [JsonPropertyName("Hidden")]
    public bool Hidden { get; set; }
}

public sealed class KomensSnapshot
{
    public List<KomensMessageDto> Received { get; set; } = [];
    public List<KomensMessageDto> Noticeboard { get; set; } = [];

    public void MarkRead(string messageId)
    {
        foreach (var m in Received.Where(m => m.Id == messageId)) m.Read = true;
        foreach (var m in Noticeboard.Where(m => m.Id == messageId)) m.Read = true;
    }
}

public sealed class KomensMessage
{
    public string MessageId { get; init; } = string.Empty;
    public KomensBox Box { get; init; }
    public string? Title { get; init; }
    public string Body { get; init; } = string.Empty;
    public string? SenderName { get; init; }
    public DateTimeOffset? SentAt { get; init; }
    public bool IsRead { get; set; }
    public IReadOnlyList<SchoolAttachment> Attachments { get; init; } = [];

    public string Id => $"{Box}\u001F{MessageId}";

    public string Heading
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(Title)) return Title;
            var first = Body.Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Trim();
            return string.IsNullOrEmpty(first) ? "Message" : first;
        }
    }

    public string Preview
    {
        get
        {
            var lines = Body.Split('\n', StringSplitOptions.RemoveEmptyEntries).Select(l => l.Trim());
            var slice = Title is null ? lines.Skip(1) : lines;
            return string.Join(" ", slice);
        }
    }

    public static KomensMessage FromDto(KomensMessageDto dto, KomensBox box)
    {
        var decodedTitle = dto.Title is null ? null : KomensText.DecodeEntities(dto.Title).Trim();
        var sender = !string.IsNullOrWhiteSpace(dto.Sender?.Name)
            ? dto.Sender.Name.Trim()
            : (!string.IsNullOrWhiteSpace(dto.RelevantName) ? dto.RelevantName.Trim() : null);

        return new KomensMessage
        {
            MessageId = dto.Id,
            Box = box,
            Title = string.IsNullOrEmpty(decodedTitle) ? null : decodedTitle,
            Body = KomensText.PlainTextFromHtml(dto.Text ?? string.Empty),
            SenderName = sender,
            SentAt = Mark.ParseSchoolDate(dto.SentDate),
            IsRead = dto.Read,
            Attachments = dto.Attachments.Select(a => new SchoolAttachment(
                a.Id,
                string.IsNullOrWhiteSpace(a.Name) ? a.Id : a.Name.Trim(),
                a.Size > 0 ? a.Size : null)).ToList()
        };
    }

    public static List<KomensMessage> SortNewestFirst(IEnumerable<KomensMessage> messages) =>
        messages.OrderByDescending(m => m.SentAt ?? DateTimeOffset.MinValue)
                .ThenByDescending(m => m.MessageId, StringComparer.Ordinal)
                .ToList();
}

public static partial class KomensText
{
    private static readonly Dictionary<string, string> NamedEntities = new(StringComparer.Ordinal)
    {
        ["nbsp"] = " ", ["amp"] = "&", ["lt"] = "<", ["gt"] = ">", ["quot"] = "\"", ["apos"] = "'",
        ["ndash"] = "–", ["mdash"] = "—", ["hellip"] = "…", ["bull"] = "•", ["middot"] = "·",
        ["bdquo"] = "„", ["ldquo"] = "“", ["rdquo"] = "”", ["sbquo"] = "‚", ["lsquo"] = "‘", ["rsquo"] = "’",
        ["laquo"] = "«", ["raquo"] = "»", ["euro"] = "€", ["times"] = "×", ["deg"] = "°", ["copy"] = "©", ["shy"] = "",
        ["aacute"] = "á", ["Aacute"] = "Á", ["eacute"] = "é", ["Eacute"] = "É", ["iacute"] = "í", ["Iacute"] = "Í",
        ["oacute"] = "ó", ["Oacute"] = "Ó", ["uacute"] = "ú", ["Uacute"] = "Ú", ["yacute"] = "ý", ["Yacute"] = "Ý",
        ["ecaron"] = "ě", ["Ecaron"] = "Ě", ["scaron"] = "š", ["Scaron"] = "Š", ["ccaron"] = "č", ["Ccaron"] = "Č",
        ["rcaron"] = "ř", ["Rcaron"] = "Ř", ["zcaron"] = "ž", ["Zcaron"] = "Ž", ["dcaron"] = "ď", ["Dcaron"] = "Ď",
        ["tcaron"] = "ť", ["Tcaron"] = "Ť", ["ncaron"] = "ň", ["Ncaron"] = "Ň", ["uring"] = "ů", ["Uring"] = "Ů",
        ["auml"] = "ä", ["ouml"] = "ö", ["uuml"] = "ü", ["Auml"] = "Ä", ["Ouml"] = "Ö", ["Uuml"] = "Ü", ["szlig"] = "ß",
        ["lcaron"] = "ľ", ["Lcaron"] = "Ľ", ["ocirc"] = "ô", ["Ocirc"] = "Ô", ["lacute"] = "ĺ", ["racute"] = "ŕ"
    };

    public static string PlainTextFromHtml(string html)
    {
        if (string.IsNullOrEmpty(html)) return string.Empty;
        if (!HtmlTagDetectRegex().IsMatch(html))
            return Tidy(DecodeEntities(html));

        var text = WhitespaceRegex().Replace(html, " ");
        text = ScriptStyleCommentRegex().Replace(text, string.Empty);
        text = LinkRegex().Replace(text, match =>
        {
            var address = DecodeEntities(match.Groups[1].Value).Replace("mailto:", "", StringComparison.OrdinalIgnoreCase);
            var label = StripTagsRegex().Replace(match.Groups[2].Value, string.Empty).Trim();
            if (string.IsNullOrEmpty(label)) return address;
            return DecodeEntities(label).Contains(address, StringComparison.OrdinalIgnoreCase)
                ? label
                : $"{label} ({address})";
        });
        text = BrRegex().Replace(text, "\n");
        text = LiRegex().Replace(text, "\n• ");
        text = BlockTagRegex().Replace(text, "\n");
        text = TableCellEndRegex().Replace(text, " ");
        text = StripTagsRegex().Replace(text, string.Empty);
        return Tidy(DecodeEntities(text));
    }

    public static string DecodeEntities(string text)
    {
        if (!text.Contains('&')) return text;
        return EntityRegex().Replace(text, match =>
        {
            var name = match.Groups[1].Value;
            if (name.StartsWith("#x", StringComparison.OrdinalIgnoreCase) &&
                int.TryParse(name[2..], System.Globalization.NumberStyles.HexNumber, null, out var hexCode) &&
                hexCode > 0 && hexCode <= 0x10FFFF)
            {
                return char.ConvertFromUtf32(hexCode);
            }
            if (name.StartsWith('#') &&
                int.TryParse(name[1..], out var decCode) &&
                decCode > 0 && decCode <= 0x10FFFF)
            {
                return char.ConvertFromUtf32(decCode);
            }
            return NamedEntities.TryGetValue(name, out var mapped) ? mapped : match.Value;
        });
    }

    private static string Tidy(string text)
    {
        var lines = new List<string>();
        foreach (var raw in text.Replace("\r\n", "\n").Split('\n'))
        {
            var trimmed = raw.Trim();
            if (trimmed.Length == 0)
            {
                if (lines.Count > 0 && lines[^1].Length > 0)
                    lines.Add(string.Empty);
            }
            else
            {
                lines.Add(trimmed);
            }
        }
        return string.Join("\n", lines).Trim();
    }

    [GeneratedRegex("<[a-zA-Z/!]")]
    private static partial Regex HtmlTagDetectRegex();

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();

    [GeneratedRegex(@"<!--.*?-->|<(script|style)[^>]*>.*?</\1\s*>", RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex ScriptStyleCommentRegex();

    [GeneratedRegex(@"<a\s[^>]*href\s*=\s*[""']([^""']+)[""'][^>]*>(.*?)</a\s*>", RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex LinkRegex();

    [GeneratedRegex(@"<br\s*/?>", RegexOptions.IgnoreCase)]
    private static partial Regex BrRegex();

    [GeneratedRegex(@"<li[^>]*>", RegexOptions.IgnoreCase)]
    private static partial Regex LiRegex();

    [GeneratedRegex(@"</?(p|div|ul|ol|table|tr|h[1-6]|blockquote|section|article)(\s[^>]*)?>", RegexOptions.IgnoreCase)]
    private static partial Regex BlockTagRegex();

    [GeneratedRegex(@"</t[dh]\s*>", RegexOptions.IgnoreCase)]
    private static partial Regex TableCellEndRegex();

    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex StripTagsRegex();

    [GeneratedRegex(@"&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,31});")]
    private static partial Regex EntityRegex();
}
