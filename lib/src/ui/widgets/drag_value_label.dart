import 'app_tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../input/control_press_claim.dart';
import '../input/wheel_law.dart';
import '../text/full_width_numerals.dart' show halfWidthDigitsOnly;
import '../text/readout_text.dart' show ReadoutPart, readoutParts;
import '../theme/app_theme.dart' show AppColors;
import '../theme/disabled_ink.dart';
import '../theme/text_on_ground.dart';
import '../timeline/memo_token.dart' show Kept, keptWhileSame;
import 'axis_bar_gesture.dart';
import 'field_slider.dart';
import 'inline_numeric_field.dart';
import 'owning_axis_grip.dart';
import 'value_hands.dart';

/// A NUMBER YOU OPERATE, by hands that each do ONE thing (UI-R18 #21, the
/// shared vocabulary for the canvas angle/zoom, the page readouts and every
/// number box):
/// - its FACE drags — along x, from the first pixel, whatever the pointer
///   ([unitsPerPixel] per pixel, reported as whole units through
///   [onDragDelta]); a press that does not move does nothing; the wheel
///   over it turns it a step a notch;
/// - its STEPS (the settings bar's own ±, [ValueSteps]) move it a step;
/// - its PENCIL ([ValuePencil]) opens the inline field — the number alone
///   ([readoutParts]), selected, the field all of the readout; Enter or a
///   press elsewhere commits through [onEditSubmit], Escape abandons.
///
/// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「모든 드래그+편집이 가능한
/// 박스를 구조를 나누고싶어. 펜으로도 1px만움직여도 드래그로 조정가능하고
/// 편집도 떼면 바로 가능하게하려면 그냥 버튼을 나누는게 좋아보이거든? 지금의
/// 박스는 그냥 드래그만 하고, 편집창 여는건 그 옆에 편집아이콘 둬서 그거
/// 누르면 열리도록」 · 「상자에 한걸음 올리기 내리기버튼들도 동일하게
/// 넣고싶어」 · 휠 「좋아」. ↩️A tap on the face opened the field (R10: once
/// a double tap), so every press waited for its release to tell a tap from
/// a drag, and the drag waited out the pointer's slop so a wobbling tap
/// stayed a tap — 18px a pen had to travel before a fine adjustment began,
/// and ONE pixel for a pen the OS calls a mouse, whose wobble scrubbed.
///
/// 🚨H24 (유저 2026-09-15: 「뷰어쪽 줌 레일스크롤바랑 겹치는거」): A PRESS
/// THAT STARTS ON THE FACE IS THE FACE'S, WHICHEVER WAY IT MOVES. The drag
/// takes the arena on the first movement
/// ([OwningHorizontalDragGestureRecognizer]), so no list around it ever
/// scrolls; a vertical move scrubs nothing and scrolls nothing.
class DragValueLabel extends StatefulWidget {
  /// The bare readout — the number in its own width, its pencil after it
  /// where a number is typed into it ([onEditSubmit]); its steps where the
  /// host has none of its own ([steps]: the canvas bar turns the view with
  /// its ⟲ ⟳, the page band with its ◀ ▶).
  const DragValueLabel({
    super.key,
    required this.keyValue,
    required this.text,
    required this.onDragDelta,
    this.onEditSubmit,
    this.unitsPerPixel = 1.0,
    this.width = 48,
    this.tooltip,
    this.textStyle,
    this.inputKeyValue,
    this.textAlign = TextAlign.center,
    this.enabled = true,
    this.onOperationStart,
    this.onOperationEnd,
    this.digitsOnly = false,
    this.steps = false,
    this.stepBeforePencil,
  }) : name = null,
       turned = false,
       _face = _Face.bare;

