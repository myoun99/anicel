import 'package:flutter/material.dart';

import '../layout/device_grid.dart';
import '../theme/app_theme.dart';

// What every icon button's face measures, paints and inks — the
// [AppIconButton]'s and the rail's glyph's (`RailGlyphButton`) alike, so
// neither file has to import the other to share them.

/// What a button's box measures — a named token, or a box its PARENT
/// already promised.
///
/// 🚨★★★ONE FIELD, TWO KINDS. [AppIconButton] holds a single [size], so
/// "which of the two decides the box?" is not a question the widget can be
/// asked — a `size` token beside a nullable `box` would have let a caller
/// pass both, and the day they disagreed the button would have had two
/// owners for one number ([[make-the-invariant-unrepresentable]]).
abstract interface class AppIconButtonMetrics {
  double get minWidth;
  double get maxWidth;
  double get height;
  double get iconSize;

  /// True when a PARENT sized this box, so the numbers are used verbatim.
  /// A token's are quantized onto the device grid first; a promised box is
  /// not ours to round.
  bool get parentOwnsBox;
}

/// A box the parent already promised — the rails' 20–22px slots and the
/// top strip's 32px group, where the surrounding layout was built around a
/// number before the button existed.
///
/// ⛔THIS IS NOT A SIXTH TOKEN. A token names a PLACE and is reused; this
/// says "the caller owns this one" and is passed at the call site, so it
/// cannot quietly become a new default for anyone else. It exists because
/// 실측 on 2026-08-28 found 36 hand-rolled `IconButton`s that could not join
/// a token without their box changing, and a box that changes is exactly
/// what the rail cannot survive ([[widget-between-slot-and-plate]]).
class AppIconButtonBox implements AppIconButtonMetrics {
  const AppIconButtonBox({
    required double width,
    required this.height,
    required this.iconSize,
  }) : minWidth = width,
       maxWidth = width;

  @override
  final double minWidth;
  @override
  final double maxWidth;
  @override
  final double height;
  @override
  final double iconSize;

  @override
  bool get parentOwnsBox => true;
}

/// ⛔A NEW TOKEN IS NOT A FREE MOVE. Adding one because a number is off by
/// two is how five becomes fifteen; each token below names a PLACE that
/// argued for its size, and the argument is in its doc.
enum AppIconButtonSize implements AppIconButtonMetrics {
  /// Panel bottom bars — the reference size.
  bar(minWidth: 26, maxWidth: 30, height: 24, iconSize: 18),

  /// Slim panel status strips.
  strip(minWidth: 22, maxWidth: 26, height: 20, iconSize: 15),

  /// The TOOL RAIL's square. 42 is a stylus target the rail was narrowed
  /// AROUND (R9 #17: a tight box, so the slim rail holds the button instead
  /// of the button dictating a 72px rail) — shrinking it here would reopen
  /// that decision from the wrong end.
  tool(minWidth: 42, maxWidth: 42, height: 42, iconSize: 20),

  /// Timeline lanes and the workspace chrome: a bar button with a smaller
  /// glyph, because the row it sits in is shorter than a panel's.
  dense(minWidth: 24, maxWidth: 28, height: 22, iconSize: 16),

  /// Window chrome and the debug inspector — the smallest the app draws,
  /// where the button is beside text rather than in a row of its own.
  micro(minWidth: 20, maxWidth: 24, height: 18, iconSize: 14),

  /// Dialogs and menus, where the button sits among Material's own metrics
  /// and a 18px glyph would read as a different control.
  standard(minWidth: 36, maxWidth: 40, height: 36, iconSize: 24);

  const AppIconButtonSize({
    required this.minWidth,
    required this.maxWidth,
    required this.height,
    required this.iconSize,
  });

  @override
  final double minWidth;
  @override
  final double maxWidth;
  @override
  final double height;
  @override
  final double iconSize;

  @override
  bool get parentOwnsBox => false;
}

/// [size]'s box as the device grid draws it — for every face that wears an
/// icon button's metrics: [AppIconButton] and the rail's glyph
/// (`RailGlyphButton`).
///
/// 🎯The single largest source of off-grid PAINTED edges in this app — 34
/// of them came from [AppIconButton], because every toolbar and rail button
/// was one and each draws its shape at its own bounds (a Material shape
/// until 2026-09-10, a [ShapeDecoration] since — the bounds are what matter,
/// and they did not move). `controlLarge` is 42, and 42 × 1.25 = 52.5.
///
/// ⚠️MEASURED, and smaller than it looks: painted boxes off the grid go 350
/// → 340 at 1.25 and 356 → 356 at 1.35. Size quantization alone buys almost
/// nothing while ORIGINS are off, because a box whose origin is fractional
/// has a fractional far edge whatever its width. What this actually earns is
/// that the button stops ADDING a fraction — it is what keeps the row on the
/// grid once the origins are fixed, not what fixes them.
///
/// ⛔So do not read this as the pattern to copy across the other wrappers:
/// the same edit on five more of them would cost five diffs for the same
/// ~3%. The origins are the lever.
/// ⛔A PROMISED BOX IS NOT OURS TO ROUND. The rails' slots are 20–22px
/// numbers the surrounding layout was built around, and
/// [[widget-between-slot-and-plate]] is the record of what a changed slot
/// costs — a hundred tests that never mention it. Quantizing a token is a
/// style choice; quantizing a promise is breaking it.
({double minWidth, double maxWidth, double height}) appIconButtonBoxOnGrid(
  BuildContext context,
  AppIconButtonMetrics size,
) {
  if (size.parentOwnsBox) {
    return (
      minWidth: size.minWidth,
      maxWidth: size.maxWidth,
      height: size.height,
    );
  }
  final grid = DeviceGrid.of(context);
  return (
    minWidth: grid.position(size.minWidth),
    maxWidth: grid.position(size.maxWidth),
    height: grid.position(size.height),
  );
}

