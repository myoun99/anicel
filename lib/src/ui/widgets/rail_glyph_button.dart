import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/lru.dart';
import '../input/control_press_claim.dart';
import 'app_icon_button.dart';
import 'app_tooltip.dart';
import 'named.dart';

/// What a rail glyph draws: a glyph of an icon font ([RailIconGlyph]), or a
/// word set in type ([RailTextGlyph] — the fx switch's `fx`).
sealed class RailGlyph {
  const RailGlyph();
}

/// An [Icon]'s glyph — drawn as [Icon] draws it, in the button's ink unless
/// [color] says otherwise (the eye's off colour, a soloed speaker).
final class RailIconGlyph extends RailGlyph {
  const RailIconGlyph(this.icon, {this.color});

  final IconData icon;
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is RailIconGlyph && other.icon == icon && other.color == color;

  @override
  int get hashCode => Object.hash(icon, color);
}

/// A word set in [style] over the ambient text style, as a [Text] with no
/// text scaling sets it — an icon does not follow the OS text size.
final class RailTextGlyph extends RailGlyph {
  const RailTextGlyph(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  bool operator ==(Object other) =>
      other is RailTextGlyph && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);
}

/// THE RAIL'S BUTTON — what a rail's toggles and doors are made of (the eye,
/// the speaker, the fx switch, the sheet toggle, the twirls), drawn by ONE
/// render object each.
///
/// 🚨WHY (I-57 ①, 유저 10-09 「가볍기만하면 레일전용버튼해도 상관없어 …
/// 통일할거 알아서 통일하고」): a cut switch mounts every visible rail row
/// anew — their keys are the layers', and the layers are another cut's — and
/// one row was ~400 elements, most of them its buttons: each an
/// [AppIconButton] of ~35 (the claim, a stateful face, a semantics node, a
/// tooltip of nine, focus, actions, a mouse region, a listener, three boxes,
/// two builders and an [Icon] of six). Measured in a profile build on the
/// user's project: the frame after a cut switch spent ~45% of its time on
/// the rail. This is the claim and ONE leaf: the leaf paints the box, the
/// state layer and the glyph (laid out once for the whole app), says the
/// semantics, shows the cursor, and summons the one tooltip window the
/// rail's buttons share ([SummonedTooltip]).
///
/// ⛔THE PRESS IS UNTOUCHED: [ControlPressClaim] fires it, as it fires an
/// [AppIconButton]'s, and [PressFireScope] says when — the leaf only enters
/// the do-nothing tap an [AppIconButtonFace] enters, so an ancestor's tap
/// still loses to a press on a button.
///
/// ⛔ONE INK, ONE SHAPE: [IconButtonInk] and [appIconButtonShape] are the
/// [AppIconButton]'s own, so the rail looks exactly as it did.
///
/// ⚠️What a rail button no longer has is KEYBOARD FOCUS — the Tab key's
/// stop and the focus ring. Its Enter/Space were already silent by 유저's
/// call (2026-09-10: 「탭은 다른 숏컷 쓸수도있어서 굳이 필요없을거같고」), so
/// focus led nowhere. A screen reader still finds and presses it.
/// ⚠️That premise fell on 2026-10-23 (board `F-450-Q1`: every other icon
/// button now answers Enter/Space); whether the rail takes its focus back,
/// at the cost the leaf was built to shed, is board `F-450-Q2`.
class RailGlyphButton extends StatelessWidget {
  const RailGlyphButton({
    super.key,
    required this.name,
    required this.tooltip,
    required this.glyph,
    required this.onPressed,
    required this.size,
    this.isSelected = false,
    this.danger = false,
    this.semanticLabel,
  });

  /// What a finder calls the [RailGlyphFace], the box the user sees and
  /// presses — the tests' handle, a [Named] and never a key: a rail row
  /// shows one layer and then another in the same elements (I-57, 10-13),
  /// and a key spelled from the layer remade every button of every row on
  /// every cut switch.
  final String name;