  /// THE NUMBER BOX: this number wearing a settings bar's face — its frame,
  /// its name at the left, its number at the right ([FieldSlider.frameOf])
  /// — without the fill, for a value with no range to fill; and the bar's
  /// hands after it, its steps and its pencil, in the column a bar's stand
  /// in. It fills the width it is given.
  ///
  /// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「다 추천대로」 — 숫자는
  /// 「다른 도구의 숫자 상자와 같은 모양」.
  ///
  /// [turned]: the box turned a quarter on its side by its host (a
  /// `RotatedBox`), as Latin turns in vertical writing — the x-sheet's lane
  /// values (유저 2026-10-11: 「일본어 세로쓰기에서 영어 세로쓰기인데 진짜로
  /// 90도눕혀서 쓰는것처럼 하면 길이 다 타임라인이랑 똑같이 들어갈거같은데
  /// 그렇게하자」). The same box with the same hands; its drag runs along the
  /// column, and its cursor says so. ↩️It STOOD UP in the sheet's 28px
  /// column instead (2026-10-10): a small box whose number shrank into it,
  /// with no name, no steps, and its pencil under it.
  const DragValueLabel.box({
    super.key,
    required this.keyValue,
    required this.text,
    required this.onDragDelta,
    required this.onEditSubmit,
    this.name,
    this.unitsPerPixel = 1.0,
    this.tooltip,
    this.inputKeyValue,
    this.enabled = true,
    this.onOperationStart,
    this.onOperationEnd,
    this.digitsOnly = false,
    this.turned = false,
  }) : width = double.infinity,
       textStyle = null,
       textAlign = TextAlign.right,
       steps = true,
       stepBeforePencil = null,
       _face = _Face.box;

  /// What a bare readout [width] wide takes of its row with its hands after
  /// it — its pencil, and its steps where it carries them ([steps]) — for a
  /// host that budgets its row before it builds it (the canvas pill).
  static double rowWidthOf(double width, {bool steps = false}) =>
      width + ValuePencil.reach + (steps ? ValueSteps.reach : 0);

