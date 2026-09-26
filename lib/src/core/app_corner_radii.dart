/// The app's corner radii as NUMBERS — the one place the chrome's shapes
/// (`AppShapes`) and the printed sheets read them from.
///
/// They live here, inward of `ui/`, because a sheet's page is decided in
/// `models/` (the conte's marks), and a model may not reach `ui/theme` —
/// the corner a printed picture frame wears is still the app's corner
/// (유저 2026-09-25: 「지브리콘티처럼 모서리 둥글게하자. 우리 앱 통일
/// 모서리 따라서」). What the corner LOOKS like — a superellipse on flat
/// sides — and why the two families differ is `AppShapes`' to say.
abstract final class AppCornerRadii {
  /// A control's corner as a fraction of its short axis.
  static const double controlRatio = 0.28;

  /// A window: dialogs, menus, popovers — and a picture window cut into a
  /// printed frame.
  static const double window = 6;

  /// A well cut into a surface. The smallest corner the app draws.
  static const double well = 4;

  /// A panel floating over the artwork.
  static const double floatingPanel = 14;
}
