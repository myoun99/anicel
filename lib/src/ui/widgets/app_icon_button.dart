import 'app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../input/control_press_claim.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../theme/app_theme.dart';
import 'press_face.dart';
import 'icon_button_box.dart';
import 'keyboard_press.dart';
import 'rail_glyph_button.dart';

export 'icon_button_box.dart';

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
///  * the press law — the claim still owns the firing, the face's own since
///    2026-10-25 ([PressClaim]);
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
///    finds it with `find.tooltipSaying`, not `find.byTooltip`;
///  * ONE semantics node: button / enabled / selected / focusable / focused
///    and its tap action, with the tooltip on it. The tap action FIRES —
///    [AppIconButtonFace.onPressed] (유저 2026-09-10);
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
    // ⛔The claim is not WRITTEN here — it is the face's own ([PressClaim],
    // the one code a [ControlPressClaim] is too). It used to be three inline
    // `Listener` lines that [ControlPressClaim] also had — and while the
    // law lived in two places the buttons that mounted neither (the
    // x-sheet's toggles, the toolbar's 1·2·3·4·N) went unnoticed. ↩️A
    // [ControlPressClaim] stood over the face until 2026-10-25 (card
    // frame-panels-build-in-one-frame): an element and a render object for
    // every icon button a tab reopens.
    // 🚨★★★WHEN it acts is not this widget's to say (유저 확정 2026-08-30):
    // a button on a rail's row acts on the DOWN, and every other
    // button acts when it is released still inside itself. [PressFireScope]
    // holds that split in ONE place, so this hands over the callback and
    // says nothing about the moment.
    return AppIconButtonFace(
      key: ValueKey<String>(keyValue),
      tooltip: shortcutTooltip(context, tooltip, shortcuts),
      // The ONE callback, for every way a button is pressed: the pointer's
      // (the face's claim), a key's — Enter/Space, as on any other button
      // (유저 2026-10-23, board `F-450-Q1`: 「통일 — 아이콘 버튼도 Enter ·
      // Space 로 눌린다」; ↩️silent to keys from 2026-09-10 until then) —
      // and a screen reader's, whose activation arrives as
      // SemanticsAction.tap, which the claim never hears
      // (「스크린리더만 있으면좋을까싶은데」).
      // ↩️It was two until 2026-10-25: a [silentPress] for the face, so
      // a face with a pointer path of its own could not fire a press the
      // claim above it had fired already. The face's pointer path IS the
      // claim now, so there is no second path left to silence.
      onPressed: onPressed,
      isSelected: isSelected,
      danger: danger,
      outlined: outlined,
      size: size,
      icon: icon,
    );
  }
}

/// The part of an [AppIconButton] the keyboard reaches: its FOCUS and the
/// Enter/Space it answers ([onPressed]) — and, under it, the press face
/// that is everything a pointer and a screen reader meet
/// ([IconButtonPressFace]): the box, the hover / pressed / focus layer, the
/// cursor, the tooltip, the one semantics node and the claim that fires a
/// pointer's press.
///
/// Public because it is what [AppIconButton.keyValue] names: a test that
/// finds a button by its key finds THIS, exactly where the Material
/// `IconButton` used to stand.
class AppIconButtonFace extends StatefulWidget {
  const AppIconButtonFace({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.isSelected,
    required this.danger,
    required this.outlined,
    required this.size,
    required this.icon,
  });

  final String tooltip;

  /// What a press does — a pointer's, a key's and a screen reader's alike
  /// ([AppIconButton.onPressed]): non-null means enabled.
  final VoidCallback? onPressed;
  final bool isSelected;
  final bool danger;
  final bool outlined;
  final AppIconButtonMetrics size;
  final Widget icon;

  // ⛔STATE TRAVELS AS A `WidgetState` SET, NOT A ROW OF BOOLEANS. Five
  // named flags is what the wide-signature ratchet
  // (`clean_code_stays_measured_test`) stopped — and Material speaks in
  // `WidgetState` too, which is what lets every colour below come straight
  // out of Material's own `ButtonStyle`s.

  @override
  State<AppIconButtonFace> createState() => _AppIconButtonFaceState();
}

