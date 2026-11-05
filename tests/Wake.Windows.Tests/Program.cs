using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using Ellipse = System.Windows.Shapes.Ellipse;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Wake.Core;
using Wake.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string output = Path.GetFullPath(args.FirstOrDefault() ?? "artifacts/theme-previews");
        Directory.CreateDirectory(output);
        string data = Path.Combine(Path.GetTempPath(), "wake-ui-tests-" + Guid.NewGuid());
        var app = new App();
        app.InitializeComponent();
        MainWindow? window = null;
        int checks = 0;
        void Check(bool condition, string name)
        {
            if (!condition) throw new InvalidOperationException(name);
            checks++; Console.WriteLine("PASS " + name);
        }
        void Pump()
        {
            app.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
            window!.UpdateLayout();
        }
        T Element<T>(string name) where T : FrameworkElement => (T)window!.FindName(name);
        Color ColorOf(Brush brush) => ((SolidColorBrush)brush).Color;
        Color Resource(string key) => ColorOf((Brush)app.Resources[key]);
        try
        {
            window = new MainWindow(new AppState { KeepAwake = false }, new StateStore(data));
            window.Show(); Pump();
            Check(window.FontSize == 14 && window.Style is not null, "Derived MainWindow receives explicit app style");
            Check(window.Width == 520, "Compact reference layout is the default");
            Check(Element<StackPanel>("TimePanel").Visibility == Visibility.Visible && Element<StackPanel>("TimerPanel").Visibility == Visibility.Collapsed, "Time mode initially visible");
            Element<RadioButton>("AfterDelay").IsChecked = true; Pump();
            Check(Element<StackPanel>("TimerPanel").Visibility == Visibility.Visible && Element<StackPanel>("TimePanel").Visibility == Visibility.Collapsed, "Timer tab changes panels");
            Element<RadioButton>("AtTime").IsChecked = true;
            foreach (string theme in Themes.Palettes.Keys)
            {
                // Simulate contrary OS brushes without changing the runner's actual Windows settings.
                // The app's pixels must resolve from its own resources, not these system defaults.
                foreach (bool lightSystem in new[] { true, false })
                {
                    app.Resources[SystemColors.WindowBrushKey] = lightSystem ? Brushes.White : Brushes.Black;
                    app.Resources[SystemColors.WindowTextBrushKey] = lightSystem ? Brushes.Black : Brushes.White;
                    Element<ComboBox>("ThemePicker").SelectedItem = theme;
                    Themes.Apply(theme); Pump();
                    string prefix = theme + (lightSystem ? " / OS light" : " / OS dark");
                    Check(ColorOf(window.Background) == Resource("BackgroundBrush"), prefix + " window background");
                    Check(ColorOf(window.Foreground) == Resource("TextBrush"), prefix + " window foreground");
                    Check(ColorOf(Element<TextBlock>("ClockText").Foreground) == Resource("TextBrush"), prefix + " readable clock");
                    Check(ColorOf(Element<TextBlock>("NewAlarmHeading").Foreground) == Resource("MutedBrush"), prefix + " readable heading");
                    Check(ColorOf(Element<TextBox>("TimeInput").Foreground) == Resource("TextBrush"), prefix + " themed time field");
                    var combo = Element<ComboBox>("TonePicker"); combo.ApplyTemplate();
                    Check(ColorOf(combo.Foreground) == Resource("TextBrush"), prefix + " dropdown text");
                    var surface = (Border)combo.Template.FindName("DropdownBorder", combo);
                    Check(ColorOf(surface.Background) == Resource("FieldBrush"), prefix + " dropdown surface");
                    combo.IsDropDownOpen = true; Pump();
                    var popup = (Border)combo.Template.FindName("PopupSurface", combo);
                    Check(ColorOf(popup.Background) == Resource("PopupBrush"), prefix + " popup surface");
                    Check(combo.ItemContainerGenerator.ContainerFromIndex(0) is ComboBoxItem item && ColorOf(item.Foreground) == Resource("AccentBrush"), prefix + " popup item text");
                    combo.IsDropDownOpen = false;
                    var toggle = Element<CheckBox>("TypingToggle"); toggle.ApplyTemplate();
                    toggle.IsChecked = true; Pump();
                    var track = (Border)toggle.Template.FindName("Track", toggle);
                    Check(track.Background is LinearGradientBrush && ((Ellipse)toggle.Template.FindName("Knob", toggle)).HorizontalAlignment == HorizontalAlignment.Right, prefix + " checked switch");
                    toggle.IsChecked = false;
                    Check(track.Background is SolidColorBrush, prefix + " unchecked switch");
                }
                Element<ScrollViewer>("MainContent").ScrollToTop(); Pump();
                Capture(window, Path.Combine(output, theme.Replace(' ', '-') + ".png"));
                window.Width = 380; Pump();
                Check(Element<ComboBox>("ThemePicker").ActualWidth > 100 && Element<TextBox>("TimeInput").ActualWidth > 200, theme + " usable minimum width");
                window.Width = 520;
            }
            Themes.Apply("Sunrise");
            Element<ComboBox>("ThemePicker").SelectedItem = "Sunrise";
            Element<RadioButton>("AfterDelay").IsChecked = true;
            Element<CheckBox>("MathToggle").IsChecked = true;
            Element<ListBox>("MathCountPicker").SelectedItem = 8;
            Element<ScrollViewer>("MainContent").ScrollToTop(); Pump();
            Check(Element<StackPanel>("MathOptions").Visibility == Visibility.Visible, "Math options expand");
            Capture(window, Path.Combine(output, "Sunrise-timer.png"));
            Element<ScrollViewer>("MainContent").ScrollToBottom(); Pump();
            Capture(window, Path.Combine(output, "Sunrise-options.png"));
            Console.WriteLine($"{checks} Windows UI checks passed; captures: {output}");
            Console.WriteLine($"::notice title=Native theme checks::{checks} Windows UI checks passed. All eight themes rendered.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            Console.WriteLine("::error title=Windows theme regression::" + ex.ToString().Replace("%", "%25").Replace("\r", "%0D").Replace("\n", "%0A"));
            return 1;
        }
        finally
        {
            window?.ShutdownRuntime(); window?.Close(); app.Shutdown();
            if (Directory.Exists(data)) Directory.Delete(data, true);
        }
    }
    private static void Capture(Window window, string path)
    {
        var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(window);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
}
