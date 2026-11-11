using System.Runtime.InteropServices;
using ClaudeCost.Core;

namespace ClaudeCost.Tray;

/// <summary>アイコンをクリックすると開く内訳パネル。フォーカスが外れると閉じる。</summary>
internal sealed class PanelForm : Form
{
    private static readonly Color WarningColor = Color.FromArgb(202, 80, 16);

    private readonly TrayContext _app;
    private readonly FlowLayoutPanel _root;
    private readonly BarChart _chart;
    private readonly Font _caption;
    private readonly Font _large;
    private readonly Font _medium;
    private bool _showsWeeks;
    private DateTime _hiddenAt = DateTime.MinValue;
    private Point _anchor;

    public PanelForm(TrayContext app)
    {
        _app = app;
        Font = SystemFonts.MessageBoxFont ?? DefaultFont;
        _caption = new Font(Font.FontFamily, Font.SizeInPoints - 0.5f);
        _large = new Font(Font.FontFamily, 20f, FontStyle.Bold);
        _medium = new Font(Font.FontFamily, 13f, FontStyle.Bold);

        Text = "ClaudeCost";
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        KeyPreview = true;
        BackColor = SystemColors.Window;
        ForeColor = SystemColors.WindowText;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Padding = new Padding(Scale(14));

        _root = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = Padding.Empty,
            Padding = Padding.Empty,
        };
        Controls.Add(_root);