  /// Empty is no tooltip at all, as an [AppTooltip]'s empty message is.
  final String tooltip;
  final RailGlyph glyph;
  final VoidCallback? onPressed;

  /// What a screen reader calls a button whose glyph says what it is and
  /// that shows no tooltip — the type button's kind.
  final String? semanticLabel;

  /// The box: the rail's slot as an [AppIconButtonBox] the parent promised,
  /// or a token where the button stands outside a rail.
  final AppIconButtonMetrics size;

  /// The ON state — accent ink only ([AppIconButton.isSelected]).
  final bool isSelected;

  /// Something is wrong with what this button is about ([AppIconButton.
  /// danger]).
  final bool danger;

  @override
  Widget build(BuildContext context) => ControlPressClaim(
    onPressed: onPressed,
    child: Named(
      name,
      child: RailGlyphFace(
        tooltip: tooltip,
        glyph: glyph,
        // 🚨A screen reader is not a pointer: its activation arrives as
        // SemanticsAction.tap, which the claim never hears, so the node
        // gets the REAL callback — as an [AppIconButton]'s does.
        onSemanticTap: onPressed,
        semanticLabel: semanticLabel,
        isSelected: isSelected,
        danger: danger,
        size: size,
      ),
    ),
  );
}

/// The part of a [RailGlyphButton] you can see and hear, as one render
/// object. Public because it is what [RailGlyphButton.name] names.
class RailGlyphFace extends LeafRenderObjectWidget {
  const RailGlyphFace({
    super.key,
    required this.tooltip,
    required this.glyph,
    required this.onSemanticTap,
    required this.isSelected,
    required this.danger,
    required this.size,
    this.semanticLabel,
  });

  final String tooltip;
  final RailGlyph glyph;

  /// What a screen reader's activation calls; null is a dead button.
  final VoidCallback? onSemanticTap;
  final String? semanticLabel;
  final bool isSelected;
  final bool danger;
  final AppIconButtonMetrics size;

  bool get enabled => onSemanticTap != null;

  @override
  RenderRailGlyphFace createRenderObject(BuildContext context) =>
      RenderRailGlyphFace(spec: _specIn(context), tooltipContext: context);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRailGlyphFace renderObject,
  ) {
    renderObject
      ..spec = _specIn(context)
      ..tooltipContext = context;
  }

  RailGlyphSpec _specIn(BuildContext context) {
    final ambient = IconTheme.of(context);
    final box = appIconButtonBoxOnGrid(context, size);
    return RailGlyphSpec(
      tooltip: tooltip,
      glyph: glyph,
      onSemanticTap: onSemanticTap,
      semanticLabel: semanticLabel,
      isSelected: isSelected,
      ink: IconButtonInk.of(context, isSelected: isSelected, danger: danger),
      shape: appIconButtonShape(
        size.height,
        outlined: false,
        danger: danger,
        isSelected: isSelected,
      ),
      minWidth: box.minWidth,
      maxWidth: box.maxWidth,
      height: box.height,
      // The face's own `IconTheme.merge(color: ink, size: iconSize)` over
      // the ambient one — its fill, weight, grade, optical size, opacity and
      // shadows stay the ambient's.
      iconTheme: ambient.copyWith(size: size.iconSize),
      textStyle: DefaultTextStyle.of(context).style,
      textDirection: Directionality.of(context),
      triggerMode:
          TooltipTheme.of(context).triggerMode ?? TooltipTriggerMode.longPress,
    );
  }
}

/// Everything a [RenderRailGlyphFace] draws and says, resolved from the
/// context by its widget. Equal while nothing it shows would change.
@immutable
final class RailGlyphSpec {
  const RailGlyphSpec({
    required this.tooltip,
    required this.glyph,
    required this.onSemanticTap,
    required this.semanticLabel,
    required this.isSelected,
    required this.ink,
    required this.shape,
    required this.minWidth,
    required this.maxWidth,
    required this.height,
    required this.iconTheme,
    required this.textStyle,
    required this.textDirection,
    required this.triggerMode,
  });

