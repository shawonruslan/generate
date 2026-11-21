using System.Windows;
using System.Windows.Input;

namespace MHBrowser;

public partial class DarkDialog : Window
{
    public bool Confirmed { get; private set; }
    public string InputText => InputBox.Text;

    public DarkDialog(string title, string message, bool isConfirm = false, string primaryText = "OK", string secondaryText = "Cancel", bool isDanger = false, bool isBusy = false, bool isInput = false)
    {
        InitializeComponent();
        Title = title;
        TitleText.Text = title;
        MessageText.Text = message;
        BtnPrimary.Content = primaryText;
        BtnSecondary.Content = secondaryText;

        if (isDanger)
        {
            BtnPrimary.Background = (System.Windows.Media.Brush)FindResource("Danger");
            BtnPrimary.BorderBrush = (System.Windows.Media.Brush)FindResource("Danger");
            BtnPrimary.Foreground = System.Windows.Media.Brushes.White;
        }

        if (isConfirm || isInput)
            BtnSecondary.Visibility = Visibility.Visible;

        if (isInput)
        {
            InputBox.Visibility = Visibility.Visible;
            Loaded += (_, _) => InputBox.Focus();
        }

        if (isBusy)
        {
            BusyBar.Visibility = Visibility.Visible;
            FooterPanel.Visibility = Visibility.Collapsed;
            BtnX.Visibility = Visibility.Collapsed;
        }
    }

    public void UpdateBusyMessage(string message) => Dispatcher.BeginInvoke(() => MessageText.Text = message);

    private void Header_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }

    private void InputBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { Confirmed = true; Close(); }
        else if (e.Key == Key.Escape) { Confirmed = false; Close(); }
    }

    private void BtnYes_Click(object sender, RoutedEventArgs e)
    {
        Confirmed = true;
        Close();
    }

    private void BtnNo_Click(object sender, RoutedEventArgs e)
    {
        Confirmed = false;
        Close();
    }

    public static void ShowInfo(Window? owner, string title, string message)
    {
        var d = new DarkDialog(title, message, isConfirm: false);
        if (owner is not null && owner.IsLoaded) d.Owner = owner;
        else d.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        d.ShowDialog();
    }

    public static bool ShowConfirm(Window? owner, string title, string message, string yesText = "Yes", string noText = "Cancel", bool danger = false)
    {
        var d = new DarkDialog(title, message, isConfirm: true, primaryText: yesText, secondaryText: noText, isDanger: danger);
        if (owner is not null && owner.IsLoaded) d.Owner = owner;
        else d.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        d.ShowDialog();
        return d.Confirmed;
    }

    public static string? ShowInput(Window? owner, string title, string message, string okText = "Continue")
    {
        var d = new DarkDialog(title, message, isConfirm: true, primaryText: okText, secondaryText: "Cancel", isInput: true);
        if (owner is not null && owner.IsLoaded) d.Owner = owner;
        else d.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        d.ShowDialog();
        return d.Confirmed ? d.InputText : null;
    }
}
