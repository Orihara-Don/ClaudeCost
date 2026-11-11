using System.ComponentModel;
using System.Drawing.Drawing2D;
using ClaudeCost.Core;

namespace ClaudeCost.Tray;

/// <summary>日別・週別の棒グラフ。棒にマウスを乗せると日付と金額を出す。</summary>
internal sealed class BarChart : Control
{
    private IReadOnlyList<DayBar> _bars = [];
    private bool _isWeekly;
    private int _hover = -1;

    public BarChart()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
            | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    }

    [Browsable(false)]
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Func<double, string> Formatter { get; set; } = v => Format.Usd(v);

    public void SetBars(IReadOnlyList<DayBar> bars, bool isWeekly)
    {
        _bars = bars;
        _isWeekly = isWeekly;
        if (_hover >= bars.Count) _hover = -1;
        Invalidate();
    }

    private int LabelEvery => _isWeekly ? 2 : 3;

    private Rectangle PlotArea
    {
        get
        {
            var top = Font.Height + 4;
            var bottom = Font.Height + 4;
            return new Rectangle(0, top, Width, Math.Max(1, Height - top - bottom));
        }
    }

    private float Slot => _bars.Count == 0 ? 0 : (float)PlotArea.Width / _bars.Count;

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var index = Slot <= 0 ? -1 : (int)(e.X / Slot);
        if (index < 0 || index >= _bars.Count) index = -1;
        if (index == _hover) return;
        _hover = index;
        Invalidate();
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        _hover = -1;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(BackColor);
        if (_bars.Count == 0) return;

        var plot = PlotArea;
        var slot = Slot;
        var max = Math.Max(_bars.Max(b => b.Usd), 0.01);
        var barWidth = Math.Max(2f, slot * 0.6f);

        // 最大値の目安線
        using (var grid = new Pen(Color.FromArgb(60, ForeColor)) { DashStyle = DashStyle.Dot })
        {
            g.DrawLine(grid, plot.Left, plot.Top, plot.Right, plot.Top);
        }
        TextRenderer.DrawText(g, Format.Usd(max), Font, new Rectangle(0, 0, Width, plot.Top),
            SystemColors.GrayText, TextFormatFlags.Right | TextFormatFlags.Top | TextFormatFlags.NoPadding);

        using var normal = new SolidBrush(TrayIcons.Accent);
        using var highlight = new SolidBrush(ControlPaint.Dark(TrayIcons.Accent, 0.1f));
        using var empty = new SolidBrush(Color.FromArgb(40, ForeColor));
        for (var i = 0; i < _bars.Count; i++)
        {
            var bar = _bars[i];
            var x = plot.Left + i * slot + (slot - barWidth) / 2;
            var height = (float)(bar.Usd / max * plot.Height);
            if (bar.Usd <= 0)
            {
                g.FillRectangle(empty, x, plot.Bottom - 1, barWidth, 1);
            }
            else
            {
                height = Math.Max(height, 2);
                g.FillRectangle(i == _hover ? highlight : normal, x, plot.Bottom - height, barWidth, height);
            }

            if ((_bars.Count - 1 - i) % LabelEvery == 0)
            {
                var label = Format.ShortDay(bar.Date);
                var size = TextRenderer.MeasureText(g, label, Font, Size.Empty, TextFormatFlags.NoPadding);
                var center = plot.Left + i * slot + slot / 2;
                var left = (int)Math.Clamp(center - size.Width / 2f, 0, Math.Max(0, Width - size.Width));
                TextRenderer.DrawText(g, label, Font, new Point(left, plot.Bottom + 3), SystemColors.GrayText,
                    TextFormatFlags.NoPadding);
            }
        }

        if (_hover >= 0) DrawTooltip(g, plot, slot, max);
    }

    private void DrawTooltip(Graphics g, Rectangle plot, float slot, double max)
    {
        var bar = _bars[_hover];
        var title = _isWeekly ? $"{Format.ShortDay(bar.Date)} からの週" : Format.ShortDay(bar.Date);
        var text = $"{title}\n{Formatter(bar.Usd)}";
        var size = TextRenderer.MeasureText(g, text, Font);
        var padding = 4;
        var box = new Rectangle(0, 0, size.Width + padding * 2, size.Height + padding * 2);

        var center = plot.Left + _hover * slot + slot / 2;
        box.X = (int)Math.Clamp(center - box.Width / 2f, 0, Math.Max(0, Width - box.Width - 1));
        var barTop = plot.Bottom - (float)(bar.Usd / max * plot.Height);
        box.Y = (int)Math.Max(0, barTop - box.Height - 4);

        using var background = new SolidBrush(SystemColors.Info);
        using var border = new Pen(SystemColors.ControlDark);
        g.FillRectangle(background, box);
        g.DrawRectangle(border, box);
        TextRenderer.DrawText(g, text, Font, new Rectangle(box.X + padding, box.Y + padding, size.Width, size.Height),
            SystemColors.InfoText, TextFormatFlags.Left);
    }
}