  final String tooltip;
  final RailGlyph glyph;
  final VoidCallback? onSemanticTap;
  final String? semanticLabel;
  final bool isSelected;
  final IconButtonInk ink;
  final ShapeBorder shape;
  final double minWidth;
  final double maxWidth;
  final double height;
  final IconThemeData iconTheme;
  final TextStyle textStyle;
  final TextDirection textDirection;
  final TooltipTriggerMode triggerMode;

  bool get enabled => onSemanticTap != null;

  /// Whether [other] lays out the same box — else only a repaint is owed.
  bool laysOutAs(RailGlyphSpec other) =>
      other.glyph == glyph &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.height == height &&
      other.iconTheme == iconTheme &&
      other.textStyle == textStyle &&
      other.textDirection == textDirection;

  /// Whether [other] paints the same pixels in the same box — else a
  /// repaint is owed. A host that hands down a fresh closure every build
  /// changes what a screen reader's activation calls, never a pixel.
  bool paintsAs(RailGlyphSpec other) =>
      laysOutAs(other) &&
      other.enabled == enabled &&
      other.isSelected == isSelected &&
      other.ink == ink &&
      other.shape == shape;

  @override
  bool operator ==(Object other) =>
      other is RailGlyphSpec &&
      paintsAs(other) &&
      other.tooltip == tooltip &&
      other.onSemanticTap == onSemanticTap &&
      other.semanticLabel == semanticLabel &&
      other.triggerMode == triggerMode;

  @override
  int get hashCode => Object.hash(
    tooltip,
    glyph,
    onSemanticTap,
    semanticLabel,
    isSelected,
    ink,
    shape,
    minWidth,
    maxWidth,
    height,
    iconTheme,
    textStyle,
    textDirection,
    triggerMode,
  );
}

