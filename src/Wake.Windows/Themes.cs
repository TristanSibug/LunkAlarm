using System.Windows;
using System.Windows.Media;

namespace Wake.Windows;

internal static class Themes
{
    public static readonly Dictionary<string, string[]> Palettes = new()
    {
        ["Sunrise"] = ["#0A0C16", "#161827", "#0F111D", "#F4F2FF", "#A5A6C0", "#FFA94D", "#1A0F05", "#34364B"],
        ["OLED Black"] = ["#000000", "#0C0C0E", "#000000", "#F2F2F5", "#A5A5AE", "#FFA94D", "#1A0F05", "#353538"],
        ["Dark"] = ["#17181C", "#212329", "#181A1F", "#ECECF1", "#ABAEB9", "#FFA94D", "#1A0F05", "#42454F"],
        ["Light"] = ["#F3F2FA", "#FFFFFF", "#F0EFF7", "#1C1B2E", "#5B5C76", "#C4520A", "#FFFFFF", "#CCCADA"],
        ["Tokyo Night"] = ["#1A1B26", "#24283B", "#16161E", "#C0CAF5", "#A4ADD1", "#7AA2F7", "#16161E", "#414966"],
        ["VS Code Blue"] = ["#1E1E1E", "#252526", "#181818", "#D4D4D4", "#ABABAB", "#75BEFF", "#101720", "#474747"],
        ["Dracula"] = ["#282A36", "#343746", "#21222C", "#F8F8F2", "#B4B8D3", "#BD93F9", "#21142E", "#54576A"],
        ["Nord"] = ["#2E3440", "#3B4252", "#272C36", "#ECEFF4", "#BEC8D8", "#88C0D0", "#202A35", "#596478"]
    };
    public static void Apply(string name)
    {
        var colors = Palettes.GetValueOrDefault(name) ?? Palettes["Sunrise"];
        string[] keys = ["BackgroundBrush", "CardBrush", "FieldBrush", "TextBrush", "MutedBrush", "AccentBrush", "OnAccentBrush", "BorderBrush"];
        for (int i = 0; i < keys.Length; i++)
            System.Windows.Application.Current.Resources[keys[i]] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(colors[i]));
    }
}
