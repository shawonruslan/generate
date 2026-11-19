using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace MHVirtualCam;

/// <summary>Playlist row icon: film geometry for video, image geometry for images.</summary>
public sealed class KindIconConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var key = value is MediaKind.Video ? "IconFilm" : "IconImage";
        return Application.Current.TryFindResource(key) as Geometry ?? Geometry.Empty;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
