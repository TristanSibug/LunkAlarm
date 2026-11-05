using System.Windows;
using System.Windows.Media;

namespace Wake.Windows;

internal static class Themes
{
    // Color tokens from the supplied Tauri CSS. Never resolve app colors from Windows defaults.
    public static readonly Dictionary<string, string[]> Palettes = new()
    {
        ["Sunrise"] = ["#0A0C16", "#0EFFFFFF", "#47000000", "#F4F2FF", "#9A9BB8", "#FFA94D", "#1A0F05", "#17FFFFFF", "#1FFFFFFF", "#4C000000", "#1FFFFFFF", "#24FFFFFF", "#FFFFFF", "#151829", "#4ADE80", "#FF6B7A", "#477C5CFF", "#33FF6B7A"],
        ["OLED Black"] = ["#000000", "#0C0C0E", "#000000", "#F2F2F5", "#9A9AA3", "#FFA94D", "#1A0F05", "#1FFFFFFF", "#1FFFFFFF", "#1A1A1D", "#34343A", "#34343A", "#FFFFFF", "#0C0C0E", "#4ADE80", "#FF6B7A", "#00000000", "#00000000"],
        ["Dark"] = ["#17181C", "#212329", "#181A1F", "#ECECF1", "#9A9BA6", "#FFA94D", "#1A0F05", "#14FFFFFF", "#1AFFFFFF", "#181A1F", "#343740", "#3B3E48", "#FFFFFF", "#212329", "#4ADE80", "#FF6B7A", "#00000000", "#00000000"],
        ["Light"] = ["#F3F2FA", "#C7FFFFFF", "#0D14143C", "#1C1B2E", "#5B5C76", "#C4520A", "#FFFFFF", "#1A14143C", "#1414143C", "#1214143C", "#FFFFFF", "#3314143C", "#FFFFFF", "#FFFFFF", "#15803D", "#D6336C", "#247C5CFF", "#1FFF6B7A"],
        ["Tokyo Night"] = ["#1A1B26", "#24283B", "#16161E", "#C0CAF5", "#8C93BF", "#7AA2F7", "#16161E", "#1AC0CAF5", "#1AC0CAF5", "#16161E", "#2F334D", "#3B4261", "#C0CAF5", "#1F2335", "#9ECE6A", "#BB9AF7", "#1F7AA2F7", "#1ABB9AF7"],
        ["VS Code Blue"] = ["#002451", "#003370", "#001B42", "#E8F0FF", "#A9C0E6", "#5DB0FF", "#00183A", "#389DB6DD", "#1AFFFFFF", "#001B42", "#0A4A94", "#1A5296", "#FFFFFF", "#00306A", "#8BD49C", "#3A86FF", "#00000000", "#00000000"],
        ["Dracula"] = ["#282A36", "#343746", "#21222C", "#F8F8F2", "#AAB0D0", "#BD93F9", "#282A36", "#1AF8F8F2", "#1AF8F8F2", "#21222C", "#44475A", "#4B4F66", "#F8F8F2", "#2D2F3D", "#50FA7B", "#FF79C6", "#1FBD93F9", "#14FF79C6"],
        ["Nord"] = ["#2E3440", "#3B4252", "#2B303B", "#ECEFF4", "#A3B1C6", "#88C0D0", "#2E3440", "#1AD8DEE9", "#1AD8DEE9", "#2B303B", "#4C566A", "#4C566A", "#ECEFF4", "#353B49", "#A3BE8C", "#81A1C1", "#00000000", "#00000000"],
    };
    public static void Apply(string name)
    {
        var colors = Palettes.GetValueOrDefault(name) ?? Palettes["Sunrise"];
        string[] keys = ["BackgroundBrush", "CardBrush", "FieldBrush", "TextBrush", "MutedBrush", "AccentBrush", "OnAccentBrush", "BorderBrush", "HoverBrush", "TrackBrush", "TabBrush", "SwitchBrush", "KnobBrush", "PopupBrush", "GoodBrush"];
        var resources = System.Windows.Application.Current.Resources;
        for (int i = 0; i < keys.Length; i++) resources[keys[i]] = Brush(colors[i]);
        resources["AccentGradient"] = new LinearGradientBrush(ColorOf(colors[5]), ColorOf(colors[15]), 45);
        resources["SelectionBrush"] = new SolidColorBrush(ColorOf(colors[5])) { Opacity = 0.4 };
        resources["TopGlow"] = Glow(colors[16], new Point(.15, 0), .75, .65);
        resources["BottomGlow"] = Glow(colors[17], new Point(1, 1), .7, .6);
    }
    private static Color ColorOf(string value) => (Color)ColorConverter.ConvertFromString(value);
    private static SolidColorBrush Brush(string value) => new(ColorOf(value));
    private static RadialGradientBrush Glow(string value, Point origin, double x, double y)
    {
        var color = ColorOf(value);
        return new RadialGradientBrush(new GradientStopCollection
        {
            new(color, 0), new(Color.FromArgb(0, color.R, color.G, color.B), 1)
        }) { Center = origin, GradientOrigin = origin, RadiusX = x, RadiusY = y };
    }
}
