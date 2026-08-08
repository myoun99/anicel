import 'package:flutter/material.dart';

import 'app_accents.dart';

/// The app-wide dark palette (TVPaint/OpenToonz-style flat charcoal).
///
/// Every UI color that is not derived from [ColorScheme] at build time should
/// reference one of these constants so the palette stays adjustable in one
/// place. The accent is deliberately a single hue used sparingly: playhead,
/// selection, active states.
///
/// THE RULE: a neutral is a FILL, a LINE, an INK or a WASH — never two of
/// those. That is what the old palette broke, and why it read as six greys
/// that nobody could tell apart: #26282B was a toolbar AND the ink written on
/// timeline paper, #303336 was the top strip AND a pressed tool button,
/// #1A1C1E was "furthest back" AND a labelled cell in a data table.
///
/// So there are exactly THREE FILLS. [backdrop] is below every chrome
/// surface. [surface] is every opaque chrome surface, with no exceptions —
/// the top strip, the tool rail, panel bodies, tab strips, dock backgrounds
/// and section bands are all one colour, because they are all the same thing.
/// [surfaceHigh] is never at rest: it is a control the pointer is on or that
/// is switched on, and the surfaces the pointer summons (menus, tooltips).
///
/// The third level is spent UPWARD on state rather than downward on a floor,
/// because the floor is the artwork now.
abstract final class AppColors {
  /// The LIVE accent settings (UI-R22 #5): the app root rebuilds its
  /// theme off this notifier; the session restores/persists it.
  static final ValueNotifier<AppAccentSettings> accentSettings =
      ValueNotifier<AppAccentSettings>(const AppAccentSettings());

  /// The accent — selection, playhead, active toggles (default teal;
  /// customizable, UI-R22 #5).
  static Color get accent => accentSettings.value.accent;

  /// FILL 1 — below every chrome surface: the scaffold, a well cut into a
  /// panel, the ring that separates a floating panel from the artwork.
  static const Color backdrop = Color(0xFF141517);

  /// FILL 2 — every opaque chrome surface, no exceptions. The app talking
  /// about itself.
  static const Color surface = Color(0xFF1E2022);

  /// FILL 3 — never at rest: a control the pointer is on or that is switched
  /// on, and the surfaces the pointer summons (menus, tooltips).
  static const Color surfaceHigh = Color(0xFF303336);

  /// The two SHADES of the chrome: a wash laid over a fill, or the resting
  /// plate of something that sits ON a fill (a storyboard cut block, a
  /// section band). What they may never be is a chrome surface themselves —
  /// there are three of those and these are not among them.
  ///
  /// They exist because a wash used to borrow whichever surface happened to
  /// sit one step away, and those surfaces are collapsing into ONE fill — a
  /// wash mixed with the very surface it washes composites to nothing at all.
  /// The readouts that ride on them ("past the cut end", "outside the
  /// playback range", "outside the sheet") are colour-only, with no line or
  /// glyph behind them, so they would not degrade, they would disappear.
  ///
  /// [washUp] lifts the fill beneath it; [washDown] sinks it.
  static const Color washUp = Color(0xFF26282B);
  static const Color washDown = Color(0xFF1A1C1E);

  /// LINE — a seam between cells inside one surface.
  static const Color hairline = Color(0xFF37393C);

  /// LINE — a grip you have not touched yet: block outlines, field borders,
  /// a scrollbar thumb at rest.
  static const Color hairlineStrong = Color(0xFF45494E);

  /// LINE — your pointer is on the grip itself. The interaction half of what
  /// used to be [textDim]; it left the text family, because a colour cannot
  /// be both "this text is secondary" and "your hand is here".
  static const Color gripHover = Color(0xFF7C8184);

  /// LINE — the one line that must read on chrome AND on near-white sheet
  /// paper in the same stroke: the 1-second beat, drawn straight across
  /// exposed blocks and empty rows alike.
  ///
  /// It used to borrow the secondary INK, and when that ink was raised for
  /// legibility on dark chrome the beat came along for the ride and lost the
  /// paper — 3.19:1 to 2.08:1. A colour cannot be both "this text is
  /// secondary" and "the strongest line on the sheet", so it is its own line
  /// now, held at the mid-tone that survives both substrates.
  static const Color beatLine = Color(0xFF7C8184);