class _AppIconButtonFaceState extends State<AppIconButtonFace>
    with KeyboardPress {
  bool get _enabled => widget.onPressed != null;

  @override
  VoidCallback? get keyboardPress => widget.onPressed;

  @override
  Widget build(BuildContext context) {
    final focus = keyboardFocus;
    return keyboardReaches(switch (_glyphOf(context)) {
      final glyph? => RailGlyphButton.face(
        tooltip: widget.tooltip,
        glyph: glyph,
        onPressed: widget.onPressed,
        size: widget.size,
        isSelected: widget.isSelected,
        danger: widget.danger,
        outlined: widget.outlined,
        focus: focus,
      ),
      null => _faceAround(context, focus),
    });
  }

  /// [AppIconButton.icon] as a glyph the face draws itself — an [Icon] that
  /// says nothing but its glyph and its colour, as nearly every icon
  /// button's does — or null for anything else, which stays a widget under
  /// [_faceAround].
  ///
  /// 🪶WHY (card frame-panels-build-in-one-frame, 2026-10-25): an [Icon] is
  /// six elements, and the theme and text style it was set in two more
  /// each — ten of an icon button's seventeen, built again for every button
  /// a tab reopens. The rail's glyph face draws the same glyph from the
  /// app's one cache, pixel for pixel (`the_icon_button_wears_the_press_
  /// face_test` holds it against the widgets it replaced), so an icon
  /// button wears that face.
  ///
  /// ⛔Only an [Icon] the glyph says ALL of. Each field left out changes
  /// what [Icon] draws or says — its own size, its axes, shadows, blend,
  /// weight, a label a screen reader hears, a key a test finds — and a key
  /// or a label has no place on a painted glyph. Nor a glyph that turns for
  /// a right-to-left text, or a theme that scales icons with the text: the
  /// face draws neither.
  RailGlyph? _glyphOf(BuildContext context) => switch (widget.icon) {
    Icon(
      key: null,
      icon: final data?,
      :final color,
      size: null,
      fill: null,
      weight: null,
      grade: null,
      opticalSize: null,
      shadows: null,
      semanticLabel: null,
      textDirection: null,
      applyTextScaling: null,
      blendMode: null,
      fontWeight: null,
    )
        when !(data.matchTextDirection &&
                Directionality.of(context) == TextDirection.rtl) &&
            IconTheme.of(context).applyTextScaling != true =>
      RailIconGlyph(data, color: color),
    _ => null,
  };

  /// The face around an icon that is a widget of its own.
  Widget _faceAround(BuildContext context, IconButtonFocus focus) {
    final box = appIconButtonBoxOnGrid(context, widget.size);
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
      if (!_enabled) WidgetState.disabled,
      if (widget.isSelected) WidgetState.selected,
      if (focus == IconButtonFocus.shown) WidgetState.focused,
    });
    return IconButtonPressFace(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      isSelected: widget.isSelected,
      focus: focus,
      ink: ink,
      shape: appIconButtonShape(
        widget.size.height,
        outlined: widget.outlined,
        danger: widget.danger,
        isSelected: widget.isSelected,
      ),
      minWidth: box.minWidth,
      maxWidth: box.maxWidth,
      minHeight: box.height,
      maxHeight: box.height,
      child: IconTheme.merge(
        data: IconThemeData(color: foreground, size: widget.size.iconSize),
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
    );
  }
}

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
    required this.onPressed,
    required this.isSelected,
    required this.focus,
    required this.ink,
    required this.shape,
    required this.minWidth,
    required this.maxWidth,
    required this.minHeight,
    required this.maxHeight,
    required super.child,
  });

  /// Empty is no tooltip at all, as an [AppTooltip]'s empty message is.
  final String tooltip;

  /// What a press does — the pointer's, through the claim this face is,
  /// and a screen reader's activation, which the claim never hears. Null is
  /// a dead button.
  final VoidCallback? onPressed;
  final bool isSelected;
  final IconButtonFocus focus;
  final IconButtonInk ink;
  final ShapeBorder shape;
  final double minWidth;
  final double maxWidth;

  /// The box's height, between these — one height for an icon button,
  /// a span for a text button's, whose density lets it shrink to its word.
  final double minHeight;
  final double maxHeight;

  @override
  RenderIconButtonPressFace createRenderObject(BuildContext context) =>
      RenderIconButtonPressFace(
        spec: _specIn(context),
        tooltipContext: context,
      )..wearPlace(context);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderIconButtonPressFace renderObject,
  ) {
    renderObject
      ..spec = _specIn(context)
      ..tooltipContext = context
      ..wearPlace(context);
  }

  IconButtonPressSpec _specIn(BuildContext context) => IconButtonPressSpec(
    tooltip: tooltip,
    onPressed: onPressed,
    isSelected: isSelected,
    focus: focus,
    ink: ink,
    shape: shape,
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight,
    textDirection: Directionality.of(context),
    triggerMode: AppTooltipLook.triggerModeIn(context),
  );
}

/// Everything a [RenderIconButtonPressFace] paints and says, resolved from
/// the context by its widget. Equal while nothing it shows would change.
@immutable
final class IconButtonPressSpec implements FaceSpec<IconButtonPressSpec> {
  const IconButtonPressSpec({
    required this.tooltip,
    required this.onPressed,
    required this.isSelected,
    required this.focus,
    required this.ink,
    required this.shape,
    required this.minWidth,
    required this.maxWidth,
    required this.minHeight,
    required this.maxHeight,
    required this.textDirection,
    required this.triggerMode,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final bool isSelected;
  final IconButtonFocus focus;
  final IconButtonInk ink;
  final ShapeBorder shape;
  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;
  final TextDirection textDirection;
  final TooltipTriggerMode triggerMode;

  bool get enabled => onPressed != null;

  /// The box the face hugs its glyph in ([layOutIconButtonBox]).
  BoxConstraints get box => BoxConstraints(
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight,
  );

  @override
  bool laysOutAs(IconButtonPressSpec other) =>
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.minHeight == minHeight &&
      other.maxHeight == maxHeight;

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
      other.onPressed == onPressed &&
      other.triggerMode == triggerMode;

  @override
  int get hashCode => Object.hash(
    tooltip,
    onPressed,
    isSelected,
    focus,
    ink,
    shape,
    minWidth,
    maxWidth,
    minHeight,
    maxHeight,
    textDirection,
    triggerMode,
  );
}

/// The app's icon button's face: its box and its state layer around the
/// glyph, on the press every light face is ([PressFace]).
class RenderIconButtonPressFace extends RenderShiftedBox
    with PressClaim, SummonsTooltip, PressFace {
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
  VoidCallback? get onPress => _spec.onPressed;

  @override
  bool get pressSelected => _spec.isSelected;

  @override
  String? get pressSemanticLabel => null;

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
  /// width held to the box's numbers — and its height held to the box's
  /// span, which for an icon button is one height.
  double _widthAround(double glyph) => _spec.box.constrainWidth(glyph);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widthAround(super.computeMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widthAround(super.computeMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _spec.box.constrainHeight(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _spec.box.constrainHeight(super.computeMaxIntrinsicHeight(width));

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
