using System.Text.Json;

namespace Wake.Core;

public sealed class StateStore(string directory)
{
    public string DirectoryPath { get; } = directory;
    public string FilePath => Path.Combine(DirectoryPath, "state.json");
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public AppState Load()
    {
        if (!File.Exists(FilePath)) return new();
        var state = JsonSerializer.Deserialize<AppState>(File.ReadAllText(FilePath), Options)
            ?? throw new InvalidDataException("The saved alarm data is empty.");
        if (state.SchemaVersion != 1 || state.Alarms is null || state.Alarms.Any(a =>
            a is null || a.Id == Guid.Empty || a.DueUtc == default || a.MathCount is < 0 or > 8 ||
            string.IsNullOrWhiteSpace(a.Label) || string.IsNullOrWhiteSpace(a.Ringtone)) ||
            state.Alarms.Select(a => a.Id).Distinct().Count() != state.Alarms.Count)
            throw new InvalidDataException("The saved alarm data has an unsupported format.");
        return state;
    }

    public void Save(AppState state)
    {
        Directory.CreateDirectory(DirectoryPath);
        string temporary = FilePath + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, state, Options);
                stream.Flush(flushToDisk: true);
            }
            // Same-directory replace: an interrupted write leaves the previous file intact.
            if (File.Exists(FilePath)) File.Replace(temporary, FilePath, FilePath + ".bak");
            else File.Move(temporary, FilePath);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
