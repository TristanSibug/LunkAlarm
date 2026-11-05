namespace Wake.Core;

public sealed class Alarm
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Label { get; set; } = "Wake up";
    public DateTimeOffset DueUtc { get; set; }
    public string Ringtone { get; set; } = "classic-beep";
    public string? CustomAudioPath { get; set; }
    public bool Typing { get; set; }
    public int MathCount { get; set; }
    public bool Ringing { get; set; }
}

public sealed class AppState
{
    public int SchemaVersion { get; set; } = 1;
    public bool Use24Hour { get; set; }
    public string Theme { get; set; } = "Sunrise";
    public bool KeepAwake { get; set; } = true;
    public bool WakeFromSleep { get; set; }
    public List<Alarm> Alarms { get; set; } = [];
}

public static class Schedule
{
    // A nonexistent local time is rejected rather than silently moved across a DST gap.
    // A repeated local time selects the first occurrence still in the future.
    public static DateTimeOffset NextLocal(TimeOnly time, DateTimeOffset now, TimeZoneInfo zone)
    {
        var today = TimeZoneInfo.ConvertTime(now, zone).Date;
        for (int day = 0; day < 3; day++)
        {
            var local = DateTime.SpecifyKind(today.AddDays(day).Add(time.ToTimeSpan()), DateTimeKind.Unspecified);
            if (zone.IsInvalidTime(local))
            {
                if (local > TimeZoneInfo.ConvertTime(now, zone).DateTime)
                    throw new ArgumentException("That time does not exist on the next alarm date because the clocks move forward. Choose another time.");
                continue;
            }
            var offsets = zone.IsAmbiguousTime(local) ? zone.GetAmbiguousTimeOffsets(local) : [zone.GetUtcOffset(local)];
            foreach (var candidate in offsets.Select(o => new DateTimeOffset(local, o).ToUniversalTime()).Order())
                if (candidate > now) return candidate;
        }
        throw new ArgumentException("Could not find the next valid local time.");
    }

    public static DateTimeOffset Countdown(int hours, int minutes, int seconds, DateTimeOffset now)
    {
        if (hours is < 0 or > 99 || minutes is < 0 or > 59 || seconds is < 0 or > 59)
            throw new ArgumentException("Use 0–99 hours and 0–59 minutes and seconds.");
        var duration = new TimeSpan(hours, minutes, seconds);
        if (duration <= TimeSpan.Zero) throw new ArgumentException("Choose a duration greater than zero.");
        return now.Add(duration);
    }

    public static Alarm? NextDue(IEnumerable<Alarm> alarms, DateTimeOffset now) => alarms
        .Where(a => a.Ringing || a.DueUtc <= now).OrderByDescending(a => a.Ringing)
        .ThenBy(a => a.DueUtc).ThenBy(a => a.Id).FirstOrDefault();
}