  /// What a bare readout handed no [textStyle] sets its number in where
  /// [context] shows it — for a host that makes the readout as wide as the
  /// widest number it will say (the page band).
  static TextStyle bareStyleIn(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(_bareStyle);

  static const TextStyle _bareStyle = TextStyle(fontSize: 12);

  /// What a box says it holds, inside at the left — `X`, a mesh's columns.
  /// Null on the bare readout, and on a box whose row already names it.
  final String? name;

  /// Whether its host turned it a quarter on its side ([DragValueLabel.box]).
  final bool turned;

  /// Which face — the bare readout or the box.
  final _Face _face;

  /// Whether the typed value is a whole number with no sign: the field
  /// takes digits alone (full-width ones converted) on the number pad
  /// ([halfWidthDigitsOnly]). The readouts that type a sign or a point
  /// leave it false.
  final bool digitsOnly;

  /// Called ONCE at the top of an operation — a scrub, a step, a notch of
  /// the wheel, a typed commit — before the value moves, for a host that
  /// records operations rather than values.
  ///
  /// ⚠️A scrub is one operation made of many [onDragDelta] calls, and only
  /// this widget knows where it began. Null for every readout that does
  /// not care, which is most of them.
  final VoidCallback? onOperationStart;

  /// Called ONCE when an operation is over — the press that moved the
  /// value let go or was taken away, a step or a notch was taken — for a
  /// host that SHOWS a scrub while it runs and writes it once at the end
  /// (a timeline lane: one drag, one undo). Null for every readout that
  /// writes as it goes, which is the rest of them.
  final VoidCallback? onOperationEnd;

  /// Whether the bare readout carries the steps ([ValueSteps]) — where its
  /// host has no steps of its own beside it. A box always does.
  final bool steps;

  /// The host's step that stands between the number and its pencil: the
  /// page band's ▶, so its pencil comes after both of its steps as a box's
  /// comes after its ± (유저 2026-10-11: 「페이지띠는 아래버튼 밑에
  /// 연필버튼오도록. 위/페이지/아래 이런건 이어지는게 이쁘잖아」 — said of
  /// the strip that stood on the left edge; lying in the band since F-383,
  /// it reads ◀ · page · ▶ and then the pencil).
  final Widget? stepBeforePencil;

  /// Stable widget key base: `keyValue` the face, `keyValue`-edit its
  /// pencil, `keyValue`-step-up / -down its steps, `keyValue`-input its
  /// field.
  final String keyValue;

  /// Overrides the inline editor's key (hosts with pre-existing key
  /// contracts); defaults to `keyValue`-input.
  final String? inputKeyValue;

  /// The resting readout ('90%', '-15°', …).
  final String text;

  /// Whole-unit drag steps (sign follows the drag direction). A step and a
  /// notch of the wheel are one unit each.
  ///
  /// 🚨ONCE A FRAME, the hand's whole moves since the last (🔬
  /// a-drag-readout-drops-a-move, 10-27): two moves of the hand can land
  /// before the host builds the readout again, and a host counting each
  /// from the value it built with lost the first — a −30px drag of the
  /// timeline's zoom stood at 100%, not 80%. Handed on at the top of the
  /// next frame, a move always finds the host built with the last one, so
  /// `built + units` is right in every host.
  final ValueChanged<double> onDragDelta;

  /// Receives the raw typed text on commit; the owner parses/clamps. Null
  /// on a number that is only dragged: it has no pencil (the timeline's
  /// zoom, F-463 — 「연필버튼 삭제」).
  final ValueChanged<String>? onEditSubmit;

  final double unitsPerPixel;
  final double width;
  final String? tooltip;
  final TextStyle? textStyle;

  /// How the resting readout sits in its box. Centre is the default every
  /// caller had before the transform panel asked for right-aligned
  /// numbers; whether the rest should follow is a UI-session question,
  /// not this one's.
  final TextAlign textAlign;

  /// False leaves the readout where it is: no scrub, no steps, no field,
  /// and the text wears the disabled foreground every icon button wears
  /// (`AppIconButton`'s `disabledForegroundColor`).
  final bool enabled;

  @override
  State<DragValueLabel> createState() => _DragValueLabelState();
}

enum _Face { bare, box }

class _DragValueLabelState extends State<DragValueLabel> {
  bool _editing = false;
  double _pendingUnits = 0;

  /// Whether the press under way has moved the value.
  bool _scrubbedThisPress = false;

  /// The hands as last built, and what they were built from
  /// ([keptWhileSame]) — kept, as a settings bar keeps its own: a lane's
  /// boxes rebuild on every frame the cursor moves, and the hands change
  /// with none of that.
  final Map<Type, Kept<Object?>> _hands = {};

  /// The readout as ONE number and its unit — null when it is not one.
  ReadoutPart? get _part => switch (readoutParts(widget.text)) {
    [final part] => part,
    _ => null,
  };

  /// The readout's number alone — `-15°` opens as `-15`, because what you
  /// are replacing is the NUMBER ([readoutParts], the law every typed number
  /// opens by). ↩️A regex of its own stood here that dropped every
  /// character that was not a digit, so the page readout `3 / 7` opened as
  /// `37`.
  String get _seed => _part?.number ?? widget.text;

  void _beginEdit() => setState(() => _editing = true);

  void _commitEdit(String text) {
    setState(() => _editing = false);
    final submit = widget.onEditSubmit;
    if (text.isNotEmpty && submit != null) {
      widget.onOperationStart?.call();
      submit(text);
    }
  }

  void _dragStarted(DragStartDetails details) {
    _pendingUnits = 0;
    _scrubbedThisPress = false;
  }

  /// Every pixel counts from the first: the face has no tap left to keep
  /// apart from a drag.
  void _dragUpdated(DragUpdateDetails details) {
    _pendingUnits += details.delta.dx * widget.unitsPerPixel;
    final whole = _pendingUnits.truncateToDouble();
    if (whole != 0) {
      _pendingUnits -= whole;
      _unheardUnits += whole;
      _unheardCall ??= SchedulerBinding.instance.scheduleFrameCallback(
        (_) => _handOn(),
      );
    }
  }

