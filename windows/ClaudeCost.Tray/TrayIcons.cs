using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace ClaudeCost.Tray;

/// <summary>通知領域のアイコンを描く。予算超過の見込みなら赤にする。</summary>
internal static class TrayIcons
{
    public static readonly Color Accent = Color.FromArgb(217, 119, 87);
    public static readonly Color Warning = Color.FromArgb(209, 52, 56);

    /// <summary>呼び出し側は使い終わったら <see cref="Destroy"/> で破棄する。</summary>
    public static Icon Create(bool overBudget)
    {
        var size = SystemInformation.SmallIconSize.Width;
        using var bitmap = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.Transparent);
            var radius = size / 4f;
            using var path = RoundedRect(new RectangleF(0, 0, size - 1, size - 1), radius);
            using var fill = new SolidBrush(overBudget ? Warning : Accent);
            g.FillPath(fill, path);
            using var font = new Font("Segoe UI", size * 0.62f, FontStyle.Bold, GraphicsUnit.Pixel);
            using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            g.DrawString("$", font, Brushes.White, new RectangleF(0, 0, size, size + 1), format);
        }
        return Icon.FromHandle(bitmap.GetHicon());
    }

    public static void Destroy(Icon? icon)
    {
        if (icon is null) return;
        var handle = icon.Handle;
        icon.Dispose();
        DestroyIcon(handle);
    }

    private static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        var d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);
}
