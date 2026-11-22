using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;

namespace Gradely.Windows.Native;

public static class WindowsThemeInterop
{
    private const int DwmwaUseImmersiveDarkMode = 20;
    private const int DwmwaCaptionColor = 35;
    private const int DwmwaSystemBackdropType = 38;
    private const int DwmsbtMainWindow = 2; // Mica

    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmSetWindowAttribute(nint hwnd, int attr, ref int attrValue, int attrSize);

    public static bool IsSystemDarkMode()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key?.GetValue("AppsUseLightTheme") is int value)
                return value == 0;
        }
        catch
        {
            // Ignore registry permission errors in restricted environments
        }
        return false;
    }

    public static void ApplyWindowChrome(Window window, bool isDark, Color? captionColor = null)
    {
        var helper = new WindowInteropHelper(window);
        if (helper.Handle == 0)
        {
            window.SourceInitialized += (_, _) => ApplyHandleAttributes(new WindowInteropHelper(window).Handle, isDark, captionColor);
            return;
        }
        ApplyHandleAttributes(helper.Handle, isDark, captionColor);
    }

    private static void ApplyHandleAttributes(nint hwnd, bool isDark, Color? captionColor)
    {
        if (hwnd == 0) return;
        try
        {
            int darkVal = isDark ? 1 : 0;
            DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref darkVal, sizeof(int));

            // Try Mica backdrop on Windows 11 22H2+
            int backdrop = DwmsbtMainWindow;
            DwmSetWindowAttribute(hwnd, DwmwaSystemBackdropType, ref backdrop, sizeof(int));

            if (captionColor.HasValue)
            {
                var c = captionColor.Value;
                int colorRef = c.R | (c.G << 8) | (c.B << 16);
                DwmSetWindowAttribute(hwnd, DwmwaCaptionColor, ref colorRef, sizeof(int));
            }
        }
        catch
        {
            // Safe fallback on older Windows 10 builds
        }
    }
}
