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

  /// Accent 1 — selection, playhead, active toggles (default teal;
  /// customizable, UI-R22 #5).
  static Color get accent => accentSettings.value.accent;

  /// Accent 2 — the SECONDARY highlight (repeat pattern spans, selected
  /// union diamonds): the complement of accent 1 unless overridden.
  static Color get accent2 => accentSettings.value.accent2;

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

  /// INK — primary text and icons.
  static const Color text = Color(0xFFB4B8BB);

  /// INK — secondary text and inactive icons. Raised from the old #7C8184,
  /// which sat at 4.15:1 on the panel surface: it was the app's most-read
  /// colour (116 sites) and it was the least legible one.
  static const Color textDim = Color(0xFF9DA2A6);

  /// Muted red for destructive/warning marks (cut-end boundary).
  static const Color danger = Color(0xFFC95C5C);
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
OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
  borderRadius: const BorderRadius.all(Radius.circular(4)),
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
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.text,
        disabledForegroundColor: AppColors.textDim.withValues(alpha: 0.5),
        iconSize: 20,
        padding: const EdgeInsets.all(6),
        minimumSize: const Size(32, 32),
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
        minimumSize: const Size(96, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(96, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: AppColors.hairline),
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
    // Stragglers only — every app surface uses AppScrollbar; this keeps a
    // raw Flutter Scrollbar (if one ever appears) on the same S1 visuals:
    // thin grey thumb, brighter on hover, accent while dragged, no track.
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll<bool>(true),
      trackVisibility: const WidgetStatePropertyAll<bool>(false),
      thickness: WidgetStateProperty.resolveWith<double>(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? 6
            : 4,
      ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.hairline),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      textStyle: TextStyle(color: AppColors.text, fontSize: 12),
    ),
  );
}
