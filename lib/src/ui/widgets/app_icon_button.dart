import 'app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../layout/device_grid.dart';
import '../input/control_press_claim.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../theme/app_theme.dart';
import 'press_face.dart';

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

/// R26 #42 — THE app's icon button.
///
/// The canvas panel's bottom bar (fit / 1:1 / zoom / rotate / flip) is the
/// style the user adopted as the default icon UI, so it lives here now and
/// every other surface mounts THIS widget instead of hand-rolling its own
/// `InkWell` + `Icon` pair: a compact square hit target, an 18px glyph, no
/// padding, and — the selection rule ([[ui-selection-style]]) — an accent
/// FOREGROUND for the on state, never a check mark or a filled chip.
///
/// Sizing is a token, not a per-call number: [AppIconButtonSize.bar] is the
/// canvas bottom bar's, [AppIconButtonSize.strip] the same button squeezed
/// into a slim status strip. Callers pick a token so a future style change
/// lands everywhere at once.
///
/// 🚨★★★THE TOKENS ARE THE ANSWER TO 「앱에 버튼은 한 종류」, not a betrayal of
/// it. 유저 2026-08-28 chose this over collapsing every button to one size:
/// lib had **50 hand-rolled `IconButton`s across 22 files** at five different
/// glyph sizes, and 실측 said not one of them could join without the box
/// changing. ⇒ 「한 종류」 means ONE PARENT — one shape, one selection rule,
/// one hit-target policy — with the size named rather than typed.
///
/// 🚨★★★NO MATERIAL `IconButton` INSIDE ANY MORE (유저 2026-09-10, 「2번가자」
/// on board `timeline-row-controls-weigh-300-render-objects`).
///
/// Measured before the change: ONE of these was **27 render objects**, and the
/// idle screen mounts **94** of them — **47% of all 5,349** render objects the
/// app holds with nothing open. A timeline rail row carries six. Most of that
/// was not the button: it was `ButtonStyleButton`'s Material, InkWell and
/// `AnimatedTheme` (which drags a `Theme`, a `CupertinoTheme` and a
/// `DefaultSelectionStyle` in behind it) — paid for per button, whether
/// anyone hovered or not. The semantics tree mirrors every one of those
/// nodes, which is where the 「접근성 트리 10MB」 actually came from.
///
/// THE CHANGE WAS HERE AND NOWHERE ELSE, so every surface got lighter
/// together. ↩️The rail has a button of its own since 유저 10-09 (I-57 ①:
/// 「가볍기만하면 레일전용버튼해도 상관없어. 결과적으로 어디가 더
/// 가벼워지는거에따라 맞추고 통일할거 알아서 통일하고」) — `RailGlyphButton`,
/// one render object for a whole face, because a cut switch mounts every
/// rail row anew and this face of ~35 elements was most of a row. It wears
/// THIS button's ink and shape ([IconButtonInk], [appIconButtonShape]), so
/// the two still look the same as each other.
///
/// ↩️…and since 2026-10-24 THIS button wears the rail's light face too
/// (board `frame-panels-build-in-one-frame`: a tab reopened in 40–60ms, and
/// every icon button on it was ~35 elements). What a pointer and a screen
/// reader meet is ONE render object around the glyph
/// ([IconButtonPressFace]) — the press every light face is ([PressFace]);
/// only the keyboard's focus and Enter/Space stay widgets
/// ([AppIconButtonFace]).
///
/// What is KEPT, each pinned by `app_icon_button_test.dart`:
///  * the press law — [ControlPressClaim] still owns the firing;
///  * 🚨THE ARENA. The Material InkWell put a tap into the gesture arena on
///    every press, and because it was the DEEPEST tap there it WON — which
///    is the only thing that stopped an ancestor's `onTap` from firing when
///    you pressed a button inside it. The claim fires from raw pointers and
///    enters only drags, so with the InkWell gone the ancestor's tap won
///    uncontested: 🧪deleting a guide also SELECTED its row
///    (`one_symmetry_acts_many_perspectives_snap_test`). The face now enters
///    a do-nothing tap of its own, fed from the pointer events it already
///    hears — no extra node. ⚠️Disabled buttons enter none, which is what a
///    null-callback InkWell did: a tap on a dead button reaches the row;
///  * the tooltip — its look, its timing and the touch long-press. ↩️It is
///    no longer a `Tooltip` of its own (2026-10-24): the face summons the
///    one window every light face shares ([SummonedTooltip]), so a test
///    finds it with `find.railTooltip`, not `find.byTooltip`;
///  * ONE semantics node: button / enabled / selected / focusable / focused
///    and its tap action, with the tooltip on it. The tap action FIRES —
///    [AppIconButtonFace.onSemanticTap] (유저 2026-09-10);
///  * the colours, by Material's ORDER and not only its defaults: the
///    button's own style (the accent, on the ON state), then the app's
///    `IconButtonTheme`, then M3's defaults — first non-null wins, as in
///    `ButtonStyleButton`. 🧪The first cut went straight to the defaults:
///    65 of the 94 idle-screen buttons came out dimmer (glyph-colour census,
///    master vs lane, 2026-09-10), and no test saw it, because a plain
///    `MaterialApp` has no theme step to skip. One now pumps
///    `buildAppTheme()`;
///  * M3's HOVER POLICY: a mouse entering is a hover, full stop
///    (`InkResponse.handleMouseEnter` has no highlight-mode gate — and
///    `FocusableActionDetector`'s hover DOES, which is why this does not use
///    it: under a touch-mode highlight it reported no hover at all);
///  * the box: `Align(widthFactor: 1, heightFactor: 1)` inside the min/max
///    constraints — ⚠️NOT `Center`, which expands to the max width and would
///    have widened every bar button by four pixels ([layOutIconButtonBox]).
///
/// What is GONE is the ink ripple's splash. ⚠️The pressed layer is now drawn
/// from the face's own pointer events, so it no longer vanishes when a
/// press wobbles (board `press-look-dies-on-a-wobble` accepted that loss;
/// this is strictly better, and it does NOT reopen that decision's refused
/// half — nothing is threaded through the call sites, and firing is still
/// the claim's alone).
///
/// ⛔DO NOT PUT `IconButton` BACK "to get Material behaviour for free". The
/// free behaviour is the 27.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.keyValue,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isSelected = false,
    this.size = AppIconButtonSize.bar,
    this.outlined = false,
    this.danger = false,
    this.shortcuts = const [],
  });

  /// Stable widget key (the tests' handle). It lands on the
  /// [AppIconButtonFace], which is the box the user sees and presses.
  final String keyValue;
  final String tooltip;

  /// The registry actions this button is the entrance of. Their LIVE keys
  /// follow [tooltip] — 「Copy (Ctrl+C)」 — read from the bindings by the
  /// button itself, so re-recording a key re-labels every button that
  /// presses it, a cached toolbar included (I-19: 「툴팁으로 숏컷 키
  /// 보여주도록. 낡지않을구조로.」).
  final List<String> shortcuts;

  /// Usually an [Icon]; text glyphs ('1:1') are allowed — they inherit the
  /// same accent/foreground treatment.
  final Widget icon;
  final VoidCallback? onPressed;

  /// The ON state — accent ink only (UI-R21 #1: the M3 `isSelected`
  /// default was invisible in this theme, so the accent is explicit).
  final bool isSelected;

  /// The box: a named token, or an [AppIconButtonBox] the parent promised.
  final AppIconButtonMetrics size;

  /// Draws the box's EDGE — the hairline at rest, the accent while ON — for
  /// a button that stands among glyphs that only SAY something: the
  /// reference row's file button sits beside the name, where the linked
  /// row's chain is a plain badge, and the edge is what tells the two apart
  /// (the mockup the user approved on 2026-09-11 draws it so). Still the one
  /// button (「앱에 버튼은 한 종류」): the same face, its shape's side drawn.
  final bool outlined;

  /// Something is WRONG with what this button is about, and it wears
  /// [AppColors.danger] until it is not — the reference row's file button
  /// when the row asks its file for more film than the file has (유저
  /// 2026-09-12: 「참조버튼을 빨갛게」).
  ///
  /// ⛔A STATE OF THE ONE BUTTON, not a red button beside the normal one
  /// (「앱에 버튼은 한 종류」). It is exactly the shape [isSelected] already
  /// has — a flag that changes the ink and nothing else — so a second
  /// widget for it would be two buttons to keep in step forever.
  /// ⚠️Red is CHROME talking about chrome here, which is what [AppColors]
  /// reserves `danger` for; the session's red/green pair is a different
  /// colour for a different question.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final box = appIconButtonBoxOnGrid(context, size);
    // 🚨★★★ 유저 #1 (2026-08-14): 「액티브 레이어가 아닌 다른 레이어의 버튼
    // 누르면 작동안함 … 레이어에 있는 **모든 버튼이나 편집이** 그럼」.
    //
    // ★A press that lands on a control belongs to that control
    // ([value_control_pointers.dart]). That law was written for sliders and
    // splitters — and the user's report says 「모든 버튼」, which is the same
    // sentence: a BUTTON is as much the thing under the finger as a slider
    // is. Claiming here is what stops a rail row's pick from firing too,
    // which moved the drawing target and rebuilt the row out from under the
    // press that was still running.
    //
    // ⛔The claim is MOUNTED, not written here. It used to be three inline
    // `Listener` lines that [ControlPressClaim] also had — and while the
    // law lived in two places the buttons that mounted neither (the
    // x-sheet's toggles, the toolbar's 1·2·3·4·N) went unnoticed.
    // 🚨★★★WHEN it acts is not this widget's to say (유저 확정 2026-08-30):
    // a button inside a swipe column acts on the DOWN, and every other
    // button acts when it is released still inside itself. [PressFireScope]
    // holds that split in ONE place, so this hands over the callback and
    // says nothing about the moment.
    return ControlPressClaim(
      onPressed: onPressed,
      child: AppIconButtonFace(
        key: ValueKey<String>(keyValue),
        tooltip: shortcutTooltip(context, tooltip, shortcuts),
        // ⛔The face keeps the callback every claimed button keeps: silent to
        // the pointer, the press of a key. It decides the enabled look, and
        // the keyboard's Enter/Space reach it — and press, as on any other
        // button (유저 2026-10-23, board `F-450-Q1`: 「통일 — 아이콘 버튼도
        // Enter · Space 로 눌린다」). ↩️It fired nothing for a key from
        // 2026-09-10 (「탭은 다른 숏컷 쓸수도있어서 굳이 필요없을거같고」)
        // until then. ⚠️Never wire the face's POINTER path to a real
        // callback: the claim already fires every press, and a face that
        // fired too would fire twice.
        onPressed: silentPress(onPressed),
        // 🚨…but a screen reader is not a pointer: its activation arrives as
        // SemanticsAction.tap, which the claim never hears, so the node gets
        // the REAL callback (「스크린리더만 있으면좋을까싶은데」). Measured
        // before: 0 fires, on master and on the light face alike.
        onSemanticTap: onPressed,
        isSelected: isSelected,
        danger: danger,
        minWidth: box.minWidth,
        maxWidth: box.maxWidth,
        height: box.height,
        iconSize: size.iconSize,
        shape: appIconButtonShape(
          size.height,
          outlined: outlined,
          danger: danger,
          isSelected: isSelected,
        ),
        icon: icon,
      ),
    );
  }
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
           ? AppIconButtonFace._dangerInk
           : isSelected
           ? AppIconButtonFace._accentInk
           : null,
       _theme = IconButtonTheme.of(context).style,
       _defaults = AppIconButtonFace._m3DefaultsFor(
         Theme.of(context).colorScheme,
       );

  /// 🚨DANGER OUTRANKS SELECTED. The red is about the thing the button acts
  /// on and stands until that is fixed; selected says only that its popover
  /// is open this instant.
  final ButtonStyle? _own;
  final ButtonStyle? _theme;
  final ButtonStyle _defaults;

  /// `ButtonStyleButton`'s icon colour. Its own- and default-style
  /// `iconColor` steps are dropped: `styleFrom` never sets one, so only a
  /// theme can answer there.
  Color foreground(Set<WidgetState> states) =>
      AppIconButtonFace._firstResolved(states, [
        _theme?.iconColor,
        _own?.foregroundColor,
        _theme?.foregroundColor,
        _defaults.foregroundColor,
      ])!;

  /// The state layer. A disabled Material button's ink drew none, and at
  /// rest every step answers null — so nothing is painted, as with the ink.
  Color? overlay(Set<WidgetState> states) =>
      states.contains(WidgetState.disabled)
      ? null
      : AppIconButtonFace._firstResolved(states, [
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
      identical(other._defaults, _defaults);

  @override
  int get hashCode => Object.hash(
    identityHashCode(_own),
    identityHashCode(_theme),
    identityHashCode(_defaults),
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

/// The part of an [AppIconButton] the keyboard reaches: its FOCUS and the
/// Enter/Space it answers ([onPressed]) — and, under it, the press face
/// that is everything a pointer and a screen reader meet
/// ([IconButtonPressFace]): the box, the hover / pressed / focus layer, the
/// cursor, the tooltip and the one semantics node. A pointer's press is the
/// claim's to fire, never this.
///
/// Public because it is what [AppIconButton.keyValue] names: a test that
/// finds a button by its key finds THIS, exactly where the Material
/// `IconButton` used to stand.
class AppIconButtonFace extends StatefulWidget {
  const AppIconButtonFace({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.onSemanticTap,
    required this.isSelected,
    required this.danger,
    required this.minWidth,
    required this.maxWidth,
    required this.height,
    required this.iconSize,
    required this.shape,
    required this.icon,
  });

  final String tooltip;

  /// The callback [AppIconButton] hands down — silent to the pointer, the
  /// press of a key ([silentPress]): non-null means enabled.
  final VoidCallback? onPressed;

  /// What a screen reader's activation calls: the REAL callback. Its
  /// "double-tap to activate" arrives as `SemanticsAction.tap`, not as a
  /// pointer, so the claim never hears it and nothing fires twice. Null
  /// exactly when [onPressed] is.
  final VoidCallback? onSemanticTap;
  final bool isSelected;
  final bool danger;
  final double minWidth;
  final double maxWidth;
  final double height;
  final double iconSize;
  final ShapeBorder shape;
  final Widget icon;

  // ⛔STATE TRAVELS AS A `WidgetState` SET, NOT A ROW OF BOOLEANS. Five
  // named flags is what the wide-signature ratchet
  // (`clean_code_stays_measured_test`) stopped — and Material speaks in
  // `WidgetState` too, which is what lets every colour below come straight
  // out of Material's own `ButtonStyle`s.

  /// The button's OWN style on the ON state — the same
  /// `IconButton.styleFrom(foregroundColor: AppColors.accent)` it asked for
  /// while it wrapped a Material `IconButton`, which also derives the
  /// accent's state layer. Off, the button has no colour of its own and the
  /// theme answers.
  static final ButtonStyle _accentInk = IconButton.styleFrom(
    foregroundColor: AppColors.accent,
  );

  /// The same one step, in [AppColors.danger] — so the state layer under a
  /// hover or a press is derived from the red the glyph is wearing rather
  /// than from the accent it is not.
  static final ButtonStyle _dangerInk = IconButton.styleFrom(
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

  @override
  State<AppIconButtonFace> createState() => _AppIconButtonFaceState();
}

class _AppIconButtonFaceState extends State<AppIconButtonFace> {
  bool _hasFocus = false;

  bool get _enabled => widget.onPressed != null;

  /// Where the focus is, as the face shows it — M3's focus layer is for
  /// KEYBOARD focus only, the same gate `InkResponse.updateFocusHighlights`
  /// applies.
  IconButtonFocus get _focus => !_hasFocus
      ? IconButtonFocus.away
      : _enabled &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional
      ? IconButtonFocus.shown
      : IconButtonFocus.held;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    if (_hasFocus) {
      setState(() {});
    }
  }

  void _setHasFocus(bool value) {
    if (_hasFocus != value) {
      setState(() => _hasFocus = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final focus = _focus;
    // 🚨DANGER OUTRANKS SELECTED — and a button that fell back to accent while
    // its own popover was open would drop the louder fact at exactly the
    // moment the popover is there to explain it ([IconButtonInk]).
    final ink = IconButtonInk.of(
      context,
      isSelected: widget.isSelected,
      danger: widget.danger,
    );
    // The glyph's ink, for every state this widget knows. The hover and the
    // press live in the face's render object and are not asked: no step of
    // [IconButtonInk.foreground] answers them — `styleFrom` builds its
    // foreground from `ButtonStyleButton.defaultColor` (disabled, else the
    // colour) — pinned by `app_icon_button_test`.
    final foreground = ink.foreground(<WidgetState>{
      if (!enabled) WidgetState.disabled,
      if (widget.isSelected) WidgetState.selected,
      if (focus == IconButtonFocus.shown) WidgetState.focused,
    });
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: Focus(
        canRequestFocus: enabled,
        // The face's ONE node says the focus ([RenderIconButtonPressFace]).
        includeSemantics: false,
        onFocusChange: _setHasFocus,
        child: IconButtonPressFace(
          tooltip: widget.tooltip,
          onSemanticTap: widget.onSemanticTap,
          isSelected: widget.isSelected,
          focus: focus,
          ink: ink,
          shape: widget.shape,
          minWidth: widget.minWidth,
          maxWidth: widget.maxWidth,
          height: widget.height,
          child: IconTheme.merge(
            data: IconThemeData(color: foreground, size: widget.iconSize),
            // Text glyphs take the button's colour too — the promise
            // [AppIconButton.icon] makes. ⚠️Material never kept it: an
            // IconButton has no text style, so its Material fell back to the
            // theme's `bodyMedium`. No glyph on screen changed (census,
            // 2026-09-10): the FX mark colours itself, and the canvas bar's
            // 1:1 is never disabled or selected — at rest `bodyMedium` and the
            // theme's foreground are the same b4b8bb.
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground),
              child: widget.icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the keyboard's focus is, as an icon button shows it: not on it;
/// on it but unseen — the pointer is driving, and M3 shows the focus layer
/// for KEYBOARD focus only; or on it and shown.
enum IconButtonFocus { away, held, shown }

/// What a pointer and a screen reader meet of an [AppIconButton], as ONE
/// render object around its glyph ([RenderIconButtonPressFace]).
///
/// 🚨WHY (board `frame-panels-build-in-one-frame`, 2026-10-24): reopening
/// the timeline tab mounted ~5,700 elements, and every icon button was ~35
/// of them — a semantics node, a tooltip of nine, a mouse region, a
/// listener and three boxes, each its own element. This is the rail's light
/// face (I-57 ①: 「어디가 더 가벼워지는거에따라 맞추고 통일할거 알아서
/// 통일하고」) with the icon button's glyph as its child: the press every
/// light face is ([PressFace]), and the box and the state layer
/// ([layOutIconButtonBox], [IconButtonLayer]) the rail's glyph wears too.
class IconButtonPressFace extends SingleChildRenderObjectWidget {
  const IconButtonPressFace({
    super.key,
    required this.tooltip,
    required this.onSemanticTap,
    required this.isSelected,
    required this.focus,
    required this.ink,
    required this.shape,
    required this.minWidth,
    required this.maxWidth,
    required this.height,
    required super.child,
  });

  /// Empty is no tooltip at all, as an [AppTooltip]'s empty message is.
  final String tooltip;

  /// What a screen reader's activation calls; null is a dead button.
  final VoidCallback? onSemanticTap;
  final bool isSelected;
  final IconButtonFocus focus;
  final IconButtonInk ink;
  final ShapeBorder shape;
  final double minWidth;
  final double maxWidth;
  final double height;

  @override
  RenderIconButtonPressFace createRenderObject(BuildContext context) =>
      RenderIconButtonPressFace(
        spec: _specIn(context),
        tooltipContext: context,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderIconButtonPressFace renderObject,
  ) {
    renderObject
      ..spec = _specIn(context)
      ..tooltipContext = context;
  }

  IconButtonPressSpec _specIn(BuildContext context) => IconButtonPressSpec(
    tooltip: tooltip,
    onSemanticTap: onSemanticTap,
    isSelected: isSelected,
    focus: focus,
    ink: ink,
    shape: shape,
    minWidth: minWidth,
    maxWidth: maxWidth,
    height: height,
    textDirection: Directionality.of(context),
    triggerMode:
        TooltipTheme.of(context).triggerMode ?? TooltipTriggerMode.longPress,
  );
}

/// Everything a [RenderIconButtonPressFace] paints and says, resolved from
/// the context by its widget. Equal while nothing it shows would change.
@immutable
final class IconButtonPressSpec implements FaceSpec<IconButtonPressSpec> {
  const IconButtonPressSpec({
    required this.tooltip,
    required this.onSemanticTap,
    required this.isSelected,
    required this.focus,
    required this.ink,
    required this.shape,
    required this.minWidth,
    required this.maxWidth,
    required this.height,
    required this.textDirection,
    required this.triggerMode,
  });

  final String tooltip;
  final VoidCallback? onSemanticTap;
  final bool isSelected;
  final IconButtonFocus focus;
  final IconButtonInk ink;
  final ShapeBorder shape;
  final double minWidth;
  final double maxWidth;
  final double height;
  final TextDirection textDirection;
  final TooltipTriggerMode triggerMode;

  bool get enabled => onSemanticTap != null;

  /// The box the face hugs its glyph in ([layOutIconButtonBox]).
  BoxConstraints get box => BoxConstraints(
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: height,
    maxHeight: height,
  );

  @override
  bool laysOutAs(IconButtonPressSpec other) =>
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.height == height;

  /// A host that hands down a fresh closure every build changes what a
  /// screen reader's activation calls, never a pixel.
  @override
  bool paintsAs(IconButtonPressSpec other) =>
      laysOutAs(other) &&
      other.enabled == enabled &&
      other.isSelected == isSelected &&
      (other.focus == IconButtonFocus.shown) ==
          (focus == IconButtonFocus.shown) &&
      other.ink == ink &&
      other.shape == shape &&
      other.textDirection == textDirection;

  @override
  bool operator ==(Object other) =>
      other is IconButtonPressSpec &&
      paintsAs(other) &&
      other.focus == focus &&
      other.tooltip == tooltip &&
      other.onSemanticTap == onSemanticTap &&
      other.triggerMode == triggerMode;

  @override
  int get hashCode => Object.hash(
    tooltip,
    onSemanticTap,
    isSelected,
    focus,
    ink,
    shape,
    minWidth,
    maxWidth,
    height,
    textDirection,
    triggerMode,
  );
}

/// The app's icon button's face: its box and its state layer around the
/// glyph, on the press every light face is ([PressFace]).
class RenderIconButtonPressFace extends RenderShiftedBox with PressFace {
  RenderIconButtonPressFace({
    required IconButtonPressSpec spec,
    required BuildContext tooltipContext,
  }) : _spec = spec,
       super(null) {
    this.tooltipContext = tooltipContext;
  }

  IconButtonPressSpec _spec;
  IconButtonPressSpec get spec => _spec;
  set spec(IconButtonPressSpec value) {
    final old = _spec;
    _spec = value;
    respec(old, value);
  }

  @override
  bool get pressEnabled => _spec.enabled;

  @override
  bool get pressSelected => _spec.isSelected;

  @override
  String? get pressSemanticLabel => null;

  @override
  VoidCallback? get pressSemanticTap => _spec.onSemanticTap;

  @override
  TextDirection get pressTextDirection => _spec.textDirection;

  @override
  TooltipTriggerMode get pressTriggerMode => _spec.triggerMode;

  @override
  String get tooltipMessage => _spec.tooltip;

  @override
  void pressLookChanged() => markNeedsPaint();

  /// The state layer painted right now — for tests.
  @visibleForTesting
  Color? get debugLayerInk => _spec.ink.overlay(_states);

  Set<WidgetState> get _states => <WidgetState>{
    ...pressStates,
    if (_spec.focus == IconButtonFocus.shown) WidgetState.focused,
  };

  // ── layout ──────────────────────────────────────────────────────────
  //
  // ⛔Every way a parent can ask the box's size answers what the widgets it
  // replaced answered — the layout, the dry layout, the intrinsics and the
  // baselines — since the icon button stands in rows, wraps and dialogs
  // that ask each of them.

  ({Size size, Offset glyphOffset}) _boxIn(
    BoxConstraints constraints,
    Size Function(BoxConstraints loose) layOutGlyph,
  ) => layOutIconButtonBox(
    constraints,
    _spec.box,
    (loose) => child == null ? loose.smallest : layOutGlyph(loose),
  );

  @override
  void performLayout() {
    final glyph = child;
    final box = _boxIn(constraints, (loose) {
      glyph!.layout(loose, parentUsesSize: true);
      return glyph.size;
    });
    size = box.size;
    if (glyph != null) {
      (glyph.parentData! as BoxParentData).offset = box.glyphOffset;
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _boxIn(constraints, (loose) => child!.getDryLayout(loose)).size;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final glyph = child;
    if (glyph == null) {
      return null;
    }
    late final BoxConstraints loose;
    final box = _boxIn(constraints, (given) {
      loose = given;
      return glyph.getDryLayout(given);
    });
    final glyphBaseline = glyph.getDryBaseline(loose, baseline);
    return glyphBaseline == null ? null : glyphBaseline + box.glyphOffset.dy;
  }

  /// The face's old `ConstrainedBox`'s rule: the glyph's own intrinsic
  /// width held to the box's numbers — and the box's height, which is
  /// fixed.
  double _widthAround(double glyph) => _spec.box.constrainWidth(glyph);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widthAround(super.computeMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widthAround(super.computeMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) => _spec.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _spec.height;

  late final IconButtonLayer _layer = IconButtonLayer(markNeedsPaint);

  @override
  void paint(PaintingContext context, Offset offset) {
    _layer.paint(
      context.canvas,
      offset & size,
      ShapeDecoration(shape: _spec.shape, color: _spec.ink.overlay(_states)),
      _spec.textDirection,
    );
    super.paint(context, offset);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // The focus is said HERE rather than by `Focus` — that would add a node
    // per button for a fact this one already states. ⚠️Always a yes or a
    // no, never "not focusable": the old `Semantics(focusable: enabled,
    // focused: hasFocus)` set both, and the second answer won.
    config.isFocused = _spec.focus != IconButtonFocus.away;
  }

  @override
  void dispose() {
    _layer.dispose();
    super.dispose();
  }
}
