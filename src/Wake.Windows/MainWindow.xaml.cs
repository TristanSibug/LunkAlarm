using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Wake.Core;
using Forms = System.Windows.Forms;

namespace Wake.Windows;

public partial class MainWindow : Window
{
    private readonly AppState _state;
    private readonly StateStore _store;
    private readonly AudioService _audio = new();
    private readonly WindowsPower _power = new();
    private readonly DispatcherTimer _tick = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private readonly Forms.NotifyIcon _tray;
    private Alarm? _ringing;
    private Challenge? _challenge;
    private string _answer = "";
    private string? _customPath;
    private bool _ready, _quitting, _powerFailed, _disposed;
    private int _lastSecond = -1;
    private record ToneOption(string Id, string Name);
    private record AlarmRow(Guid Id, string Label, string Time, string Details);

    public MainWindow(AppState state, StateStore store)
    {
        _state = state; _store = store;
        Themes.Apply(state.Theme);
        InitializeComponent();
        ThemePicker.ItemsSource = Themes.Palettes.Keys;
        ThemePicker.SelectedItem = Themes.Palettes.ContainsKey(state.Theme) ? state.Theme : "Sunrise";
        TonePicker.ItemsSource = Tones.All.Select(t => new ToneOption(t.Id, t.Name)).ToList();
        TonePicker.SelectedIndex = 0;
        MathCountPicker.ItemsSource = Enumerable.Range(1, 8);
        MathCountPicker.SelectedItem = 3;
        KeepAwakeToggle.IsChecked = state.KeepAwake;
        WakeToggle.IsChecked = state.WakeFromSleep;
        try { LoginToggle.IsChecked = WindowsPower.StartsAtLogin(); }
        catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        { MessageText.Text = "Could not read start-at-login setting: " + ex.Message; }
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Wake", null, (_, _) => Dispatcher.Invoke(Reveal));
        menu.Items.Add("Quit Wake…", null, (_, _) => Dispatcher.Invoke(Quit));
        using var iconStream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/wake.ico"))!.Stream;
        _tray = new Forms.NotifyIcon { Icon = new System.Drawing.Icon(iconStream), Text = "Wake — Alarm Clock", Visible = true, ContextMenuStrip = menu };
        _tray.DoubleClick += (_, _) => Dispatcher.Invoke(Reveal);
        _audio.Warning += message => { MessageText.Text = message; RingWarning.Text = message; };
        DataObject.AddPastingHandler(CodeInput, (_, e) => e.CancelCommand());
        CommandManager.AddPreviewExecutedHandler(CodeInput, (_, e) =>
        { if (e.Command == ApplicationCommands.Paste || e.Command == ApplicationCommands.Copy || e.Command == ApplicationCommands.Cut) e.Handled = true; });
        CodeInput.ContextMenu = new ContextMenu();
        PreviewKeyDown += RingKeyDown;
        _ready = true;
        RefreshAlarms();
        _tick.Tick += (_, _) => Tick();
        _tick.Start();
        Tick();
    }