  /// INK — primary text and icons.
  static const Color text = Color(0xFFB4B8BB);

  /// INK — secondary text and inactive icons. Raised from the old #7C8184,
  /// which sat at 4.15:1 on the panel surface: it was the app's most-read
  /// colour (116 sites) and it was the least legible one.
  static const Color textDim = Color(0xFF9DA2A6);

  /// Muted red for destructive/warning marks (cut-end boundary).
  static const Color danger = Color(0xFFC95C5C);
}

/// The app's one corner.
///
/// There is a single button in this app. Not a single button WIDGET — a
/// single button SHAPE, worn by the tool buttons, the panel buttons, the
/// project chips, the overflow, and the buttons inside the timeline alike.
/// They differ in size and in nothing else.
///
/// The corner is a SUPERELLIPSE, and only the corner is. Drawing the whole
/// rectangle as a superellipse bows the straight edges, which is wrong at
/// any size and ridiculous at panel size; [RoundedSuperellipseBorder]
/// rounds the four corners on a superellipse and leaves the sides flat, so
/// a 1800px edge with a 20px radius shows no bow at all.
///
/// Two families, because they are answering different questions:
///
///  * A CONTROL's radius is a fixed fraction of its own size
///    ([controlCornerRatio]), so the family reads as one shape at 42, 34
///    and 32. Scaling a control without scaling its corner is what makes a
///    small button look like a different button.
///  * A CONTAINER's radius is absolute. A panel is not a big button, and a
///    ratio would give a 350px-tall timeline a 98px corner.
abstract final class AppShapes {
  /// A control's corner as a fraction of its short axis.
  static const double controlCornerRatio = 0.28;

  /// The three control sizes: the rail/strip button, the dialog action and
  /// chip, the dense inline control.
  static const double controlLarge = 42;
  static const double controlMedium = 34;
  static const double controlSmall = 32;

  /// The corner a control of [size] wears.
  static double controlRadius(double size) => size * controlCornerRatio;

  /// A window that the pointer summoned: dialogs, menus, popovers.
  static const double windowRadius = 6;

  /// A well cut into a surface: text fields, swatches, inline plates. The
  /// smallest corner the app draws.
  static const double wellRadius = 4;

  /// A panel FLOATING over the artwork — the timeline, and whatever else
  /// comes to rest on the canvas rather than beside it. Deliberately larger
  /// than [windowRadius]: a floating panel has to read as a separate object
  /// lying on the drawing, not as a region of chrome that happens to end.
  static const double floatingPanelRadius = 14;

  /// The shape of a control whose short axis is [size].
  static RoundedSuperellipseBorder control(
    double size, {
    BorderSide side = BorderSide.none,
  }) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(controlRadius(size))),
    side: side,
  );

  /// The shape of a container with an absolute [radius] — one of
  /// [windowRadius], [wellRadius] or [floatingPanelRadius].
  static RoundedSuperellipseBorder container(
    double radius, {
    BorderSide side = BorderSide.none,
  }) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(radius)),
    side: side,
  );

  /// A container whose corners are not all the same — a region that floats
  /// over the artwork on some edges and lies on the window's own edge on
  /// others, where a rounded corner would show the scaffold through the
  /// notch instead of the drawing.
  static RoundedSuperellipseBorder containerRadius(
    BorderRadius radius, {
    BorderSide side = BorderSide.none,
  }) => RoundedSuperellipseBorder(borderRadius: radius, side: side);

  /// ⛔There is no clipper here any more — clip with `SuperellipseClip`.
  ///
  /// It used to be `ShapeBorderClipper` inside a `ClipPath`, chosen over
  /// `ClipRSuperellipse` because that widget's `hitTest` asks only
  /// `outerRect.contains()`, so the four corners it visibly cuts away
  /// still swallow pointers — a floating panel drawn that way eats
  /// strokes in a square of empty canvas at each corner. That reasoning
  /// is intact and `SuperellipseClip` keeps it, by asking
  /// `RSuperellipse.contains`, which is exact.
  ///
  /// What it does NOT keep is the `Path`: `pushClipPath` shifts the path
  /// by the paint offset, allocating a fresh `Path` — and therefore a
  /// fresh generation id, and therefore a clip-mask cache miss — on every
  /// single paint, at every clip site, forever. The engine's superellipse
  /// op takes a value instead.
  ///
  /// (`ContinuousRectangleBorder` remains out for its own reason: it is
  /// not a superellipse at all, it is a squircle-ish approximation that
  /// reads as a lozenge.)
}

