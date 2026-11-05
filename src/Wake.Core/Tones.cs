using System.Text;
using System.Text.Json;

namespace Wake.Core;

public sealed record Tone(string Id, string Name, string Wave, string Style, double Volume, double Cycle, double[][] Notes);

public static class Tones
{
    public static IReadOnlyList<Tone> All { get; } = Load();
    private static Tone[] Load()
    {
        using var stream = typeof(Tones).Assembly.GetManifestResourceStream("Wake.Core.tones.json")!;
        return JsonSerializer.Deserialize<Tone[]>(stream, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
    }

    // Original synthesizer recipes rendered into offline PCM WAV, played through Windows audio.
    public static void WriteWave(Tone tone, Stream output)
    {
        const int rate = 44100;
        int count = (int)(tone.Cycle * rate);
        using var writer = new BinaryWriter(output, Encoding.ASCII, leaveOpen: true);
        writer.Write(Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + count * 2);
        writer.Write(Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16);
        writer.Write((short)1); writer.Write((short)1); writer.Write(rate); writer.Write(rate * 2);
        writer.Write((short)2); writer.Write((short)16);
        writer.Write(Encoding.ASCII.GetBytes("data")); writer.Write(count * 2);
        for (int i = 0; i < count; i++)
        {
            double time = (double)i / rate, sample = 0;
            foreach (var n in tone.Notes)
            {
                double t = time - n[1], length = n[2];
                if (t < 0 || t >= length) continue;
                double phase = n[0] * t + (n.Length > 3 ? (n[3] - n[0]) * t * t / (2 * length) : 0);
                double angle = 2 * Math.PI * phase;
                double wave = tone.Wave switch
                {
                    "square" => Math.Sin(angle) >= 0 ? 1 : -1,
                    "triangle" => 2 / Math.PI * Math.Asin(Math.Sin(angle)),
                    "sawtooth" => 2 * (phase - Math.Floor(phase + 0.5)),
                    _ => Math.Sin(angle)
                };
                double envelope = Math.Min(1, t / .01) * (tone.Style == "ring" ? Math.Exp(-7 * t / length) : Math.Min(1, (length - t) / .02));
                sample += wave * tone.Volume * envelope;
            }
            writer.Write((short)(Math.Clamp(sample, -1, 1) * short.MaxValue));
        }
    }
}
