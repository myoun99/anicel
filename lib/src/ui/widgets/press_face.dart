import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppCursors, SuperellipseFace;
import 'app_tooltip.dart';
import 'icon_button_box.dart' show IconButtonLayer;
import 'live_sheet.dart';

/// What a light face's spec says of the one it replaces ([PressFace.respec]).
abstract interface class FaceSpec<S> {
  /// Whether [other] lays out the same box — else only a repaint is owed.
  bool laysOutAs(S other);

  /// Whether [other] paints the same pixels in the same box.
  bool paintsAs(S other);
}

/// What every light button's face is besides what it shows: the hover and
/// the press, the cursor, the do-nothing tap it enters into the arena, the
/// tooltip it summons and the one semantics node a button is — so the
/// rail's glyph (`RenderRailGlyphFace`), the rail's plate
/// (`RenderRailPlateFace`) and the app's icon button
/// (`RenderIconButtonPressFace`) are one press under three pictures.
///
/// 🚨WHY ONE RENDER OBJECT (I-57 ①, 유저 10-09 「가볍기만하면
/// 레일전용버튼해도 상관없어 … 어디가 더 가벼워지는거에따라 맞추고 통일할거
/// 알아서 통일하고」): the widgets a button used to be made of — a semantics
/// node, a tooltip of nine elements, a mouse region, a listener — were most
/// of every panel a tab switch builds anew.
///
/// ⛔THE PRESS IS FIRED BY THE CLAIM, NOT HERE: the face IS its claim
/// ([PressClaim] — the one code a [ControlPressClaim] is too), and
/// [PressFireScope] says when. The face only enters the do-nothing tap, so
/// an ancestor's tap still loses to a press on a button. ↩️A
/// [ControlPressClaim] stood over every face until 2026-10-25 — a second
/// element and a second render object for every button a tab reopens
/// (card frame-panels-build-in-one-frame).
mixin PressFace on RenderBox, PressClaim, SummonsTooltip
    implements MouseTrackerAnnotation {
  /// Whether a press does anything: a dead face shows no press, enters no
  /// tap and wears the basic cursor.
  @protected
  bool get pressEnabled => onPress != null;

  /// The ON state, as a screen reader hears it.
  @protected
  bool get pressSelected;

  /// What a screen reader calls a face whose picture says what it is.
  @protected
  String? get pressSemanticLabel;

  @protected
  TextDirection get pressTextDirection;

  @protected
  TooltipTriggerMode get pressTriggerMode;

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

  /// This face's state in Material's own vocabulary — what an ink resolves
  /// against.
  @protected
  Set<WidgetState> get pressStates => <WidgetState>{
    if (!pressEnabled) WidgetState.disabled,
    if (pressSelected) WidgetState.selected,
    if (_pressed) WidgetState.pressed,
    if (_hovered) WidgetState.hovered,
  };

  /// The hover or the press changed — a face whose own picture shows them
  /// besides its state layer, in its glyph's ink say, repaints. The state
  /// layer is laid again without it ([_lookChanged]).
  @protected
  void pressLookChanged() {}

  // ── the state layer ────────────────────────────────────────────────

  /// What the face lays under what it shows for the state it is in — the
  /// hover, the press, the keyboard's focus (`iconButtonLayerOf`) — or null
  /// for a face that lays none.
  @protected
  ShapeDecoration? get stateLayer;

  late final IconButtonLayer _stateLayerPaint = IconButtonLayer(
    markNeedsPaint,
  );

  /// The state layer as the sheet under the face draws it, where one is
  /// ([LiveSheet]).
  late final LaidLook<ShapeDecoration> _laidStateLayer =
      LaidLook<ShapeDecoration>(
        this,
        _stateLayerOnTheSheet,
        (canvas, layer) => _stateLayerPaint.paint(
          canvas,
          Offset.zero & size,
          layer,
          pressTextDirection,
        ),
      );

  /// 🚨A STATE LAYER IS LAID ON THE SHEET UNDER THE FACE, WHERE ONE IS
  /// ([LiveSheet] has why): drawn live there, it changes nothing a still
  /// region holds, and a pointer passing over the face takes no image.
  ///
  /// ⛔Not a layer that is the face's own inside ([SuperellipseFace] — an
  /// outlined face's, filled at rest too, its edge drawn by that fill,
  /// `iconButtonLayerOf`): it is opaque, and what the face stands in is
  /// painted over the sheet.
  bool _sheetDraws(ShapeDecoration? layer) =>
      _laidStateLayer.onSheet && layer != null && layer is! SuperellipseFace;

  /// The state layer at [rect] in the face's own picture — nothing where
  /// the sheet under the face draws it.
  @protected
  void paintStateLayer(Canvas canvas, Rect rect) {
    final layer = stateLayer;
    if (layer == null) {
      return;
    }
    if (_sheetDraws(layer)) {
      return;
    }
    _stateLayerPaint.paint(canvas, rect, layer, pressTextDirection);
  }

  /// What the sheet under the face draws of the state layer now — nothing
  /// while it shows nothing.
  ///
  /// 🚨A layer with no ink is no look: a face at rest lays nothing, and a
  /// sheet with nothing laid asks nothing of any frame ([LiveSheet]) — the
  /// frames of a stroke among them.
  ShapeDecoration? _stateLayerOnTheSheet() {
    final layer = stateLayer;
    return _sheetDraws(layer) && layer?.color != null ? layer : null;
  }

  /// The hover or the press changed: the state layer is laid again — on
  /// the sheet, or by the face painting itself.
  void _lookChanged() {
    _laidStateLayer.changed();
    final layer = stateLayer;
    if (layer != null && !_sheetDraws(layer)) {
      markNeedsPaint();
    }
    pressLookChanged();
  }

  @override
  void wearPlace(BuildContext context) {
    super.wearPlace(context);
    _laidStateLayer.wear(LiveSheet.underOf(context));
  }

  /// The face now wears [value] in place of [old]: unchanged, nothing is
  /// owed; else a box that moved lays out again, a picture that changed
  /// paints again, and the node says the new facts. A face that went dead
  /// mid-press must not keep looking pressed. (Hover is kept, as M3 keeps
  /// it: re-enabled under a resting mouse, the button is hovered again
  /// without the mouse having to move.) Called once [value] is worn.
  @protected
  void respec<S extends FaceSpec<S>>(S old, S value) {
    if (value == old) {
      return;
    }
    if (!pressEnabled) {
      _setPressed(false);
    }
    if (!value.laysOutAs(old)) {
      markNeedsLayout();
    } else if (!value.paintsAs(old)) {
      markNeedsPaint();
    }
    markNeedsSemanticsUpdate();
    // What it lays is its spec's too — its ink, its shape, its focus.
    _laidStateLayer.changed();
  }

  /// The do-nothing tap entered into the arena on every enabled press —
  /// "THE ARENA" on `AppIconButton`. ⚠️Its `onTap` is REQUIRED: a recogniser
  /// with every callback null is never offered the pointer.
  late final TapGestureRecognizer _arenaTap = TapGestureRecognizer(
    debugOwner: this,
  )..onTap = _ownsTheTap;
  static void _ownsTheTap() {}

  // ── hover and press ────────────────────────────────────────────────

  @override
  MouseCursor get cursor => AppCursors.pressWhen(live: pressEnabled);

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
      _lookChanged();
    }
  }

  void _setPressed(bool value) {
    if (_pressed != value) {
      _pressed = value;
      _lookChanged();
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final hit = super.hitTest(result, position: position);
    // An empty tooltip shows nothing, as an [AppTooltip] holding an empty
    // message is no tooltip — and stands aside for none.
    if (hit && tooltipMessage.isNotEmpty) {
      SummonedTooltip.standInnermost();
    }
    return hit;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      if (pressEnabled) {
        _setPressed(true);
        _arenaTap.addPointer(event);
      }
      summonOnLongPress(event, pressTriggerMode);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _setPressed(false);
    }
    // The claim hears the pointer AFTER the face, as it did while it was
    // the box around it.
    super.handleEvent(event, entry);
  }

  // ── semantics ──────────────────────────────────────────────────────

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // ONE node per button: a boundary, so a row of six does not collapse
    // into one, with the tooltip hung on it.
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
    // 🚨A screen reader is not a pointer: its activation arrives as
    // SemanticsAction.tap, which the claim never hears, so the node gets the
    // press itself.
    if (onPress case final onTap?) {
      config.onTap = onTap;
    }
  }

  // ── lifecycle ──────────────────────────────────────────────────────

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _laidStateLayer.attached();
  }

  @override
  void detach() {
    _hovered = false;
    _pressed = false;
    _laidStateLayer.detached();
    super.detach();
  }

  @override
  void dispose() {
    _arenaTap.dispose();
    _stateLayerPaint.dispose();
    super.dispose();
  }
}