/// What every rail press face is besides what it shows: the hover and the
/// press, the cursor, the do-nothing tap it enters into the arena, the
/// tooltip it summons and the one semantics node a button is — so the
/// glyph face ([RenderRailGlyphFace]) and the plate face
/// ([RenderRailPlateFace]) are one press under two pictures.
mixin RailPressFace on RenderBox
    implements MouseTrackerAnnotation, SummonedTooltipTarget {
  /// Whether a press does anything: a dead face shows no press, enters no
  /// tap and wears the basic cursor.
  @protected
  bool get pressEnabled;

  /// The ON state, as a screen reader hears it.
  @protected
  bool get pressSelected;

  /// What a screen reader calls a face whose picture says what it is.
  @protected
  String? get pressSemanticLabel;

  /// What a screen reader's activation calls — the REAL callback, since a
  /// screen reader's tap never reaches the claim ([RailGlyphButton]).
  @protected
  VoidCallback? get pressSemanticTap;

  @protected
  TextDirection get pressTextDirection;

  @protected
  TooltipTriggerMode get pressTriggerMode;

  BuildContext? _tooltipContext;
  set tooltipContext(BuildContext value) => _tooltipContext = value;

  bool _hovered = false;
  bool _pressed = false;

  @protected
  bool get hovered => _hovered;

  @protected
  bool get pressed => _pressed;

  /// What the hover and the press look like right now — for tests.
  @visibleForTesting
  ({bool hovered, bool pressed}) get debugState =>
      (hovered: _hovered, pressed: _pressed);

  /// The hover or the press changed — a face that shows them repaints.
  @protected
  void pressLookChanged() {}

  /// A face that went dead mid-press must not keep looking pressed. (Hover
  /// is kept, as M3 keeps it.)
  @protected
  void letGoOfThePress() => _setPressed(false);

  /// The do-nothing tap entered into the arena on every enabled press —
  /// "THE ARENA" on [AppIconButton]. ⚠️Its `onTap` is REQUIRED: a recogniser
  /// with every callback null is never offered the pointer.
  late final TapGestureRecognizer _arenaTap = TapGestureRecognizer(
    debugOwner: this,
  )..onTap = _ownsTheTap;
  static void _ownsTheTap() {}

  /// The tooltip's own trigger on a touch or a pen: Flutter's, the devices
  /// that cannot hover.
  late final LongPressGestureRecognizer _longPress = LongPressGestureRecognizer(
    debugOwner: this,
    supportedDevices: const {
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
      PointerDeviceKind.unknown,
      PointerDeviceKind.trackpad,
    },
  )
    ..onLongPress = _onLongPress
    ..onLongPressUp = _onLongPressUp
    ..onLongPressCancel = _onLongPressCancel;
  int? _longPressPointer;

  // ── hover and press ────────────────────────────────────────────────

  @override
  MouseCursor get cursor =>
      pressEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic;

  @override
  PointerEnterEventListener? get onEnter => _onEnter;

  @override
  PointerExitEventListener? get onExit => _onExit;

  @override
  bool get validForMouseTracker => attached;

  void _onEnter(PointerEnterEvent event) {
    _setHovered(true);
    SummonedTooltip.hover(this);
  }

  void _onExit(PointerExitEvent event) {
    _setHovered(false);
    SummonedTooltip.unhover(this);
  }

  void _setHovered(bool value) {
    if (_hovered != value) {
      _hovered = value;
      pressLookChanged();
    }
  }

  void _setPressed(bool value) {
    if (_pressed != value) {
      _pressed = value;
      pressLookChanged();
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      if (pressEnabled) {
        _setPressed(true);
        _arenaTap.addPointer(event);
      }
      if (pressTriggerMode == TooltipTriggerMode.longPress) {
        _longPress.addPointer(event);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _setPressed(false);
    }
  }

  void _onLongPress() {
    final pointer = _longPress.primaryPointer;
    if (pointer == null) {
      return;
    }
    _longPressPointer = pointer;
    SummonedTooltip.longPressed(this, pointer);
  }

  void _onLongPressUp() {
    _longPressPointer = null;
    SummonedTooltip.lifted(this);
  }

  /// A press that moved off or was taken before it was long: whatever this
  /// face had summoned goes, as a tooltip's own cancel dismisses it.
  void _onLongPressCancel() {
    _longPressPointer = null;
    SummonedTooltip.forget(this);
  }

  // ── the summoned tooltip ───────────────────────────────────────────

  @override
  Rect? get tooltipGlobalRect => attached && hasSize
      ? MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size)
      : null;

  @override
  BuildContext? get tooltipContext => attached ? _tooltipContext : null;

  // ── semantics ──────────────────────────────────────────────────────

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // ONE node per button: a boundary, so a row of six does not collapse
    // into one, with the tooltip hung on it — as an [AppIconButton]'s.
    config
      ..isSemanticBoundary = true
      ..isButton = true
      ..isEnabled = pressEnabled
      ..isSelected = pressSelected
      ..tooltip = tooltipMessage
      // A node that carries text says which way it reads.
      ..textDirection = pressTextDirection;
    if (pressSemanticLabel case final label?) {
      config.label = label;
    }
    if (pressSemanticTap case final onTap?) {
      config.onTap = onTap;
    }
  }

  // ── lifecycle ──────────────────────────────────────────────────────

  @override
  void detach() {
    _hovered = false;
    _pressed = false;
    if (_longPressPointer != null) {
      _longPressPointer = null;
    }
    SummonedTooltip.forget(this);
    super.detach();
  }

  @override
  void dispose() {
    _arenaTap.dispose();
    _longPress.dispose();
    super.dispose();
  }
}

/// The rail button's face: its box, its state layer and its glyph, as one
/// render object, on the press every rail face is ([RailPressFace]).
class RenderRailGlyphFace extends RenderBox with RailPressFace {
  RenderRailGlyphFace({
    required RailGlyphSpec spec,
    required BuildContext tooltipContext,
  }) : _spec = spec {
    this.tooltipContext = tooltipContext;
  }

