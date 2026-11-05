using Wake.Core;
using System.Text;

int passed = 0, failed = 0;
void Test(string name, Action test)
{
    try { test(); Console.WriteLine("PASS " + name); passed++; }
    catch (Exception ex) { Console.Error.WriteLine("FAIL " + name + ": " + ex.Message); failed++; }
}
void Check(bool value) { if (!value) throw new Exception("Assertion failed"); }
void Throws<T>(Action action) where T : Exception
{
    try { action(); } catch (T) { return; }
    throw new Exception("Expected " + typeof(T).Name);
}
var now = new DateTimeOffset(2026, 11, 5, 12, 0, 0, TimeSpan.Zero);
Test("Clock alarm selects today when future", () => Check(Schedule.NextLocal(new(13, 0), now, TimeZoneInfo.Utc) == now.AddHours(1)));
Test("Clock alarm rolls past time to tomorrow", () => Check(Schedule.NextLocal(new(7, 0), now, TimeZoneInfo.Utc) == now.AddHours(19)));
Test("Exact current minute selects tomorrow", () => Check(Schedule.NextLocal(new(12, 0), now, TimeZoneInfo.Utc) == now.AddDays(1)));
Test("Uses supplied local zone", () => Check(Schedule.NextLocal(new(21, 0), now, TimeZoneInfo.CreateCustomTimeZone("UTC+8", TimeSpan.FromHours(8), "UTC+8", "UTC+8")) == now.AddHours(1)));
Test("Countdown includes all units", () => Check(Schedule.Countdown(1, 2, 3, now) == now.AddSeconds(3723)));
Test("Zero countdown rejected", () => Throws<ArgumentException>(() => Schedule.Countdown(0, 0, 0, now)));
Test("Negative and overflowing timer fields rejected", () =>
{
    Throws<ArgumentException>(() => Schedule.Countdown(-1, 0, 0, now));
    Throws<ArgumentException>(() => Schedule.Countdown(0, 60, 0, now));
    Throws<ArgumentException>(() => Schedule.Countdown(100, 0, 0, now));
    Throws<ArgumentException>(() => Schedule.Countdown(0, 0, 60, now));
});
var eastern = TimeZoneInfo.FindSystemTimeZoneById("America/New_York");
Test("Spring DST nonexistent time rejected", () => Throws<ArgumentException>(() => Schedule.NextLocal(new(2, 30), new(2026, 3, 8, 5, 0, 0, TimeSpan.Zero), eastern)));
Test("Tomorrow spring DST nonexistent time rejected", () => Throws<ArgumentException>(() => Schedule.NextLocal(new(2, 30), new(2026, 3, 7, 18, 0, 0, TimeSpan.Zero), eastern)));
Test("Autumn DST selects first future occurrence", () => Check(Schedule.NextLocal(new(1, 30), new(2026, 11, 1, 4, 0, 0, TimeSpan.Zero), eastern) == new DateTimeOffset(2026, 11, 1, 5, 30, 0, TimeSpan.Zero)));
Test("Autumn DST selects second occurrence after first passed", () => Check(Schedule.NextLocal(new(1, 30), new(2026, 11, 1, 5, 45, 0, TimeSpan.Zero), eastern) == new DateTimeOffset(2026, 11, 1, 6, 30, 0, TimeSpan.Zero)));
Test("Empty queue has no due alarm", () => Check(Schedule.NextDue([], now) is null));
Test("Future alarm does not ring early", () => Check(Schedule.NextDue([new() { DueUtc = now.AddSeconds(1) }], now) is null));
Test("Overdue alarms ring oldest first", () =>
{
    var old = new Alarm { DueUtc = now.AddHours(-2) };
    Check(Schedule.NextDue([new() { DueUtc = now }, old], now) == old);
});
Test("Persisted ringing alarm resumes before other alarms", () =>
{
    var active = new Alarm { DueUtc = now.AddHours(1), Ringing = true };
    Check(Schedule.NextDue([new() { DueUtc = now.AddHours(-2) }, active], now) == active);
});
Test("Simultaneous alarms stay queued after dismissal", () =>
{
    var alarms = new List<Alarm> { new() { DueUtc = now }, new() { DueUtc = now } };
    var first = Schedule.NextDue(alarms, now)!; alarms.Remove(first);
    Check(Schedule.NextDue(alarms, now) is not null && Schedule.NextDue(alarms, now) != first);
});
Test("Typing requires exact code and blocks math until solved", () =>
{
    var challenge = new Challenge(true, 2);
    Check(challenge.Code.Length == 8 && !challenge.Complete);
    Check(!challenge.SubmitAnswer(challenge.Left + challenge.Right));
    Check(!challenge.SubmitCode("wrong"));
    Check(challenge.SubmitCode(challenge.Code) && !challenge.TypingPending && challenge.Remaining == 2);
});
Test("Math wrong answer does not advance", () =>
{
    var c = new Challenge(false, 3); int left = c.Left, right = c.Right;
    Check(!c.SubmitAnswer(-1) && c.Remaining == 3 && c.Left == left && c.Right == right);
    for (int i = 0; i < 3; i++) Check(c.SubmitAnswer(c.Left + c.Right));
    Check(c.Complete && !c.SubmitAnswer(0));
});
Test("No tests completes immediately", () => Check(new Challenge(false, 0).Complete));
Test("Challenge rejects unsupported problem counts", () => Throws<ArgumentOutOfRangeException>(() => new Challenge(true, 9)));
Test("State round trips alarm-specific choices and ringing flag", () =>
{
    string dir = Path.Combine(Path.GetTempPath(), "wake-test-" + Guid.NewGuid());
    try
    {
        var store = new StateStore(dir);
        Check(store.Load().Alarms.Count == 0);
        var state = new AppState { Theme = "Nord", Alarms = [new() { DueUtc = now, Label = "Tea", Typing = true, MathCount = 8, Ringing = true, Ringtone = "custom", CustomAudioPath = "local.wav" }] };
        store.Save(state);
        var loaded = store.Load();
        Check(loaded.Theme == "Nord" && loaded.Alarms[0].Id == state.Alarms[0].Id && loaded.Alarms[0].DueUtc == now);
        Check(loaded.Alarms[0].Ringing && loaded.Alarms[0].Typing && loaded.Alarms[0].MathCount == 8 && loaded.Alarms[0].CustomAudioPath == "local.wav");
        state.Alarms.Clear(); store.Save(state);
        Check(store.Load().Alarms.Count == 0 && File.Exists(store.FilePath + ".bak") && !File.Exists(store.FilePath + ".tmp"));
        Check(System.Text.Json.JsonSerializer.Deserialize<AppState>(File.ReadAllText(store.FilePath + ".bak"))!.Alarms.Count == 1);
    }
    finally { Directory.Delete(dir, true); }
});
Test("Corrupt and future schema state are not silently erased", () =>
{
    string dir = Path.Combine(Path.GetTempPath(), "wake-test-" + Guid.NewGuid()); Directory.CreateDirectory(dir);
    try
    {
        var store = new StateStore(dir); File.WriteAllText(store.FilePath, "broken");
        Throws<System.Text.Json.JsonException>(() => store.Load()); Check(File.ReadAllText(store.FilePath) == "broken");
        File.WriteAllText(store.FilePath, "{\"SchemaVersion\":2}"); Throws<InvalidDataException>(() => store.Load());
        File.WriteAllText(store.FilePath, "{\"Alarms\":[{\"MathCount\":100}]}"); Throws<InvalidDataException>(() => store.Load());
    }
    finally { Directory.Delete(dir, true); }
});
Test("All ten original tones generate valid PCM wave files", () =>
{
    Check(Tones.All.Count == 10 && Tones.All.Select(t => t.Id).Distinct().Count() == 10);
    foreach (var tone in Tones.All)
    {
        using var stream = new MemoryStream(); Tones.WriteWave(tone, stream);
        byte[] data = stream.ToArray();
        Check(Encoding.ASCII.GetString(data, 0, 4) == "RIFF" && Encoding.ASCII.GetString(data, 8, 4) == "WAVE");
        Check(BitConverter.ToInt32(data, 4) == data.Length - 8 && BitConverter.ToInt32(data, 40) == data.Length - 44);
        Check(BitConverter.ToInt32(data, 24) == 44100 && data.Skip(44).Any(b => b != 0));
    }
});
Console.WriteLine($"{passed} passed, {failed} failed");
return failed == 0 ? 0 : 1;
