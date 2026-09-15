import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import 'axis_bar_gesture.dart';
import 'inline_numeric_field.dart';

/// A numeric READOUT you can operate (UI-R18 #21, the shared vocabulary
/// for the canvas angle/zoom texts and any future value label):
/// - horizontal DRAG adjusts the value ([unitsPerPixel] per pixel,
///   reported as whole-unit deltas through [onDragDelta]);
/// - a single TAP swaps to an inline numeric field (Enter/tap-out commits
///   through [onEditSubmit], Escape cancels).
///
/// R10: the field used to open on a DOUBLE tap, which held every tap on
/// this label for the double-tap window — ~300ms of nothing happening,
/// which is what the user asked to be rid of everywhere. It cost nothing
/// to give up: there was no single-tap action to collide with, and the
/// app's rule is now one line — a tap edits a number, a double tap opens
/// a thing.
///
/// 🚨H24 (유저 2026-09-15: 「뷰어쪽 줌 레일스크롤바랑 겹치는거」): A PRESS
/// THAT STARTS HERE IS THE LABEL'S, WHICHEVER WAY IT MOVES. Tap and drag
/// used to settle it between them in the arena — past the slop the drag
/// won, and the tap was refused — which left the arena open to a list
/// around the label. 🧪Measured in a scroller: a drag that ran straight up
/// moved the list 120px for touch, pen and mouse alike (a horizontal
/// recogniser never crosses its slop on one). The drag takes the arena on
/// the first movement now, as the slider's does
/// ([OwningHorizontalDragGestureRecognizer]) — which is exactly what would
/// refuse a tap left in the arena on any wobble (F-120's shape), so the tap
/// is the claim's, fired on release inside
/// ([_DragValueLabelState._editUnlessScrubbed]).
class DragValueLabel extends StatefulWidget {
  const DragValueLabel({
    super.key,
    required this.keyValue,
    required this.text,
    required this.onDragDelta,
    required this.onEditSubmit,
    this.unitsPerPixel = 1.0,
    this.width = 48,
    this.tooltip,
    this.textStyle,
    this.inputKeyValue,
    this.textAlign = TextAlign.center,
  });

  /// Stable widget key base (`keyValue` label / `keyValue`-input).
  final String keyValue;

  /// Overrides the inline editor's key (hosts with pre-existing key
  /// contracts); defaults to `keyValue`-input.
  final String? inputKeyValue;

  /// The resting readout ('90%', '-15°', …).
  final String text;

  /// Whole-unit drag steps (sign follows the drag direction).
  final ValueChanged<double> onDragDelta;

  /// Receives the raw typed text on commit; the owner parses/clamps.
  final ValueChanged<String> onEditSubmit;

  final double unitsPerPixel;
  final double width;
  final String? tooltip;
  final TextStyle? textStyle;

  /// How the resting readout sits in its box. Centre is the default every
  /// caller had before the transform panel asked for right-aligned
  /// numbers; whether the rest should follow is a UI-session question,
  /// not this one's.
  final TextAlign textAlign;

  @override
  State<DragValueLabel> createState() => _DragValueLabelState();
}

class _DragValueLabelState extends State<DragValueLabel> {
  bool _editing = false;
  double _pendingUnits = 0;

  /// Whether the press under way has moved the value.
  bool _scrubbedThisPress = false;

  /// Where the press went down, how far along the label it may go before
  /// the value moves, and whether it has gone that far.
  ///
  /// ⛔NOT A NEW THRESHOLD. It is the rule the plain horizontal recogniser
  /// this replaced applied before its first delta, spelled the same way:
  /// the pointer kind's hit slop, measured as the press's net travel along
  /// x. The owning recogniser takes the arena on the first movement and
  /// reports what follows, so without this a pen that wobbles in a few
  /// steps would move the zoom and lose its tap.
  double _downX = 0;
  double _slop = 0;
  bool _pastTheSlop = false;

  /// The readout with its units stripped — '−15°' seeds the field as
  /// '-15', because what you are replacing is the NUMBER.
  String get _seed => widget.text.replaceAll(RegExp(r'[^0-9.\-]'), '');

  void _beginEdit() => setState(() => _editing = true);

  void _commitEdit(String text) {
    setState(() => _editing = false);
    if (text.isNotEmpty) {
      widget.onEditSubmit(text);
    }
  }

  void _pressStarted(PointerDownEvent event) {
    _scrubbedThisPress = false;
    _pastTheSlop = false;
    _downX = event.position.dx;
    _slop = computeHitSlop(
      event.kind,
      MediaQuery.maybeGestureSettingsOf(context),
    );
  }

  bool _beyondTheSlop(Offset globalPosition) =>
      (globalPosition.dx - _downX).abs() > _slop;

  void _dragStarted(DragStartDetails details) {
    _pendingUnits = 0;
    _pastTheSlop = _beyondTheSlop(details.globalPosition);
  }

  /// The event that carries the press past the slop is the one the old
  /// recogniser accepted on, and it reported nothing for it either — the
  /// deltas after it are the scrub.
  void _dragUpdated(DragUpdateDetails details) {
    if (!_pastTheSlop) {
      _pastTheSlop = _beyondTheSlop(details.globalPosition);
      return;
    }
    _pendingUnits += details.delta.dx * widget.unitsPerPixel;
    final whole = _pendingUnits.truncateToDouble();
    if (whole != 0) {
      _pendingUnits -= whole;
      _scrubbedThisPress = true;
      widget.onDragDelta(whole);
    }
  }

  /// A press edits the number unless it moved the value.
  ///
  /// ⛔Not the arena: the drag takes it on the first movement, so the arena
  /// can no longer tell a tap from a scrub. The verb's own answer does —
  /// did a whole unit go out.
  void _editUnlessScrubbed() {
    if (!_scrubbedThisPress) {
      _beginEdit();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: widget.width,
        child: InlineNumericField(
          fieldKey: ValueKey<String>(
            widget.inputKeyValue ?? '${widget.keyValue}-input',
          ),
          initialText: _seed,
          textStyle: widget.textStyle ?? const TextStyle(fontSize: 12),
          onSubmit: _commitEdit,
          onCancel: () => setState(() => _editing = false),
        ),
      );
    }
    final label = MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      // ⚠️The order is what makes the tap right. Pointer-up runs deepest
      // first, so [DragVerbClaim] has let its claim go by the time
      // [ControlPressClaim] asks whether a drag verb owns the pointer — the
      // claim then fires, and [_editUnlessScrubbed] is what refuses a press
      // that scrubbed.
      child: ControlPressClaim(
        onPressed: _editUnlessScrubbed,
        child: Listener(
          onPointerDown: _pressStarted,
          child: DragVerbClaim(
            behavior: HitTestBehavior.opaque,
            child: RawGestureDetector(
              key: ValueKey<String>(widget.keyValue),
              behavior: HitTestBehavior.opaque,
              gestures: <Type, GestureRecognizerFactory>{
                OwningHorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      OwningHorizontalDragGestureRecognizer
                    >(
                      () => OwningHorizontalDragGestureRecognizer(
                        debugOwner: this,
                      ),
                      (recognizer) {
                        recognizer.onStart = _dragStarted;
                        recognizer.onUpdate = _dragUpdated;
                      },
                    ),
              },
              child: SizedBox(
                width: widget.width,
                child: Text(
                  widget.text,
                  textAlign: widget.textAlign,
                  style: widget.textStyle ?? const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return tooltip == null ? label : Tooltip(message: tooltip, child: label);
  }
}