  RailGlyphSpec _spec;
  RailGlyphSpec get spec => _spec;
  set spec(RailGlyphSpec value) {
    if (value == _spec) {
      return;
    }
    final relayout = !value.laysOutAs(_spec);
    final repaint = !value.paintsAs(_spec);
    _spec = value;
    if (!value.enabled) {
      letGoOfThePress();
    }
    if (relayout) {
      markNeedsLayout();
    } else if (repaint) {
      markNeedsPaint();
    }
    markNeedsSemanticsUpdate();
  }

  @override
  bool get pressEnabled => _spec.enabled;

  @override
  bool get pressSelected => _spec.isSelected;

  @override
  String? get pressSemanticLabel => _spec.semanticLabel;

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

  /// The colour the glyph is painted in right now — for tests.
  @visibleForTesting
  Color? get debugGlyphInk =>
      _glyphPainter(_spec.ink.foreground(_states)).text?.style?.color;

  Set<WidgetState> get _states => <WidgetState>{
    if (!_spec.enabled) WidgetState.disabled,
    if (_spec.isSelected) WidgetState.selected,
    if (pressed) WidgetState.pressed,
    if (hovered) WidgetState.hovered,
  };

  // ── layout ──────────────────────────────────────────────────────────

  /// Where the glyph is painted inside the face — [Icon]'s square of its
  /// size centred and the glyph centred in it, or the word's paragraph
  /// centred — summed as the widgets summed their offsets.
  Offset _glyphOffset = Offset.zero;

  @override
  void performLayout() {
    // The face's `ConstrainedBox`: the slot's numbers, enforced inside what
    // the parent allows.
    final face = BoxConstraints(
      minWidth: _spec.minWidth,
      maxWidth: _spec.maxWidth,
      minHeight: _spec.height,
      maxHeight: _spec.height,
    ).enforce(constraints);
    // …then `Align(widthFactor: 1, heightFactor: 1)`: as big as its child,
    // within that — the child laid out loose.
    final loose = face.loosen();
    final painter = _glyphPainter(_spec.ink.foreground(_states));
    final Size child;
    final Offset inChild;
    switch (_spec.glyph) {
      case RailIconGlyph():
        final square = _spec.iconTheme.size!;
        child = loose.constrain(Size(square, square));
        // [Icon]'s `Center` inside its square.
        inChild = Alignment.center.alongOffset(
          child - painter.size as Offset,
        );
      case RailTextGlyph():
        child = loose.constrain(painter.size);
        inChild = Offset.zero;
    }
    size = face.constrain(child);
    _glyphOffset =
        Alignment.center.alongOffset(size - child as Offset) + inChild;
  }

  @override
  bool get sizedByParent => false;

  // ── paint ──────────────────────────────────────────────────────────

  BoxPainter? _boxPainter;
  Color? _boxPainterColor;

  @override
  void paint(PaintingContext context, Offset offset) {
    final states = _states;
    final overlay = _spec.ink.overlay(states);
    if (_boxPainter == null || overlay != _boxPainterColor) {
      _boxPainter?.dispose();
      _boxPainter = ShapeDecoration(
        shape: _spec.shape,
        color: overlay,
      ).createBoxPainter(markNeedsPaint);
      _boxPainterColor = overlay;
    }
    _boxPainter!.paint(
      context.canvas,
      offset,
      ImageConfiguration(size: size, textDirection: _spec.textDirection),
    );
    _glyphPainter(_spec.ink.foreground(states)).paint(
      context.canvas,
      offset + _glyphOffset,
    );
  }

  /// The glyph laid out in [ink] — or in its own colour where it has one —
  /// from the app's one cache: a glyph is laid out once however many rows
  /// show it.
  TextPainter _glyphPainter(Color ink) => switch (_spec.glyph) {
    RailIconGlyph(:final icon, :final color) => _GlyphCache.icon(
      icon,
      color: color ?? ink,
      theme: _spec.iconTheme,
      textDirection: _spec.textDirection,
    ),
    RailTextGlyph(:final text, :final style) => _GlyphCache.text(
      text,
      // `DefaultTextStyle.merge(color: ink)` under the word's own style.
      style: _spec.textStyle.merge(TextStyle(color: ink)).merge(style),
      textDirection: _spec.textDirection,
      maxWidth: _spec.maxWidth,
    ),
  };