/// Every popup menu opens INSTANTLY (R4 #2): Material's default grow +
/// staggered item fade read as entries appearing one by one — pass this to
/// each `showMenu`/`PopupMenuButton` as `popUpAnimationStyle`.
const AnimationStyle instantMenuAnimation = AnimationStyle(
  duration: Duration.zero,
  reverseDuration: Duration.zero,
);

/// The one outline every text input wears: hairline at rest, accent on
/// focus, danger on error, 4px corners. Inline cell editors that must stay
/// bare opt out at the call site with `filled: false` + [InputBorder.none].
/// A field is the one control that cannot take [AppShapes]: Material wants
/// an [InputBorder] here, and the superellipse borders are [OutlinedBorder]s.
/// It still reads its radius from the same place, so the well corner moves
/// once when it moves.
OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
  borderRadius: const BorderRadius.all(Radius.circular(AppShapes.wellRadius)),
  borderSide: BorderSide(color: color),
);

/// The accent washed into the panel surface.
///
/// The container roles used to be six frozen teal literals that did NOT
/// follow the live accent, so any of the seven non-teal presets stranded the
/// active-row tint, the storyboard chips and the layer controls on green —
/// and painted dark teal text on a red fill in the export queue. Deriving
/// them costs two lines and makes the accent mean something again.
///
/// The alphas are chosen to land on the values those literals had, so
/// switching to a derivation is not also a visual change.
Color _accentWash(double alpha) => Color.alphaBlend(
  AppColors.accent.withValues(alpha: alpha),
  AppColors.surface,
);

ColorScheme _buildColorScheme() {
  // Non-const: the accent is LIVE now (UI-R22 #5) — the app root
  // rebuilds the theme when the accent settings change.
  return ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: AppColors.backdrop,
    primaryContainer: _accentWash(0.26),
    onPrimaryContainer: AppColors.text,
    secondary: AppColors.accent,
    onSecondary: AppColors.backdrop,
    secondaryContainer: _accentWash(0.20),
    onSecondaryContainer: AppColors.text,
    error: AppColors.danger,
    onError: AppColors.backdrop,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    // THREE FILLS. Everything inert is one surface; the container ladder
    // below is not six steps of chrome any more, it is one chrome plus the
    // floor beneath it plus the one level reserved for state.
    surfaceDim: AppColors.backdrop,
    surfaceContainerLowest: AppColors.backdrop,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surface,
    onSurfaceVariant: AppColors.textDim,
    outline: AppColors.hairlineStrong,
    outlineVariant: AppColors.hairline,
  );
}

