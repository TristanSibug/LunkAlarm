using System.IO;
using System.Threading;
using System.Windows;
using Wake.Core;

namespace Wake.Windows;

public partial class App : System.Windows.Application
{
    private Mutex? _instance;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _instance = new Mutex(true, @"Local\Wake.Native.Windows", out bool first);
        if (!first)
        {
            MessageBox.Show("Wake is already running. Open it from the system tray.", "Wake");
            Shutdown(); return;
        }
        var store = new StateStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WakeNative"));
        AppState state;
        try { state = store.Load(); }
        catch (Exception ex) when (ex is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            MessageBox.Show($"Wake could not read your alarms. Your files have been left untouched.\n\n{ex.Message}\n\nData: {store.DirectoryPath}\nA previous save may be available as state.json.bak.", "Cannot load alarms", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1); return;
        }
        var window = new MainWindow(state, store);
        MainWindow = window;
        if (!e.Args.Contains("--background")) window.Show();
    }
    protected override void OnExit(ExitEventArgs e)
    {
        _instance?.Dispose();
        base.OnExit(e);
    }
}