    private bool Save()
    {
        try { _store.Save(_state); return true; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            MessageText.Text = "Could not save alarms: " + ex.Message;
            RingWarning.Text = MessageText.Text;
            return false;
        }
    }
    private string DisplayTime(DateTimeOffset time) => time.ToLocalTime().ToString(_state.Use24Hour ? "HH:mm" : "h:mm tt", CultureInfo.CurrentCulture);
    private void Tick()
    {
        var now = DateTimeOffset.UtcNow;
        if (_lastSecond != now.Second)
        {
            _lastSecond = now.Second;
            ClockText.Text = now.ToLocalTime().ToString(_state.Use24Hour ? "HH:mm" : "h:mm", CultureInfo.CurrentCulture);
            AmPmText.Text = _state.Use24Hour ? "" : now.ToLocalTime().ToString("tt", CultureInfo.CurrentCulture);
            SecondsText.Text = now.ToLocalTime().ToString("ss");
            DateText.Text = now.ToLocalTime().ToString("dddd, MMMM d, yyyy");
            ZoneText.Text = TimeZoneInfo.Local.DisplayName;
            var next = _state.Alarms.OrderBy(a => a.DueUtc).FirstOrDefault();
            var left = next?.DueUtc - now;
            NextText.Text = next is null ? "Your next good morning starts here." : left <= TimeSpan.Zero ? "An alarm is due." :
                $"Next in {(int)left!.Value.TotalHours:00}:{left.Value.Minutes:00}:{left.Value.Seconds:00} · {next.Label}";
        }
        if (_ringing is null && Schedule.NextDue(_state.Alarms, now) is { } due) BeginRing(due);
        UpdatePower();
    }
    private void UpdatePower()
    {
        if (_powerFailed) return;
        try
        {
            var next = _state.Alarms.Where(a => a.DueUtc > DateTimeOffset.UtcNow).OrderBy(a => a.DueUtc).FirstOrDefault();
            _power.Update(_state.KeepAwake && _state.Alarms.Count > 0, _state.WakeFromSleep ? next?.DueUtc : null);
            PowerText.Text = _state.Alarms.Count == 0 ? "Power requests are idle until you add an alarm." :
                (_state.KeepAwake ? "Idle sleep is blocked; your display may turn off. " : "Idle sleep is allowed. ") +
                (_state.WakeFromSleep ? "Wake timer requested. Windows must allow wake timers." : "Wake from sleep is off.");
        }
        catch (Win32Exception ex) { _powerFailed = true; PowerText.Text = "Power request failed: " + ex.Message + " Toggle the option to retry."; }
    }
    private void RefreshAlarms()
    {
        FormatButton.Content = _state.Use24Hour ? "24h" : "12h";
        AlarmList.ItemsSource = _state.Alarms.OrderBy(a => a.DueUtc).Select(a => new AlarmRow(a.Id, a.Label,
            DisplayTime(a.DueUtc), a.DueUtc.ToLocalTime().ToString("ddd, MMM d") + " · " +
            (a.Ringtone == "custom" ? "Custom audio" : Tones.All.FirstOrDefault(t => t.Id == a.Ringtone)?.Name ?? "Classic Beep") +
            (a.Typing ? " · Typing" : "") + (a.MathCount > 0 ? $" · {a.MathCount} sums" : ""))).ToList();
        EmptyText.Visibility = _state.Alarms.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        CountText.Text = _state.Alarms.Count.ToString();
        _lastSecond = -1; _powerFailed = false;
    }
    private void AddClick(object sender, RoutedEventArgs e)
    {
        try
        {
            var now = DateTimeOffset.UtcNow;
            DateTimeOffset due;
            if (AtTime.IsChecked == true)
            {
                if (!TimeOnly.TryParseExact(TimeInput.Text.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var time))
                    throw new ArgumentException("Enter a time like 07:00 or 19:30 (24-hour HH:mm).");
                due = Schedule.NextLocal(time, now, TimeZoneInfo.Local);
            }
            else
            {
                if (!int.TryParse(HoursInput.Text, out int h) || !int.TryParse(MinutesInput.Text, out int m) || !int.TryParse(TimerSecondsInput.Text, out int s))
                    throw new ArgumentException("Enter whole numbers for hours, minutes and seconds.");
                due = Schedule.Countdown(h, m, s, now);
            }
            var alarm = new Alarm { Label = string.IsNullOrWhiteSpace(LabelInput.Text) ? "Wake up" : LabelInput.Text.Trim(), DueUtc = due,
                Ringtone = (string?)TonePicker.SelectedValue ?? "classic-beep", CustomAudioPath = _customPath,
                Typing = TypingToggle.IsChecked == true, MathCount = MathToggle.IsChecked == true ? (int)MathCountPicker.SelectedItem : 0 };
            _state.Alarms.Add(alarm);
            if (!Save()) { _state.Alarms.Remove(alarm); return; }
            MessageText.Text = $"Alarm set for {due.ToLocalTime():ddd, MMM d} at {DisplayTime(due)}.";
            RefreshAlarms(); Tick();
        }
        catch (ArgumentException ex) { MessageText.Text = ex.Message; }
    }
    private void RemoveClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: Guid id }) return;
        var alarm = _state.Alarms.FirstOrDefault(a => a.Id == id);
        if (alarm is null || alarm == _ringing) return;
        int index = _state.Alarms.IndexOf(alarm);
        _state.Alarms.Remove(alarm);
        if (!Save()) { _state.Alarms.Insert(index, alarm); return; }
        MessageText.Text = "Alarm removed."; RefreshAlarms(); Tick();
    }
    private void BeginRing(Alarm alarm)
    {
        _ringing = alarm; alarm.Ringing = true;
        _challenge = new Challenge(alarm.Typing, alarm.MathCount);
        _answer = ""; RingWarning.Text = ""; ChallengeMessage.Text = "";
        Save();
        _audio.Play(alarm.Ringtone, alarm.CustomAudioPath);
        RingLabel.Text = alarm.Label;
        RingTime.Text = DisplayTime(alarm.DueUtc) + " · Time to wake up";
        MainContent.IsEnabled = false; RingOverlay.Visibility = Visibility.Visible;
        Reveal(); Topmost = true;
        ShowChallenge();
    }
    private void ShowChallenge()
    {
        if (_challenge is null) return;
        TypingPanel.Visibility = _challenge.TypingPending ? Visibility.Visible : Visibility.Collapsed;
        MathPanel.Visibility = !_challenge.TypingPending && _challenge.Remaining > 0 ? Visibility.Visible : Visibility.Collapsed;
        StopButton.Visibility = _challenge.Complete ? Visibility.Visible : Visibility.Collapsed;
        if (_challenge.TypingPending)
        {
            StepText.Text = _ringing!.MathCount > 0 ? "Step 1 of 2 · Type the code (case sensitive)" : "Type the code (case sensitive)";
            CodeText.Text = _challenge.Code; CodeInput.Clear(); CodeInput.Focus();
        }
        else if (_challenge.Remaining > 0)
        {
            StepText.Text = $"{(_ringing!.Typing ? "Step 2 of 2 · " : "")}Problem {_ringing.MathCount - _challenge.Remaining + 1} of {_ringing.MathCount}";
            ProblemText.Text = $"{_challenge.Left} + {_challenge.Right} = ?"; _answer = ""; AnswerText.Text = "—";
            MathPanel.Focusable = true; MathPanel.Focus();
        }
        else { StepText.Text = "You're ready for a fresh start."; StopButton.Focus(); }
    }
    private void CodeChanged(object sender, TextChangedEventArgs e)
    {
        if (_challenge?.TypingPending != true || CodeInput.Text.Length != 8) return;
        if (_challenge.SubmitCode(CodeInput.Text))
        {
            ChallengeMessage.Text = "";
            if (_challenge.Complete) FinishRing(); else ShowChallenge();
        }
        else ChallengeMessage.Text = "Try again. Capitals matter.";
    }
    private void KeypadClick(object sender, RoutedEventArgs e) => MathKey(((Button)sender).Content.ToString()!);
    private void MathKey(string key)
    {
        if (_challenge is null || _challenge.TypingPending || _challenge.Remaining == 0) return;
        if (key == "⌫") _answer = _answer.Length == 0 ? "" : _answer[..^1];
        else if (key == "OK")
        {
            if (int.TryParse(_answer, out int answer) && _challenge.SubmitAnswer(answer))
            {
                ChallengeMessage.Text = "";
                if (_challenge.Complete) FinishRing(); else ShowChallenge();
                return;
            }
            ChallengeMessage.Text = "Not quite. Try the same problem again."; _answer = "";
        }
        else if (_answer.Length < 3 && key.Length == 1 && char.IsAsciiDigit(key[0])) _answer += key;
        AnswerText.Text = _answer.Length == 0 ? "—" : _answer;
    }
    private void RingKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (_ringing is null || _challenge?.TypingPending == true || _challenge?.Remaining == 0) return;
        if (e.Key is >= Key.D0 and <= Key.D9) MathKey(((int)e.Key - (int)Key.D0).ToString());
        else if (e.Key is >= Key.NumPad0 and <= Key.NumPad9) MathKey(((int)e.Key - (int)Key.NumPad0).ToString());
        else if (e.Key == Key.Back) MathKey("⌫");
        else if (e.Key == Key.Enter) MathKey("OK");
        else return;
        e.Handled = true;
    }
    private void StopClick(object sender, RoutedEventArgs e) { if (_challenge?.Complete == true) FinishRing(); }
    private void FinishRing()
    {
        if (_ringing is null) return;
        int index = _state.Alarms.IndexOf(_ringing);
        _state.Alarms.Remove(_ringing);
        if (!Save())
        {
            _state.Alarms.Insert(index, _ringing);
            ShowChallenge(); // Completed tests remain complete; Stop retries persistence.
            return;
        }
        _audio.Stop(); _ringing = null; _challenge = null;
        Topmost = false; RingOverlay.Visibility = Visibility.Collapsed; MainContent.IsEnabled = true;
        MessageText.Text = "Alarm dismissed. Have a good day."; RefreshAlarms(); Tick();
    }
    // Also used by the Windows UI regression runner to release native resources cleanly.
    internal void ShutdownRuntime()
    {
        if (_disposed) return;
        _disposed = true; _quitting = true; _tick.Stop(); _audio.Dispose(); _power.Dispose();
        _tray.Visible = false; _tray.Icon?.Dispose(); _tray.ContextMenuStrip?.Dispose(); _tray.Dispose();
    }
    private void MinimizeClick(object sender, RoutedEventArgs e) => SystemCommands.MinimizeWindow(this);
    private void MaximizeClick(object sender, RoutedEventArgs e)
    {
        if (WindowState == WindowState.Maximized) SystemCommands.RestoreWindow(this);
        else SystemCommands.MaximizeWindow(this);
    }
    private void CloseClick(object sender, RoutedEventArgs e) => Close();
    private void Reveal() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void WindowClosing(object? sender, CancelEventArgs e)
    {
        if (_quitting) return;
        e.Cancel = true; Hide();
        _tray.ShowBalloonTip(2000, "Wake is still running", "Alarms stay active in the tray. Use the tray menu to quit.", Forms.ToolTipIcon.Info);
    }
    private void Quit()
    {
        if (_state.Alarms.Count > 0 && MessageBox.Show("Quit Wake? Alarms will not ring until you open Wake again. Pending alarms stay saved.", "Quit Wake", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        ShutdownRuntime();
        System.Windows.Application.Current.Shutdown();
    }
    private void ThemeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_ready || ThemePicker.SelectedItem is not string theme) return;
        _state.Theme = theme; Themes.Apply(theme); Save();
    }
    private void FormatClick(object sender, RoutedEventArgs e) { _state.Use24Hour = !_state.Use24Hour; Save(); RefreshAlarms(); Tick(); }
    private void ModeChanged(object sender, RoutedEventArgs e)
    {
        if (TimePanel is null || TimerPanel is null) return;
        TimePanel.Visibility = AtTime.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        TimerPanel.Visibility = AtTime.IsChecked == true ? Visibility.Collapsed : Visibility.Visible;
    }
    private void MathChanged(object sender, RoutedEventArgs e)
    { if (MathOptions is not null) MathOptions.Visibility = MathToggle.IsChecked == true ? Visibility.Visible : Visibility.Collapsed; }
    private void PresetClick(object sender, RoutedEventArgs e)
    {
        int minutes = int.Parse(((Button)sender).Tag.ToString()!, CultureInfo.InvariantCulture);
        HoursInput.Text = (minutes / 60).ToString(); MinutesInput.Text = (minutes % 60).ToString(); TimerSecondsInput.Text = "0";
    }
    private void PreviewClick(object sender, RoutedEventArgs e)
    {
        if (_audio.IsPlaying) { _audio.Stop(); return; }
        _audio.Play((string?)TonePicker.SelectedValue ?? "classic-beep", _customPath, preview: true);
    }
    private void ImportClick(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "Audio files|*.wav;*.mp3;*.wma", Title = "Choose an alarm sound (up to 2 MB)" };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var info = new FileInfo(dialog.FileName);
            if (info.Length is <= 0 or > 2 * 1024 * 1024) throw new IOException("Choose a non-empty audio file up to 2 MB.");
            string folder = Path.Combine(_store.DirectoryPath, "Sounds"); Directory.CreateDirectory(folder);
            string path = Path.Combine(folder, Guid.NewGuid() + info.Extension.ToLowerInvariant());
            File.Copy(info.FullName, path);
            _customPath = path;
            TonePicker.ItemsSource = Tones.All.Select(t => new ToneOption(t.Id, t.Name)).Append(new("custom", info.Name)).ToList();
            TonePicker.SelectedValue = "custom"; CustomText.Text = "Imported: " + info.Name + ". Preview to check Windows can play it.";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { MessageText.Text = "Could not import sound: " + ex.Message; }
    }
    private void OptionsChanged(object sender, RoutedEventArgs e)
    {
        if (!_ready) return;
        _state.KeepAwake = KeepAwakeToggle.IsChecked == true; _state.WakeFromSleep = WakeToggle.IsChecked == true;
        Save(); _powerFailed = false; UpdatePower();
    }
    private void LoginChanged(object sender, RoutedEventArgs e)
    {
        if (!_ready) return;
        try { WindowsPower.SetLogin(LoginToggle.IsChecked == true); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException or InvalidOperationException)
        {
            MessageText.Text = "Could not change start at login: " + ex.Message;
            _ready = false; LoginToggle.IsChecked = !(LoginToggle.IsChecked == true); _ready = true;
        }
    }
    private void OpenLink(string uri)
    {
        try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException) { MessageText.Text = "Could not open: " + ex.Message; }
    }
    private void TimeSettingsClick(object sender, RoutedEventArgs e) => OpenLink("ms-settings:dateandtime");
    private void FindSoundsClick(object sender, RoutedEventArgs e) => OpenLink("https://mixkit.co/free-sound-effects/alarm/");
}
