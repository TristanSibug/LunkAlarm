using System.IO;
using System.Media;
using System.Windows.Media;
using System.Windows.Threading;
using Wake.Core;

namespace Wake.Windows;

internal sealed class AudioService : IDisposable
{
    private SoundPlayer? _player;
    private MemoryStream? _wave;
    private MediaPlayer? _media;
    private readonly DispatcherTimer _fallback = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly DispatcherTimer _preview = new() { Interval = TimeSpan.FromSeconds(5) };
    public bool IsPlaying { get; private set; }
    public event Action<string>? Warning;
    public AudioService()
    {
        _fallback.Tick += (_, _) => SystemSounds.Exclamation.Play();
        _preview.Tick += (_, _) => Stop();
    }
    public void Play(string ringtone, string? customPath = null, bool preview = false)
    {
        Stop();
        IsPlaying = true;
        try
        {
            if (ringtone == "custom")
            {
                if (customPath is null || !File.Exists(customPath)) throw new IOException("Custom sound is missing.");
                _media = new MediaPlayer();
                _media.MediaEnded += (_, _) => { if (_media is not null) { _media.Position = TimeSpan.Zero; _media.Play(); } };
                _media.MediaFailed += (_, _) => Fallback("Windows could not decode this sound. Playing the backup sound.");
                _media.Volume = 1;
                _media.Open(new Uri(customPath, UriKind.Absolute));
                _media.Play();
            }
            else
            {
                _wave = new MemoryStream();
                Tones.WriteWave(Tones.All.FirstOrDefault(t => t.Id == ringtone) ?? Tones.All[0], _wave);
                _wave.Position = 0;
                _player = new SoundPlayer(_wave);
                _player.Load();
                _player.PlayLooping();
            }
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or System.TimeoutException or System.ComponentModel.Win32Exception or NotSupportedException)
        { Fallback("Audio failed: " + ex.Message + " Using the system backup sound."); }
        if (preview) _preview.Start();
    }
    private void Fallback(string message)
    {
        _media?.Close(); _player?.Stop();
        Warning?.Invoke(message);
        SystemSounds.Exclamation.Play(); _fallback.Start();
    }
    public void Stop()
    {
        IsPlaying = false;
        _preview.Stop(); _fallback.Stop();
        _media?.Close(); _media = null;
        _player?.Stop(); _player?.Dispose(); _player = null;
        _wave?.Dispose(); _wave = null;
    }
    public void Dispose() => Stop();
}