/// The single app theme: flat dark surfaces, hairline borders, compact
/// icon-first controls with tooltips.
ThemeData buildAppTheme() {
  final colorScheme = _buildColorScheme();
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.backdrop,
    canvasColor: AppColors.surface,
    dividerColor: AppColors.hairline,
    visualDensity: VisualDensity.compact,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      toolbarHeight: 40,
      titleTextStyle: TextStyle(
        color: AppColors.textDim,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.text, size: 20),
    // THE line that makes "one button shape" true rather than aspirational.
    // Without a shape here every IconButton in the app falls through to M3's
    // default StadiumBorder — a PILL, which is further from the app's corner
    // than the plain rounding it replaced — and there are 71 of them across
    // 32 files, including every button in the timeline. One line reaches all
    // of them; the alternative is 32 files of hand-application, which is
    // exactly how the shape ended up living in 12 places.
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.text,
        disabledForegroundColor: AppColors.textDim.withValues(alpha: 0.5),
        iconSize: 20,
        padding: const EdgeInsets.all(6),
        minimumSize: const Size(32, 32),
        shape: AppShapes.control(AppShapes.controlSmall),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    // Dialog actions are the only place these two buttons appear (the one
    // toolbar TextButton — the comma group — sets its own minimumSize), so
    // sizing them here gives every window the same generous action row: a
    // 34px tall pair with 6px corners, cancel and confirm the same size.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.text,
        disabledForegroundColor: AppColors.textDim.withValues(alpha: 0.5),
        minimumSize: const Size(96, AppShapes.controlMedium),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: AppShapes.control(AppShapes.controlMedium),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(96, AppShapes.controlMedium),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: AppShapes.control(AppShapes.controlMedium),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    // Every window's MATERIAL, decided once: the panel surface, a hairline
    // border and 6px corners (M3's default is a 28px tinted blob that
    // floats off the charcoal), no elevation tint, and a barrier light
    // enough to keep the drawing visible behind it.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: AppShapes.container(
        AppShapes.windowRadius,
        side: const BorderSide(color: AppColors.hairline),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      titleTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
      actionsPadding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
    ),
    // Boxed fields sunk to the backdrop, so a field reads as a well on the
    // panel surface rather than as a stray underline.
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.backdrop,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      border: _fieldBorder(AppColors.hairlineStrong),
      enabledBorder: _fieldBorder(AppColors.hairlineStrong),
      focusedBorder: _fieldBorder(AppColors.accent),
      disabledBorder: _fieldBorder(AppColors.hairline),
      errorBorder: _fieldBorder(AppColors.danger),
      focusedErrorBorder: _fieldBorder(AppColors.danger),
      labelStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
      floatingLabelStyle: TextStyle(color: AppColors.accent, fontSize: 12),
      hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
      errorStyle: const TextStyle(color: AppColors.danger, fontSize: 11),
    ),
    // ⛔NOT "stragglers only" — that comment was wrong for as long as it
    // stood. `MaterialScrollBehavior.buildScrollbar` puts a framework
    // Scrollbar on EVERY vertical scrollable on desktop, so this theme has
    // been dressing some thirty real surfaces, not a hypothetical one.
    //
    // It keeps them on the same visuals as [AppScrollbar]: thin grey thumb,
    // brighter under the pointer, accent while pressed, no track. 🐛And the
    // THICKNESS is constant, which it was not: this property used to resolve
    // 6 on hover/drag, so the app's own bars held still under the pointer
    // while the framework's grew — the one divergence the user could see
    // (유저: 호버중에 크기가 커지는데? 안커지도록). It came from here, not
    // from Flutter's defaults.
    //
    // What this theme still governs after the scroll BEHAVIOUR takes over
    // the rest: the dropdown and MenuAnchor menus. Both wrap themselves in
    // `copyWith(scrollbars: false)` and build their own Scrollbar, so no
    // ScrollBehavior can reach them and this is their only styling.
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll<bool>(true),
      trackVisibility: const WidgetStatePropertyAll<bool>(false),
      thickness: const WidgetStatePropertyAll<double>(4),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.dragged)) {
          return AppColors.accent;
        }
        if (states.contains(WidgetState.hovered)) {
          return AppColors.gripHover;
        }
        return AppColors.hairlineStrong;
      }),
      trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceHigh,
      shape: AppShapes.container(
        AppShapes.windowRadius,
        side: const BorderSide(color: AppColors.hairline),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll<Color>(
          AppColors.surfaceHigh,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          AppShapes.container(
            AppShapes.windowRadius,
            side: const BorderSide(color: AppColors.hairline),
          ),
        ),
      ),
    ),
    // A tooltip carries a SHAPE now rather than a BoxDecoration's radius,
    // which is the only way a Material tooltip can wear a superellipse.
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: ShapeDecoration(
        color: AppColors.surfaceHigh,
        shape: AppShapes.container(AppShapes.wellRadius),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
  );
}
