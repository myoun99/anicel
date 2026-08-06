import 'package:flutter/material.dart';

import 'app_accents.dart';

/// The app-wide dark palette (TVPaint/OpenToonz-style flat charcoal).
///
/// Every UI color that is not derived from [ColorScheme] at build time should
/// reference one of these constants so the palette stays adjustable in one
/// place. The accent is deliberately a single hue used sparingly: playhead,
/// selection, active states.
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

  /// Darkest backdrop: canvas surround, scaffold background.
  static const Color backdrop = Color(0xFF141517);

  /// Panel body surface.
  static const Color surface = Color(0xFF1E2022);

  /// Panel headers and toolbars.
  static const Color surfaceRaised = Color(0xFF26282B);

  /// Hover fills and exposure blocks — one step above raised.
  static const Color surfaceHigh = Color(0xFF303336);

  /// The two WASHES: the only neutrals that are painted AT ALPHA over a fill,
  /// and that may never be poured into a rectangle of their own.
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

  /// Hairline borders between panels and cells.
  static const Color hairline = Color(0xFF37393C);

  /// Emphasized borders (block outlines, dividers that must read clearly).
  static const Color hairlineStrong = Color(0xFF45494E);

  /// Primary text and icons.
  static const Color text = Color(0xFFB4B8BB);

  /// Secondary text and inactive icons.
  static const Color textDim = Color(0xFF7C8184);

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

ColorScheme _buildColorScheme() {
  // Non-const: the accent is LIVE now (UI-R22 #5) — the app root
  // rebuilds the theme when the accent settings change.
  return ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: const Color(0xFF10201E),
    primaryContainer: const Color(0xFF27443F),
    onPrimaryContainer: const Color(0xFFA5D6D0),
    secondary: AppColors.accent,
    onSecondary: const Color(0xFF10201E),
    secondaryContainer: const Color(0xFF2A3A38),
    onSecondaryContainer: const Color(0xFFA5D6D0),
    error: AppColors.danger,
    onError: Color(0xFF2B1212),
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceDim: AppColors.backdrop,
    surfaceContainerLowest: AppColors.backdrop,
    surfaceContainerLow: Color(0xFF1A1C1E),
    surfaceContainer: Color(0xFF232527),
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surfaceRaised,
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
      backgroundColor: AppColors.surfaceRaised,
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
          return AppColors.textDim;
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