  /// The whole units the hand moved that the host has not been handed —
  /// handed on once a frame ([DragValueLabel.onDragDelta]).
  double _unheardUnits = 0;

  /// The frame callback that hands them on, while one waits.
  int? _unheardCall;

  void _handOn() {
    _unheardCall = null;
    final units = _unheardUnits;
    _unheardUnits = 0;
    if (units == 0) {
      return;
    }
    // ⚠️On the FIRST whole unit, not on the press: a press that never
    // moves the value is not an operation.
    if (!_scrubbedThisPress) {
      widget.onOperationStart?.call();
    }
    _scrubbedThisPress = true;
    widget.onDragDelta(units);
  }

  /// The press is over — what it moved handed on first: a scrub it made is
  /// done ([DragValueLabel.onOperationEnd]).
  void _scrubOver() {
    if (_unheardCall case final call?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(call);
      _handOn();
    }
    if (_scrubbedThisPress) {
      _scrubbedThisPress = false;
      widget.onOperationEnd?.call();
    }
  }

  /// One step [direction] (+1 up, -1 down) — a whole operation of its own,
  /// as a step of a settings bar is: a ± press, a notch of the wheel.
  void _step(int direction) {
    if (!widget.enabled) {
      return;
    }
    widget.onOperationStart?.call();
    widget.onDragDelta(direction.toDouble());
    widget.onOperationEnd?.call();
  }

  void _wheel(PointerScrollEvent event) {
    if (event.scrollDelta.dy == 0) {
      return;
    }
    _step(event.scrollDelta.dy < 0 ? 1 : -1);
  }

  @override
  void dispose() {
    if (_unheardCall case final call?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(call);
    }
    super.dispose();
  }

  /// How tall the bare readout's hands stand.
  static const double _bareHandsHeight = 20;

  double get _handsHeight => switch (widget._face) {
    _Face.box => FieldSlider.defaultHeight,
    _Face.bare => _bareHandsHeight,
  };

  /// The field the readout turns into, holding [_seed] — and nothing else:
  /// typed in, a readout is all field, its name and its unit gone with the
  /// rest of its chrome (유저 2026-10-11: 「X같은 글자 없애고
  /// 전면텍스트박스로 하는거니까 뒤에 붙은 %나 도같은 단위도 텍스트편집창에서
  /// 없도록. 진짜 박스 전면 텍스트로 하고싶은거야」). ↩️The unit stood beside
  /// the field and the name before it; a narrow readout kept half of itself
  /// for the unit.
  Widget _field(TextStyle style, TextAlign align) => InlineNumericField(
    fieldKey: ValueKey<String>(
      widget.inputKeyValue ?? '${widget.keyValue}-input',
    ),
    initialText: _seed,
    textStyle: style,
    textAlign: align,
    keyboardType: widget.digitsOnly ? TextInputType.number : null,
    inputFormatters: widget.digitsOnly ? halfWidthDigitsOnly : null,
    onSubmit: _commitEdit,
    onCancel: () => setState(() => _editing = false),
  );