/// An icon button's box: the app's control corner for its OWN height — a
/// bar button and a strip button are different sizes, and the corner is a
/// RATIO of the short axis, so each asks for its own — with the edge drawn
/// when [outlined] ([AppIconButton.outlined]).
///
/// One shape for every face that wears it: [AppIconButtonFace] and the
/// rail's glyph (`RailGlyphButton`).
ShapeBorder appIconButtonShape(
  double height, {
  required bool outlined,
  required bool danger,
  required bool isSelected,
}) => AppShapes.control(
  height,
  side: outlined
      ? BorderSide(
          color: danger
              ? AppColors.danger
              : isSelected
              ? AppColors.accent
              : AppColors.hairlineStrong,
        )
      : BorderSide.none,
);

/// THE INK OF AN ICON BUTTON — its glyph's colour and the state layer under
/// it, for whatever state it is in — read in Material's ORDER: the button's
/// own style (the accent on the ON state, [AppColors.danger] while something
/// is wrong), then the app's `IconButtonTheme`, then M3's defaults; the first
/// non-null answer wins, as in `ButtonStyleButton`.
///
/// Read once per build and asked per state: a face that tracks its own hover
/// and press (the app's, [RenderIconButtonPressFace], and the rail's glyph,
/// `RailGlyphButton`) asks it again at paint without the context — the two
/// faces cannot come to wear different ink.
final class IconButtonInk {
  IconButtonInk.of(
    BuildContext context, {
    required bool isSelected,
    required bool danger,
  }) : _own = danger
           ? _dangerInk
           : isSelected
           ? _accentInk
           : null,
       _theme = IconButtonTheme.of(context).style,
       _defaults = _m3DefaultsFor(
         Theme.of(context).colorScheme,
       ),
       _asksIconColor = true;

  /// A TEXT button's ink, in `TextButton`'s order: the app's
  /// `TextButtonTheme`, then M3's `TextButton` defaults — what the
  /// toolbar's word buttons wore while they were Material `TextButton`s
  /// (`CommaButton`). They say no colour of their own: their style is
  /// their box.
  IconButtonInk.textButton(BuildContext context)
    : _own = null,
      _theme = TextButtonTheme.of(context).style,
      _defaults = _m3TextDefaultsFor(Theme.of(context).colorScheme),
      _asksIconColor = false;

  /// Whether the foreground asks the theme's `iconColor` first — an icon
  /// button's glyph does, a text button's word never does.
  final bool _asksIconColor;

  /// 🚨DANGER OUTRANKS SELECTED. The red is about the thing the button acts
  /// on and stands until that is fixed; selected says only that its popover
  /// is open this instant.
  final ButtonStyle? _own;
  final ButtonStyle? _theme;
  final ButtonStyle _defaults;


  /// The button's OWN style on the ON state — the same
  /// `IconButton.styleFrom(foregroundColor: AppColors.accent)` it asked for
  /// while it wrapped a Material `IconButton`, which also derives the
  /// accent's state layer. Off, the button has no colour of its own and the
  /// theme answers.
  static ButtonStyle get _accentInk => IconButton.styleFrom(
    foregroundColor: AppColors.accent,
  );

  /// The same one step, in [AppColors.danger] — so the state layer under a
  /// hover or a press is derived from the red the glyph is wearing rather
  /// than from the accent it is not.
  static ButtonStyle get _dangerInk => IconButton.styleFrom(
    foregroundColor: AppColors.danger,
  );

  /// M3's `IconButton` defaults (`_IconButtonDefaultsM3`), the last step —
  /// built through the same `styleFrom`, so the state layer is Material's
  /// own arithmetic: 0.1 pressed, 0.08 hovered, 0.1 focused. Their selected
  /// branches are left out because [_accentInk] always answers there first.
  /// One per colour scheme: a face rebuilds on every focus change.
  static final Expando<ButtonStyle> _m3Defaults = Expando<ButtonStyle>(
    'M3 icon button defaults',
  );