        _chart = new BarChart
        {
            Width = ContentWidth,
            Height = Scale(120),
            Font = _caption,
            Margin = new Padding(0, 0, 0, Scale(8)),
        };
    }

    private int ContentWidth => Scale(320);

    private int Scale(int value) => LogicalToDeviceUnits(value);

    protected override CreateParams CreateParams
    {
        get
        {
            const int dropShadow = 0x00020000;
            var p = base.CreateParams;
            p.ClassStyle |= dropShadow;
            return p;
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        // Windows 11 では角を丸くする（それより前の Windows では何もしない）
        const int cornerPreference = 33;
        var round = 2;
        _ = DwmSetWindowAttribute(Handle, cornerPreference, ref round, sizeof(int));
    }

    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
        HidePanel();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.KeyCode == Keys.Escape) HidePanel();
    }

    private void HidePanel()
    {
        if (!Visible) return;
        Hide();
        _hiddenAt = DateTime.Now;
    }

    /// <summary>アイコンのクリック。開いているときにクリックすると、先にフォーカスが外れて閉じるので、直後なら開き直さない。</summary>
    public void Toggle()
    {
        if (Visible)
        {
            HidePanel();
            return;
        }
        if (DateTime.Now - _hiddenAt < TimeSpan.FromMilliseconds(300)) return;
        ShowNearCursor();
    }

    public void ShowNearCursor()
    {
        _anchor = Cursor.Position;
        Render();
        Show();
        // 表示されてから大きさが決まることがあるため、もう一度合わせる
        PlaceNearAnchor();
        Activate();
    }

    public void RefreshIfVisible()
    {
        if (Visible) Render();
    }

    // MARK: 配置

    /// <summary>タスクバーの位置に合わせて、アイコンの近くに出す。</summary>
    private void PlaceNearAnchor()
    {
        var screen = Screen.FromPoint(_anchor);
        var work = screen.WorkingArea;
        var bounds = screen.Bounds;
        var gap = Scale(8);
        var size = Size;

        int x, y;
        if (work.Left > bounds.Left)
        {
            x = work.Left + gap;
            y = _anchor.Y - size.Height / 2;
        }
        else if (work.Right < bounds.Right)
        {
            x = work.Right - size.Width - gap;
            y = _anchor.Y - size.Height / 2;
        }
        else if (work.Top > bounds.Top)
        {
            x = _anchor.X - size.Width / 2;
            y = work.Top + gap;
        }
        else
        {
            x = _anchor.X - size.Width / 2;
            y = work.Bottom - size.Height - gap;
        }
        x = Math.Clamp(x, work.Left + gap, Math.Max(work.Left + gap, work.Right - size.Width - gap));
        y = Math.Clamp(y, work.Top + gap, Math.Max(work.Top + gap, work.Bottom - size.Height - gap));
        Location = new Point(x, y);
    }

    // MARK: 内容

    private void Render()
    {
        SuspendLayout();
        _root.SuspendLayout();
        foreach (var control in _root.Controls.Cast<Control>().ToList())
        {
            _root.Controls.Remove(control);
            if (control != _chart) control.Dispose();
        }

        if (_app.Summary is { } summary)
            AddContent(summary);
        else
            AddScanning();
        AddButtons();

        _root.ResumeLayout(true);
        ResumeLayout(true);
        PlaceNearAnchor();
    }

    private void AddScanning()
    {
        var text = _app.Progress is { } p ? $"集計中… {p.Done}/{p.Total} ファイル" : "集計中…";
        _root.Controls.Add(MakeLabel(text, Font, SystemColors.GrayText, bottom: 12));
    }

    private void AddContent(Summary s)
    {
        _root.Controls.Add(TwoColumns(
            AmountBlock("今日", s.Today.Usd, _large, ForeColor),
            AmountBlock("今週", s.Weeks.Count > 0 ? s.Weeks[^1].Usd : 0, _medium, ForeColor)));
        _root.Controls.Add(TwoColumns(
            AmountBlock("今月", s.MonthUsd, _medium, ForeColor),
            AmountBlock("月末見込み", s.ForecastUsd, _medium, _app.IsOverBudget ? TrayIcons.Warning : ForeColor)));

        _root.Controls.Add(Separator());
        _root.Controls.Add(ChartHeader());
        _chart.Formatter = usd =>
        {
            var (primary, secondary) = _app.Amounts(usd);
            return secondary is null ? primary : $"{primary}  {secondary}";
        };
        _chart.SetBars(_showsWeeks ? s.Weeks : s.Days, _showsWeeks);
        _root.Controls.Add(_chart);

        if (s.Models.Count > 0)
        {
            _root.Controls.Add(Separator());
            _root.Controls.Add(MakeLabel("モデル別（今月）", _caption, SystemColors.GrayText, bottom: 2));
            foreach (var row in s.Models)
            {
                var value = row.Usd is { } usd
                    ? _app.Amounts(usd).Primary
                    : $"単価未登録 {Format.Tokens(row.Tokens)} tokens";
                _root.Controls.Add(BreakdownRow(Format.ModelName(row.Model), value));
            }
        }

        if (s.Projects.Count > 0)
        {
            _root.Controls.Add(Separator());
            _root.Controls.Add(MakeLabel("プロジェクト別（今月・上位5件）", _caption, SystemColors.GrayText, bottom: 2));
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            foreach (var row in s.Projects)
            {
                _root.Controls.Add(BreakdownRow(Format.ProjectName(row.Project, home), _app.Amounts(row.Usd).Primary));
            }
        }

        AddWarnings(s);
        _root.Controls.Add(MakeLabel(
            $"最終更新 {s.GeneratedAt.LocalDateTime:H:mm} ・ 金額は推計値です", _caption, SystemColors.GrayText, top: 8, bottom: 10));
    }

    private void AddWarnings(Summary s)
    {
        var warnings = new List<string>();
        if (!s.LogsFound) warnings.Add("Claude Code のログが見つかりません");
        if (s.UnpricedModels.Count > 0)
            warnings.Add("単価未登録のため金額に含まれていません: " + string.Join(", ", s.UnpricedModels.Select(Format.ModelName)));
        if (_app.LogFormatWarning)
            warnings.Add("ログは増えていますが利用量を読み取れません。ログ形式が変わった可能性があります");
        if (_app.PricesError is { } error) warnings.Add(error);
        foreach (var text in warnings)
        {
            _root.Controls.Add(MakeLabel("⚠ " + text, _caption, WarningColor, top: 6));
        }
    }

    private void AddButtons()
    {
        var bar = new TableLayoutPanel
        {
            ColumnCount = 4,
            RowCount = 1,
            Width = ContentWidth,
            AutoSize = true,
            Margin = Padding.Empty,
        };
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var refresh = MakeButton("今すぐ更新", () => _app.Refresh());
        refresh.Enabled = !_app.IsScanning;
        bar.Controls.Add(refresh, 0, 0);
        bar.Controls.Add(MakeButton("設定", () =>
        {
            HidePanel();
            _app.ShowSettings();
        }), 2, 0);
        bar.Controls.Add(MakeButton("終了", () => _app.Quit()), 3, 0);
        _root.Controls.Add(bar);
    }

    private Control ChartHeader()
    {
        var header = new TableLayoutPanel
        {
            ColumnCount = 3,
            RowCount = 1,
            Width = ContentWidth,
            AutoSize = true,
            Margin = new Padding(0, 0, 0, Scale(4)),
        };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var title = MakeLabel(_showsWeeks ? "直近8週" : "直近14日", _caption, SystemColors.GrayText);
        title.Anchor = AnchorStyles.Left;
        header.Controls.Add(title, 0, 0);
        header.Controls.Add(PeriodButton("日別", weekly: false), 1, 0);
        header.Controls.Add(PeriodButton("週別", weekly: true), 2, 0);
        return header;
    }

    private RadioButton PeriodButton(string text, bool weekly)
    {
        var button = new RadioButton
        {
            Text = text,
            Appearance = Appearance.Button,
            Checked = _showsWeeks == weekly,
            AutoSize = true,
            Font = _caption,
            TextAlign = ContentAlignment.MiddleCenter,
            Margin = new Padding(0),
            FlatStyle = FlatStyle.System,
        };
        button.Click += (_, _) =>
        {
            if (_showsWeeks == weekly) return;
            _showsWeeks = weekly;
            // 押されたボタン自身を作り直すため、イベントの処理が終わってから描き直す
            BeginInvoke(Render);
        };
        return button;
    }

    private Control AmountBlock(string title, double usd, Font font, Color color)
    {
        var (primary, secondary) = _app.Amounts(usd);
        var block = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true,
            Margin = Padding.Empty,
        };
        block.Controls.Add(MakeLabel(title, _caption, SystemColors.GrayText));
        block.Controls.Add(MakeLabel(primary, font, color));
        if (secondary is not null) block.Controls.Add(MakeLabel(secondary, _caption, SystemColors.GrayText));
        return block;
    }

    private Control TwoColumns(Control left, Control right)
    {
        var table = new TableLayoutPanel
        {
            ColumnCount = 2,
            RowCount = 1,
            Width = ContentWidth,
            AutoSize = true,
            Margin = new Padding(0, 0, 0, Scale(10)),
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Scale(130)));
        table.Controls.Add(left, 0, 0);
        table.Controls.Add(right, 1, 0);
        return table;
    }

    private Control BreakdownRow(string name, string value)
    {
        var table = new TableLayoutPanel
        {
            ColumnCount = 2,
            RowCount = 1,
            Width = ContentWidth,
            AutoSize = true,
            Margin = new Padding(0, 1, 0, 1),
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        var nameLabel = new Label
        {
            Text = name,
            AutoSize = false,
            AutoEllipsis = true,
            Height = Font.Height + 2,
            Dock = DockStyle.Fill,
            Margin = Padding.Empty,
            TextAlign = ContentAlignment.MiddleLeft,
        };
        var valueLabel = MakeLabel(value, Font, ForeColor);
        valueLabel.Anchor = AnchorStyles.Right;
        table.Controls.Add(nameLabel, 0, 0);
        table.Controls.Add(valueLabel, 1, 0);
        return table;
    }

    private Label MakeLabel(string text, Font font, Color color, int top = 0, int bottom = 0) => new()
    {
        Text = text,
        Font = font,
        ForeColor = color,
        AutoSize = true,
        MaximumSize = new Size(ContentWidth, 0),
        Margin = new Padding(0, Scale(top), 0, Scale(bottom)),
        UseMnemonic = false,
    };

    private Control Separator() => new Label
    {
        AutoSize = false,
        Height = 1,
        Width = ContentWidth,
        BackColor = SystemColors.ControlLight,
        Margin = new Padding(0, Scale(4), 0, Scale(8)),
    };

    private Button MakeButton(string text, Action onClick)
    {
        var button = new Button
        {
            Text = text,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(Scale(4), 0, 0, 0),
            Padding = new Padding(Scale(4), 0, Scale(4), 0),
            UseMnemonic = false,
        };
        button.Click += (_, _) => onClick();
        return button;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _chart.Dispose();
            _caption.Dispose();
            _large.Dispose();
            _medium.Dispose();
        }
        base.Dispose(disposing);
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