  /// The bare readout: the number, in its own width — typed in, all of it
  /// the field.
  Widget _bare(BuildContext context) {
    final base = widget.textStyle ?? DragValueLabel._bareStyle;
    final style = widget.enabled
        ? base
        : base.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.38),
          );
    return SizedBox(
      width: widget.width,
      child: _editing
          ? _field(style, TextAlign.center)
          : Text(widget.text, textAlign: widget.textAlign, style: style),
    );
  }

  /// The box: a settings bar's frame around the name and the number —
  /// typed in, all of it the field, in a typed frame ([FieldSlider.frameOf]).
  Widget _box(BuildContext context) {
    const height = FieldSlider.defaultHeight;
    final ink = TextStyle(
      color: dimmedIfDisabled(
        textOnColor(AppColors.surface),
        enabled: widget.enabled,
      ),
    );
    final numberStyle = FieldSlider.valueStyleIn(context)?.merge(ink) ?? ink;
    final name = widget.name;
    return DecoratedBox(
      decoration: FieldSlider.frameOf(
        height,
        enabled: widget.enabled,
        typed: _editing,
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FieldSlider.inset),
          child: Row(
            children: _editing
                ? [Expanded(child: _field(numberStyle, TextAlign.right))]
                : [
                    if (name != null)
                      Text(
                        name,
                        maxLines: 1,
                        style:
                            Theme.of(
                              context,
                            ).textTheme.labelSmall?.merge(ink) ??
                            ink,
                      ),
                    Expanded(
                      child: Text(
                        widget.text,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        style: numberStyle,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  /// Whether a number is typed into it: its pencil is.
  bool get _typed => widget.onEditSubmit != null;

  /// [face] with its hands after it: its steps where it carries them, and
  /// its pencil where a number is typed into it — after the host's step
  /// that stands there ([DragValueLabel.stepBeforePencil]).
  Widget _withHands(Widget face) {
    final hands = widget.steps || _typed
        ? keptWhileSame(
            _hands,
            DragValueLabel,
            (
              widget.enabled,
              widget.keyValue,
              widget._face,
              widget.steps,
              _typed,
            ),
            _handsNow,
          )
        : null;
    final fills = widget._face == _Face.box;
    return Row(
      mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (fills) Expanded(child: face) else face,
        ?widget.stepBeforePencil,
        ?hands,
      ],
    );
  }

  Widget _handsNow() {
    final pencil = _typed
        ? ValuePencil(
            keyValue: '${widget.keyValue}-edit',
            height: _handsHeight,
            enabled: widget.enabled,
            onPressed: _beginEdit,
          )
        : null;
    if (!widget.steps) {
      return pencil!;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueSteps(
          keyPrefix: '${widget.keyValue}-step',
          height: _handsHeight,
          enabled: widget.enabled,
          onStep: _step,
        ),
        ?pencil,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final face = widget._face == _Face.bare ? _bare(context) : _box(context);
    if (_editing) {
      return _withHands(face);
    }
    // ⚠️The press is CLAIMED though it does nothing on a release: a press
    // that starts on a control is that control's (CLAUDE.md, 「컨트롤 위에서
    // 시작한 제스처는 그 컨트롤의 것이다」), so a row around the number does
    // not take it for its own tap.
    final pressed = ControlPressClaim(
      onPressed: null,
      child: Listener(
        // H23: registered rather than handled, so the notch the number takes
        // is not also taken by a scroller or a canvas around it.
        onPointerSignal: widget.enabled
            ? (event) => handleWheelUnlessScrolling(event, context, _wheel)
            : null,
        child: OwningAxisGrip(
          key: ValueKey<String>(widget.keyValue),
          axis: Axis.horizontal,
          configure: widget.enabled
              ? (recognizer) {
                  // From the press: the first pixel is the scrub's.
                  recognizer.dragStartBehavior = DragStartBehavior.down;
                  recognizer.onStart = _dragStarted;
                  recognizer.onUpdate = _dragUpdated;
                  recognizer.onEnd = (_) => _scrubOver();
                  recognizer.onCancel = _scrubOver;
                }
              : null,
          child: face,
        ),
      ),
    );
    final label = MouseRegion(
      cursor: widget.enabled ? _dragCursor : MouseCursor.defer,
      child: pressed,
    );
    final tooltip = widget.tooltip;
    return _withHands(
      tooltip == null ? label : AppTooltip(message: tooltip, child: label),
    );
  }

  /// Which way the drag runs: down the column, on a turned box.
  MouseCursor get _dragCursor => widget.turned
      ? SystemMouseCursors.resizeUpDown
      : SystemMouseCursors.resizeLeftRight;
}