  static ButtonStyle _m3DefaultsFor(ColorScheme scheme) =>
      _m3Defaults[scheme] ??= IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
      );

  /// M3's `TextButton` defaults (`_TextButtonDefaultsM3`) the same way: the
  /// primary, and the state layer `styleFrom` derives from it.
  static final Expando<ButtonStyle> _m3TextDefaults = Expando<ButtonStyle>(
    'M3 text button defaults',
  );

  static ButtonStyle _m3TextDefaultsFor(ColorScheme scheme) =>
      _m3TextDefaults[scheme] ??= TextButton.styleFrom(
        foregroundColor: scheme.primary,
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
      );

  /// `ButtonStyleButton`'s rule: resolve each step against [states] in
  /// order, and the first non-null answer wins.
  static Color? _firstResolved(
    Set<WidgetState> states,
    List<WidgetStateProperty<Color?>?> steps,
  ) {
    for (final step in steps) {
      final color = step?.resolve(states);
      if (color != null) {
        return color;
      }
    }
    return null;
  }

  /// `ButtonStyleButton`'s icon colour — or, for a text button, its
  /// foreground. The own- and default-style `iconColor` steps are dropped:
  /// `styleFrom` never sets one, so only a theme can answer there.
  Color foreground(Set<WidgetState> states) =>
      _firstResolved(states, [
        if (_asksIconColor) _theme?.iconColor,
        _own?.foregroundColor,
        _theme?.foregroundColor,
        _defaults.foregroundColor,
      ])!;

  /// The state layer. A disabled Material button's ink drew none, and at
  /// rest every step answers null — so nothing is painted, as with the ink.
  Color? overlay(Set<WidgetState> states) =>
      states.contains(WidgetState.disabled)
      ? null
      : _firstResolved(states, [
          _own?.overlayColor,
          _theme?.overlayColor,
          _defaults.overlayColor,
        ]);

  /// Equal while every step is the SAME style object — the theme's and the
  /// defaults' are kept per scheme, so a rebuild in the same theme is equal.
  @override
  bool operator ==(Object other) =>
      other is IconButtonInk &&
      identical(other._own, _own) &&
      identical(other._theme, _theme) &&
      identical(other._defaults, _defaults) &&
      other._asksIconColor == _asksIconColor;

  @override
  int get hashCode => Object.hash(
    identityHashCode(_own),
    identityHashCode(_theme),
    identityHashCode(_defaults),
    _asksIconColor,
  );
}

/// THE BOX AN ICON BUTTON HUGS ITS GLYPH IN — the box's numbers enforced
/// inside what the parent allows (the face's old `ConstrainedBox`), then
/// `Align(widthFactor: 1, heightFactor: 1)`: the glyph laid out LOOSE in
/// that, the box as big as the glyph within it, the glyph centred.
/// ⚠️NOT `Center`, which expands to the max width and would widen every bar
/// button by four pixels.
///
/// One rule for every face that wears an icon button's box: the app's,
/// around a widget glyph ([RenderIconButtonPressFace]), and the rail's,
/// around a glyph it paints itself (`RenderRailGlyphFace`).
({Size size, Offset glyphOffset}) layOutIconButtonBox(
  BoxConstraints parent,
  BoxConstraints box,
  Size Function(BoxConstraints loose) layOutGlyph,
) {
  final face = box.enforce(parent);
  final glyph = layOutGlyph(face.loosen());
  final size = face.constrain(glyph);
  return (
    size: size,
    glyphOffset: Alignment.center.alongOffset(size - glyph as Offset),
  );
}

/// THE STATE LAYER UNDER AN ICON BUTTON'S GLYPH — [IconButtonInk.overlay]
/// for the state it is in, filling its shape — painted as the face's old
/// `DecoratedBox` painted it, by every face that tracks its own hover and
/// press: the app's ([RenderIconButtonPressFace]) and the rail's glyph
/// (`RenderRailGlyphFace`). At rest the overlay is null and only an
/// outlined shape's edge is drawn.
final class IconButtonLayer {
  /// [onChanged] repaints the face — what a decoration calls when an image
  /// it waits for arrives.
  IconButtonLayer(this._onChanged);

  final VoidCallback _onChanged;
  BoxPainter? _painter;
  ShapeDecoration? _decoration;

  /// [decoration] — the shape, filled with the overlay — over [rect].
  void paint(
    Canvas canvas,
    Rect rect,
    ShapeDecoration decoration,
    TextDirection textDirection,
  ) {
    if (_painter == null || decoration != _decoration) {
      _painter?.dispose();
      _painter = decoration.createBoxPainter(_onChanged);
      _decoration = decoration;
    }
    _painter!.paint(
      canvas,
      rect.topLeft,
      ImageConfiguration(size: rect.size, textDirection: textDirection),
    );
  }

  void dispose() => _painter?.dispose();
}

/// Where the keyboard's focus is, as an icon button shows it: not on it;
/// on it but unseen — the pointer is driving, and M3 shows the focus layer
/// for KEYBOARD focus only; or on it and shown.
enum IconButtonFocus { away, held, shown }