  @override
  void dispose() {
    _boxPainter?.dispose();
    super.dispose();
  }
}

/// A rail PLATE that is pressed — the mark's and the take's ([RailPlateFace]).
/// What it shows is its child's own: the plate paints itself, opaque, so no
/// state layer would show over it — and the [InkWell] the plate used to wear
/// drew its ink UNDER it, unseen. Everything else is the press every rail
/// face is ([RailPressFace]).
class RenderRailPlateFace extends RenderProxyBox with RailPressFace {
  RenderRailPlateFace({
    required RailPlateSpec spec,
    required BuildContext tooltipContext,
  }) : _spec = spec {
    this.tooltipContext = tooltipContext;
  }

  RailPlateSpec _spec;
  RailPlateSpec get spec => _spec;
  set spec(RailPlateSpec value) {
    if (value == _spec) {
      return;
    }
    _spec = value;
    if (!value.enabled) {
      letGoOfThePress();
    }
    markNeedsSemanticsUpdate();
  }

  @override
  bool get pressEnabled => _spec.enabled;

  @override
  bool get pressSelected => false;

  @override
  String? get pressSemanticLabel => _spec.semanticLabel;

  @override
  VoidCallback? get pressSemanticTap => _spec.onSemanticTap;

  @override
  TextDirection get pressTextDirection => _spec.textDirection;

  @override
  TooltipTriggerMode get pressTriggerMode => _spec.triggerMode;

  @override
  String get tooltipMessage => _spec.tooltip;
}

/// Everything a [RenderRailPlateFace] says, resolved from the context by
/// its widget.
@immutable
final class RailPlateSpec {
  const RailPlateSpec({
    required this.tooltip,
    required this.onSemanticTap,
    required this.semanticLabel,
    required this.textDirection,
    required this.triggerMode,
  });

  final String tooltip;
  final VoidCallback? onSemanticTap;
  final String? semanticLabel;
  final TextDirection textDirection;
  final TooltipTriggerMode triggerMode;

  bool get enabled => onSemanticTap != null;

  @override
  bool operator ==(Object other) =>
      other is RailPlateSpec &&
      other.tooltip == tooltip &&
      other.onSemanticTap == onSemanticTap &&
      other.semanticLabel == semanticLabel &&
      other.textDirection == textDirection &&
      other.triggerMode == triggerMode;

  @override
  int get hashCode => Object.hash(
    tooltip,
    onSemanticTap,
    semanticLabel,
    textDirection,
    triggerMode,
  );
}

/// The face of a pressed rail plate: [child] is the plate, and this one
/// render object around it is the button — cursor, tooltip, semantics and
/// the arena's tap. The press itself is its [ControlPressClaim]'s, as a
/// [RailGlyphButton]'s is ([RailFlyoutTrigger]).
class RailPlateFace extends SingleChildRenderObjectWidget {
  const RailPlateFace({
    super.key,
    required this.tooltip,
    required this.onSemanticTap,
    this.semanticLabel,
    required super.child,
  });

  final String tooltip;

  /// What a screen reader's activation calls; null is a dead plate.
  final VoidCallback? onSemanticTap;
  final String? semanticLabel;

  @override
  RenderRailPlateFace createRenderObject(BuildContext context) =>
      RenderRailPlateFace(spec: _specIn(context), tooltipContext: context);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRailPlateFace renderObject,
  ) {
    renderObject
      ..spec = _specIn(context)
      ..tooltipContext = context;
  }

  RailPlateSpec _specIn(BuildContext context) => RailPlateSpec(
    tooltip: tooltip,
    onSemanticTap: onSemanticTap,
    semanticLabel: semanticLabel,
    textDirection: Directionality.of(context),
    triggerMode:
        TooltipTheme.of(context).triggerMode ?? TooltipTriggerMode.longPress,
  );
}

/// THE RAIL'S PLATE BUTTON — [child] painted as it paints itself, and the
/// claim and ONE face ([RailPlateFace]) around it: what a pressed plate of
/// a rail is, whatever the press does. A list's door is this with the list
/// as its press ([RailFlyoutTrigger]); the legend's headings are this, on
/// the legend's plate (`TimelineLayerControlsHeader`). Null [onPressed] is a
/// dead plate that still shows its tooltip, as a dead [RailGlyphButton]
/// does.
class RailPlateButton extends StatelessWidget {
  const RailPlateButton({
    super.key,
    required this.name,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.semanticLabel,
  });

  /// What a finder calls the [RailPlateFace] — a [Named], as a
  /// [RailGlyphButton.name] is and for its reason.
  final String name;
  final String tooltip;
  final VoidCallback? onPressed;

  /// The plate.
  final Widget child;

  /// What a screen reader calls it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => ControlPressClaim(
    onPressed: onPressed,
    child: Named(
      name,
      child: RailPlateFace(
        tooltip: tooltip,
        // The REAL callback, for a screen reader's activation — the claim
        // never hears it ([RailGlyphButton]).
        onSemanticTap: onPressed,
        semanticLabel: semanticLabel,
        child: child,
      ),
    ),
  );
}

/// The glyphs the rail buttons draw, each laid out ONCE for the app — six
/// rows wear one eye, and a cut switch lays out none of them again.
abstract final class _GlyphCache {
  /// Enough for every glyph × ink × size the rails show, with room; the
  /// least recently drawn goes first past it.
  static const int _capacity = 256;
  static final Lru<Object, TextPainter> _painters = Lru(
    limit: () => _capacity,
    letGo: (_, painter) => painter.dispose(),
  );

  static TextPainter icon(
    IconData icon, {
    required Color color,
    required IconThemeData theme,
    required TextDirection textDirection,
  }) {
    final size = theme.size!;
    // [Icon]'s opacity: the theme's, on top of the colour's own.
    final opacity = theme.opacity ?? 1.0;
    final ink = opacity == 1.0
        ? color
        : color.withValues(alpha: color.a * opacity);
    final key = (
      icon,
      ink,
      size,
      theme.fill,
      theme.weight,
      theme.grade,
      theme.opticalSize,
      theme.shadows,
      textDirection,
    );
    return _painters.resolve(
      key,
      () => TextPainter(
        textDirection: textDirection,
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          // [Icon]'s own style, field for field.
          style: TextStyle(
            fontVariations: <FontVariation>[
              if (theme.fill != null) FontVariation('FILL', theme.fill!),
              if (theme.weight != null) FontVariation('wght', theme.weight!),
              if (theme.grade != null) FontVariation('GRAD', theme.grade!),
              if (theme.opticalSize != null)
                FontVariation('opsz', theme.opticalSize!),
            ],
            inherit: false,
            color: ink,
            fontSize: size,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontFamilyFallback: icon.fontFamilyFallback,
            shadows: theme.shadows,
            height: 1.0,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      )..layout(),
    );
  }

  static TextPainter text(
    String text, {
    required TextStyle style,
    required TextDirection textDirection,
    required double maxWidth,
  }) => _painters.resolve(
    (text, style, textDirection, maxWidth),
    () => TextPainter(
      textDirection: textDirection,
      text: TextSpan(text: text, style: style),
    )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity),
  );
}

/// The rail glyphs' painter for [text] in [style] — the cache a pin asks to
/// see keep and let go ([_GlyphCache]).
@visibleForTesting
TextPainter debugRailTextGlyph(String text, TextStyle style) =>
    _GlyphCache.text(
      text,
      style: style,
      textDirection: TextDirection.ltr,
      maxWidth: double.infinity,
    );
