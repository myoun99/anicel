import '../widgets/app_icon_button.dart';
import '../widgets/boolean_dot.dart';
import '../input/control_press_claim.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../input/eager_pan_gesture_recognizer.dart';

import '../../models/layer.dart';
import '../../models/timeline_frame_range.dart' show TimelineLaneSelection;
import '../../models/timeline_row_address.dart';
import '../theme/app_theme.dart' show AppColors;
import 'layer_label_controls.dart'
    show
        LayerSectionBandCell,
        RailSwipeColumnPointer,
        fxGlyph,
        layerLaneValueSlotWidth,
        layerMarkColor,
        railSelectedRowColor;
import 'timeline_current_row.dart';
import '../../models/se_name_tag.dart' show SeNameTag;
import 'se_name_tag_lane_preview.dart' show SeNameTagLanePreview;
import '../text/app_strings.dart' show AppText;
import 'layer_rail_columns.dart'
    show layerRailTrailingCells, layerRailTwirlIcon;
import 'property_lane_model.dart';
import 'se_name_tag_lane_editing.dart' show parseArgbInput;
import '../widgets/color_swatch_button.dart' show ColorSwatchButton;
import 'transform_lane_policy.dart' show laneSelectionCoversBandRow;
import 'timeline_block_word.dart';
import 'timeline_cell_style.dart'
    show
        TimelineBlockWordGrowth,
        timelineBlockWordStyle,
        timelineFittedGlyphFontSize,
        timelineInBlockInk;
import 'timeline_frame_range_gesture.dart'
    show TimelineLaneRangeCallbacks, TimelineLaneRangeGestureLayer;
import 'timeline_frame_span_layout.dart'
    show TimelineFrameSpan, TimelineFrameSpanPlacement;
import 'timeline_grid_metrics.dart';
import 'axis_turn.dart';

/// A selected lane key rings in ACCENT 1 with a thin silhouette stroke
/// (UI-R23 #4): two-thirds of the old 2px so the ring reads as a hairline,
/// not a second block edge.
const double _selectedLaneKeyBorderWidth = 4 / 3;

/// How short a stood-up lane label may get before its column sheds a
/// control instead — two frame rows of vertical writing, the same floor the
/// x-sheet's layer heading keeps (R10 R6). Long names pack into it; what
/// they must not do is pack into three pixels.
const double _laneLabelFloor = 2 * timelineFrameCellWidth;

/// The stood-up navigator (three 20px buttons) and value readout, plus
/// their leading gaps.
const double _laneNavigatorExtent = 3 * 20 + 4;

/// The stood-up value readout's type, and the most LINES any lane makes of
/// it. Three: a comma-separated pair stacks as `1170` / `,` / `827` (user,
/// 2026-08-08), and nothing this rail formats has two commas in it.
const double _laneValueFontSize = 11;
const int _laneValueMaxLines = 3;

/// WHOLE pixels, and each line gets a box of exactly this. A paragraph's
/// height rounds UP to an integer, so reserving `fontSize * lineHeight`
/// under-reserves by the rounding — 11×1.15 is 12.65 and lays out at 13,
/// which overflowed a three-line column by the 1.05px nobody budgeted.
/// A fixed box makes the arithmetic here the arithmetic that happens.
const double _laneValueLineExtent = 13;

/// 20 → 28 → 76 → three lines (user, 2026-08-08).
///
/// The value used to SHRINK into whatever was left, so any budget "worked"
/// and nobody had to ask what the readout actually costs. Then it read
/// DOWN the column one glyph per cell, and the slot had to hold SIX of
/// them — `0.0, 0.0` is eight cells, so anything smaller left a Position
/// lane reading `0…`.
///
/// Stacked as whole numbers it costs three LINES instead of six cells, and
/// the 36px that frees goes back to the lane's name — which is what the
/// column is for.
const double _laneValueExtent = _laneValueMaxLines * _laneValueLineExtent;

/// The label cell of one property lane: an AE-style property name, the
/// keyframe navigator (◀ previous key · ◆ toggle key at the playhead · ▶
/// next key) and the property's value at the playhead — tappable to type a
/// new value (which keys it, AE-style) or draggable to scrub it.
///
/// Axis rule: one widget serves both orientations. Horizontal = a rail row
/// under the layer's controls row (the timeline); vertical = a column
/// header cell beside the layer's header (the X-sheet), stacking the same
/// controls vertically.
class TimelineLaneControlsRow extends StatefulWidget {
  const TimelineLaneControlsRow({
    super.key,
    required this.layer,
    required this.lane,
    required this.metrics,
    this.currentFrameIndex = 0,
    this.onSelectFrame,
    this.laneEdit,
    this.onToggleLaneGroup,
    this.onToggleLaneGroupEnabled,
    this.onResetLaneGroup,
    this.axis = Axis.horizontal,
    this.keyPrefix = 'timeline',
    this.width,
    this.height,
    this.leadingInset = 0,
    this.currentRowHooks,
    this.hasOnionColumn = false,
    this.hasBlendColumn = false,
  });

  final Layer layer;
  final PropertyLaneRow lane;
  final TimelineGridMetrics metrics;
  final int currentFrameIndex;

  /// Extra leading indent (horizontal axis only): the timeline rail's
  /// inline section-tag slot (UI-R5) so lane labels stay aligned with
  /// their layer row's content.
  final double leadingInset;
  final ValueChanged<int>? onSelectFrame;
  final PropertyLaneEditCallbacks? laneEdit;

  /// Group headers: tapping the CHEVRON twirls its member lanes open/closed
  /// (AE group collapse); null leaves the chevron inert. The rest of the
  /// header stands on the row — see [currentRowHooks].
  final void Function(Layer layer, PropertyLaneRow lane)? onToggleLaneGroup;

  /// The group header's own ON/OFF switch (R6: AE's per-effect eyeball).
  /// Only reached for headers whose [PropertyLaneRow.groupEnabled] is set.
  final void Function(Layer layer, PropertyLaneRow lane)?
  onToggleLaneGroupEnabled;

  /// The group header's RESET (R5, AE's group Reset). Never deletes a key:
  /// it puts the group's members back to their defaults at the playhead —
  /// or at the keys a live lane-range selection covers.
  final void Function(Layer layer, PropertyLaneRow lane)? onResetLaneGroup;

  /// Which optional columns the OWNING surface carries, so a group header
  /// lays its trailing controls on the same grid its layer rows do (R5 #7,
  /// user: "그걸 원한 거야").
  ///
  /// A header used to put its fx switch straight after the label, so the
  /// switch landed at a different x on every header — wherever that
  /// header's name happened to end. It rides
  /// [layerRailTrailingCells] now, which is the same skeleton the layer row
  /// above it uses: matching the flags is what keeps the two in ONE column,
  /// and hand-placing it is exactly how it drifted before.
  final bool hasOnionColumn;
  final bool hasBlendColumn;

  /// The owning grid's frame-axis direction (drives only the cell's
  /// composition; every control behaves identically).
  final Axis axis;

  /// Key namespace ('timeline' | 'xsheet') so tests address one
  /// orientation.
  final String keyPrefix;

  /// Explicit cell size; defaults to the horizontal rail-row geometry.
  final double? width;
  final double? height;

  /// Which row the verbs act on, and how to make it THIS one by pressing
  /// the label (R10 #19's rail half). Null leaves the label inert and
  /// unwashed, which is what a passive host wants.
  final TimelineCurrentRowHooks? currentRowHooks;

  @override
  State<TimelineLaneControlsRow> createState() =>
      _TimelineLaneControlsRowState();
}

class _TimelineLaneControlsRowState extends State<TimelineLaneControlsRow> {
  bool _editingValue = false;

  /// One controller per editable NUMBER (F-22 ②③): Position is two fields
  /// rather than one box holding `120, 45`, and a unit is chrome beside the
  /// box instead of text inside it.
  final List<TextEditingController> _valueControllers = [];

  /// The units those fields are wearing, parallel to [_valueControllers].
  /// The commit puts them back, so the lane's own parser goes on reading
  /// exactly the text form it always has.
  List<String> _valueUnits = const [];

  Layer get layer => widget.layer;
  PropertyLaneRow get lane => widget.lane;
  String get _keyPrefix => widget.keyPrefix;

  /// The preview's look at the playhead — resolved ONCE per build, since
  /// both the sample text and the styles read it.
  SeNameTag get _previewTag =>
      lane.previewText!.tagAt(widget.currentFrameIndex);

  @override
  void dispose() {
    _disposeValueControllers();
    super.dispose();
  }

  void _disposeValueControllers() {
    for (final controller in _valueControllers) {
      controller.dispose();
    }
    _valueControllers.clear();
  }

  int? get _previousKeyFrame {
    int? best;
    for (final frame in lane.keyedFrames) {
      if (frame < widget.currentFrameIndex && (best == null || frame > best)) {
        best = frame;
      }
    }
    return best;
  }

  int? get _nextKeyFrame {
    int? best;
    for (final frame in lane.keyedFrames) {
      if (frame > widget.currentFrameIndex && (best == null || frame < best)) {
        best = frame;
      }
    }
    return best;
  }

  void _startValueEdit(String currentValue) {
    final parts = propertyLaneValueParts(currentValue);
    _disposeValueControllers();
    for (final part in parts) {
      _valueControllers.add(TextEditingController(text: part.number));
    }
    _valueUnits = [for (final part in parts) part.unit];
    setState(() => _editingValue = true);
  }

  // AE-style value scrubbing: the drag's TOTAL delta (positions against
  // the pointer-down origin — slop never eats into the value) maps the
  // label captured at the start; a live preview repaints only this row and
  // the release commits ONCE through the normal onSetValue path — one undo.
  String? _scrubBaseLabel;
  Offset? _scrubOrigin;
  String? _scrubPreview;

  void _startScrub(Offset globalPosition, String currentLabel) {
    _scrubBaseLabel = currentLabel;
    _scrubOrigin = globalPosition;
  }

  void _updateScrub(Offset globalPosition) {
    final base = _scrubBaseLabel;
    final origin = _scrubOrigin;
    final scrub = lane.scrubValue;
    if (base == null || origin == null || scrub == null) {
      return;
    }
    final preview = scrub(base, globalPosition - origin);
    if (preview != null) {
      setState(() => _scrubPreview = preview);
    }
  }

  void _endScrub() {
    final preview = _scrubPreview;
    setState(() {
      _scrubPreview = null;
      _scrubBaseLabel = null;
      _scrubOrigin = null;
    });
    if (preview != null) {
      widget.laneEdit?.onSetValue?.call(
        layer,
        lane,
        widget.currentFrameIndex,
        preview,
      );
    }
  }

  void _cancelScrub() {
    setState(() {
      _scrubPreview = null;
      _scrubBaseLabel = null;
      _scrubOrigin = null;
    });
  }

  void _commitValueEdit() {
    // The units go back on: what leaves here is the text form the lane's
    // parser has always read, so nothing downstream learns about fields.
    final input = joinPropertyLaneValueParts([
      for (var index = 0; index < _valueControllers.length; index += 1)
        (
          number: _valueControllers[index].text.trim(),
          unit: index < _valueUnits.length ? _valueUnits[index] : '',
        ),
    ]);
    setState(() => _editingValue = false);
    widget.laneEdit?.onSetValue?.call(
      layer,
      lane,
      widget.currentFrameIndex,
      input,
    );
  }

  Widget _navigator(ColorScheme colorScheme) {
    final keyedNow = lane.keyedFrames.contains(widget.currentFrameIndex);
    final previousKey = _previousKeyFrame;
    final nextKey = _nextKeyFrame;
    final onSelectFrame = widget.onSelectFrame;
    final laneEdit = widget.laneEdit;

    // R10 R6: stood up with the rest of the x-sheet header. The three
    // buttons are ~65px side by side and the sheet's columns are 28 — the
    // navigator was the widest thing in a column that no longer exists.
    // Chevrons follow the axis too: on the sheet the previous key is UP.
    final horizontal = widget.axis == Axis.horizontal;
    return Flex(
      direction: widget.axis,
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavigatorButton(
          buttonKey: ValueKey<String>(
            '$_keyPrefix-lane-prev-key-${layer.id}-${lane.laneId}',
          ),
          icon: horizontal ? Icons.chevron_left : Icons.keyboard_arrow_up,
          enabled: previousKey != null && onSelectFrame != null,
          onTap: () => onSelectFrame!(previousKey!),
        ),
        _NavigatorButton(
          buttonKey: ValueKey<String>(
            '$_keyPrefix-lane-key-toggle-${layer.id}-${lane.laneId}',
          ),
          enabled: laneEdit != null,
          onTap: () =>
              laneEdit!.onToggleKeyAt(layer, lane, widget.currentFrameIndex),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: keyedNow ? colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: keyedNow
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        _NavigatorButton(
          buttonKey: ValueKey<String>(
            '$_keyPrefix-lane-next-key-${layer.id}-${lane.laneId}',
          ),
          icon: horizontal ? Icons.chevron_right : Icons.keyboard_arrow_down,
          enabled: nextKey != null && onSelectFrame != null,
          onTap: () => onSelectFrame!(nextKey!),
        ),
      ],
    );
  }

  /// The stood-up readout: whole NUMBERS on their own lines, written
  /// across (user, 2026-08-08 — `1170` / `,` / `827`, and `100%` on one
  /// line the way it already was).
  ///
  /// It used to go through the vertical-writing table like every other
  /// label on the sheet, which set `1170, 827` as `1 1 7 0 , ␣ 827` — seven
  /// cells, because a four-digit run is past the 縦中横 limit and falls
  /// apart into single glyphs. A number is not prose; it wants to be read
  /// as one token, and the only thing vertical about it is which token
  /// comes next.
  ///
  /// Lines SHRINK to fit rather than ellipsise, which is this cell's
  /// exception to the rail-window rule: a truncated coordinate is a wrong
  /// coordinate, and the user allowed the smaller type here by name.
  Widget _stackedValue(String label, ColorScheme colorScheme) {
    final style = TextStyle(
      fontSize: _laneValueFontSize,
      color: colorScheme.primary,
    );
    final lines = _valueLines(label);
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (final line in lines)
          SizedBox(
            height: _laneValueLineExtent,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(line, maxLines: 1, softWrap: false, style: style),
            ),
          ),
      ],
    );
  }

  /// [label] split into the lines it stacks as: each comma-separated
  /// component, with the comma itself on a line between them so the pair
  /// still reads as a pair. Uncommaed values are one line, unchanged.
  ///
  /// Capped at [_laneValueMaxLines], which is what the slot is sized for.
  /// Nothing this rail formats reaches it — a coordinate pair is the
  /// longest at three — but a slot sized by a constant and filled by a
  /// stranger's string should say what happens when the two disagree, and
  /// "overflow the column" is not the answer.
  static List<String> _valueLines(String label) {
    if (!label.contains(',')) {
      return [label];
    }
    final lines = <String>[];
    for (final component in label.split(',')) {
      if (lines.isNotEmpty) {
        lines.add(',');
      }
      final trimmed = component.trim();
      if (trimmed.isNotEmpty) {
        lines.add(trimmed);
      }
    }
    if (lines.isEmpty) {
      return [label];
    }
    return lines.length <= _laneValueMaxLines
        ? lines
        : lines.sublist(0, _laneValueMaxLines);
  }

  /// AE's blue value column: the property's value at the playhead; tap to
  /// type (Enter commits and keys the value there), drag to scrub.
  Widget _valueCell(ColorScheme colorScheme, String valueLabel) {
    final laneEdit = widget.laneEdit;
    // 🚨F-22 (유저 2026-08-24): 「fx의 멤버 편집, **타입에 따라 확실하게
    // 나누기. 지금 싹 다 텍스트임.** … **Bold같은 불리언 타입은 그냥 누르면
    // 전환되는 버튼**이도록」.
    //
    // A flag has two states and no digits, so the value cell IS the
    // control: a tap flips it, and nothing here has to open a text box for
    // someone to type the word `on`. Scrubbing is off for the same reason —
    // there is nothing between the two states to scrub through.
    if (lane.valueKind == PropertyLaneValueKind.boolean &&
        laneEdit?.onSetValue != null) {
      final on = valueLabel == 'on';
      return ControlPressClaim(
        onPressed: () => laneEdit!.onSetValue!.call(
          layer,
          lane,
          widget.currentFrameIndex,
          on ? 'off' : 'on',
        ),
        child: InkWell(
          key: ValueKey<String>(
            '$_keyPrefix-lane-toggle-${layer.id}-${lane.laneId}',
          ),
          onTap: silentPress(
            () => laneEdit!.onSetValue!.call(
              layer,
              lane,
              widget.currentFrameIndex,
              on ? 'off' : 'on',
            ),
          ),
          // The app's one boolean (guide-sym ⑥⑧ — 유저 named this very cell:
          // 「네임태그fx의 bold랑 쇼 다이얼로그」). It drew a check box, and a
          // CHECK MARK is what 「선택 표시는 색상만」 names outright.
          child: Center(child: BooleanDot(value: on, size: 14)),
        ),
      );
    }
    // 🚨A COLOUR IS A SWATCH, NOT A WORD (유저 2026-08-26: 「아직도 멤버의
    // 색부분이 텍스트편집임. **색버튼으로**」). The same round control the
    // canvas surfaces and the onion tints are chosen with, so 「how do I
    // pick a colour」 has one answer everywhere.
    //
    // ⚠️`none` IS a value here, not a missing one, and the swatch says so
    // with its own face — the box behind a name can be turned off, and
    // [ColorSwatchButton.onNone] is the way back to that. The lane knows
    // whether absence is possible; nothing here switches on a lane id.
    if (lane.valueKind == PropertyLaneValueKind.color &&
        laneEdit?.onSetValue != null) {
      void set(String text) => laneEdit!.onSetValue!.call(
        layer,
        lane,
        widget.currentFrameIndex,
        text,
      );
      return Center(
        child: ColorSwatchButton(
          keyValue: '$_keyPrefix-lane-color-${layer.id}-${lane.laneId}',
          color: parseArgbInput(valueLabel),
          onChanged: (argb) => set(formatLaneColorValue(argb)),
          onNone: lane.colorCanBeNone ? () => set('none') : null,
        ),
      );
    }
    if (_editingValue) {
      return _valueEditor(colorScheme);
    }

    // Tap types a value; a drag SCRUBS it (AE-style — horizontal for the
    // first component, vertical for Position's y; the drag-axis mapping is
    // the lane's, identical in both orientations) and commits once on
    // release. EAGER slop (UI-R22F #2): a slow scrub must never lose the
    // arena to the grid scroll.
    //
    // ⛔EVERY DEVICE. The value field is a control — 「슬라이더위에서
    // 조작하기 시작하면 슬라이더조작하는거고 그 외가 스크롤인거야」(유저
    // 08-14), and 09-23 「버튼은 무조건 강한클레임」. ↩️It took the timeline's
    // edit-pan devices, so while one finger scrolls the timeline a finger on
    // a value scrolled the rail instead of scrubbing.
    return RawGestureDetector(
      gestures: laneEdit?.onSetValue == null
          ? const <Type, GestureRecognizerFactory>{}
          : <Type, GestureRecognizerFactory>{
              EagerPanGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    EagerPanGestureRecognizer
                  >(() => EagerPanGestureRecognizer(debugOwner: this), (
                    recognizer,
                  ) {
                    // PEN-11: device gesture settings (RawGestureDetector
                    // does not inject them — kTouchSlop 18 vs device ~8).
                    recognizer.gestureSettings =
                        MediaQuery.maybeGestureSettingsOf(context);
                    // .down: positions measure from the pointer-down
                    // origin, so the recognizer's slop never eats into
                    // the scrubbed value.
                    recognizer.dragStartBehavior = DragStartBehavior.down;
                    recognizer.onStart = (details) =>
                        _startScrub(details.globalPosition, valueLabel);
                    recognizer.onUpdate = (details) =>
                        _updateScrub(details.globalPosition);
                    recognizer.onEnd = (_) => _endScrub();
                    recognizer.onCancel = _cancelScrub;
                  }),
            },
      child: MouseRegion(
        cursor: laneEdit?.onSetValue == null
            ? MouseCursor.defer
            : SystemMouseCursors.resizeLeftRight,
        child: InkWell(
          key: ValueKey<String>(
            '$_keyPrefix-lane-value-${layer.id}-${lane.laneId}',
          ),
          onTap: laneEdit?.onSetValue == null
              ? null
              : () => _startValueEdit(valueLabel),
          // AE's blue value.
          child: widget.axis == Axis.horizontal
              ? Text(
                  _scrubPreview ?? valueLabel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _laneValueFontSize,
                    color: colorScheme.primary,
                  ),
                )
              : _stackedValue(_scrubPreview ?? valueLabel, colorScheme),
        ),
      ),
    );
  }

  /// The value EDITOR: one box per number, and the fixed parts beside them.
  ///
  /// 🚨F-22 (유저 2026-08-24): 「**단위 같은 고정요소를 편집창에서 제거**」,
  /// 「**포지션 등 2요소는 각각 편집**(온점 없이)」.
  ///
  /// It used to be one box over the whole readout, so changing Scale meant
  /// typing the percent sign back and nudging Position's y meant retyping
  /// `120, 45` — comma, space and all — around the one number that changed.
  /// Neither is a value: they are the shape the value is printed in.
  ///
  /// ⛔The unit stays VISIBLE, just not typed. Hiding it would make the
  /// editor say less than the readout it replaces, and a person mid-edit
  /// would have to remember which of Scale and Rotation they were in.
  ///
  /// The separator does not survive: two fields ARE the pair, so a comma
  /// between them would be a third thing to look at (「온점 없이」).
  Widget _valueEditor(ColorScheme colorScheme) {
    final horizontal = widget.axis == Axis.horizontal;
    final fields = <Widget>[
      for (var index = 0; index < _valueControllers.length; index += 1)
        _valueField(colorScheme, index, horizontal: horizontal),
    ];
    if (fields.length == 1) {
      return SizedBox(height: 20, child: fields.single);
    }
    // The slot is a FIXED 80px on the rail and three lines in the sheet, so
    // the fields share it evenly rather than sizing to their contents — a
    // box that grew with its digits would move its neighbour while typing.
    return horizontal
        ? Row(
            children: [
              for (var index = 0; index < fields.length; index += 1) ...[
                if (index > 0) const SizedBox(width: 4),
                Expanded(child: SizedBox(height: 20, child: fields[index])),
              ],
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < fields.length; index += 1) ...[
                if (index > 0) const SizedBox(height: 2),
                SizedBox(height: 18, child: fields[index]),
              ],
            ],
          );
  }

  Widget _valueField(
    ColorScheme colorScheme,
    int index, {
    required bool horizontal,
  }) {
    final unit = index < _valueUnits.length ? _valueUnits[index] : '';
    return TextField(
      key: ValueKey<String>(
        // The first field keeps the key the single box had: it IS that box
        // on every lane that holds one number, which is most of them.
        index == 0
            ? '$_keyPrefix-lane-value-field-${layer.id}-${lane.laneId}'
            : '$_keyPrefix-lane-value-field-${layer.id}-${lane.laneId}-$index',
      ),
      controller: _valueControllers[index],
      autofocus: index == 0,
      style: const TextStyle(fontSize: 11),
      textAlign: horizontal ? TextAlign.right : TextAlign.center,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        border: const OutlineInputBorder(),
        // The FIXED part, worn by the box instead of typed into it.
        suffixText: unit.isEmpty ? null : unit.trim(),
        suffixStyle: TextStyle(
          fontSize: 10,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      onSubmitted: (_) => _commitValueEdit(),
      onTapOutside: (_) {
        // Tap-away cancels (Enter commits, AE-style).
        setState(() => _editingValue = false);
      },
    );
  }

  /// Pressing anywhere on the label stands on this lane. OPAQUE so the
  /// padding and the gaps stand too; the navigator buttons, the group
  /// twirl and the value editor sit DEEPER and keep winning the arena,
  /// which is what makes one press surface over the whole cell safe.
  Widget _standable(Widget cell) {
    final stand = widget.currentRowHooks?.onStandOnLane;
    if (stand == null) {
      return cell;
    }
    return GestureDetector(
      key: ValueKey<String>(
        '$_keyPrefix-lane-stand-cell-${layer.id}-${lane.laneId}',
      ),
      behavior: HitTestBehavior.opaque,
      onTap: () => stand(layer.id, lane.laneId),
      child: cell,
    );
  }

  /// The cell SUBSCRIBES to the current row rather than being rebuilt from
  /// above with it: the claim that moves the row fires on pointer-down
  /// inside gestures that must not notify, and only two rows change
  /// appearance when it moves.
  @override
  Widget build(BuildContext context) {
    final hooks = widget.currentRowHooks;
    // 🚨A LANE ROW IS 「레이어 쪽」 too (유저 확정 2026-08-30): 「레이어 쪽
    // 버튼은 탭다운, 헤더쪽은 손떼면」. Said once for the whole row, so the
    // lane's twirl and its value button cannot drift from the swipe columns
    // standing beside them.
    if (hooks == null) {
      return PressFireScope(
        fireOn: PressFire.down,
        child: _buildCell(context, null),
      );
    }
    return PressFireScope(
      fireOn: PressFire.down,
      child: ValueListenableBuilder<TimelineRowAddress?>(
        valueListenable: hooks.currentRow,
        builder: (context, currentRow, _) => _buildCell(context, currentRow),
      ),
    );
  }

  Widget _buildCell(BuildContext context, TimelineRowAddress? currentRow) {
    final colorScheme = Theme.of(context).colorScheme;
    final plate = _plate(colorScheme, currentRow);
    return _standable(
      lane.isGroupHeader
          ? _headerCell(context, colorScheme, plate)
          : _memberCell(colorScheme, plate),
    );
  }

  /// The lane's PLATE: the shared "you are standing here" wash while this
  /// row is the verbs' subject — or while you are standing INSIDE the group
  /// it leads, so the rail reads as the chain it is (layer ▸ Blur ▸ Radius
  /// all lit, user 2026-08-07).
  Color _plate(ColorScheme colorScheme, TimelineRowAddress? currentRow) {
    final lit =
        currentRowIsLane(currentRow, layer.id, lane.laneId) ||
        (lane.isGroupHeader &&
            currentRowIsInsideGroup(currentRow, layer.id, lane.laneId));
    return lit ? railSelectedRowColor(colorScheme) : AppColors.washDown;
  }

  /// The cell's box, the same for a header and a member: the rail's row
  /// width (the sheet's column), the row height, the plate and its hairline.
  /// A lane row is a PLATE belonging to the layer above it, not one of the
  /// three chrome surfaces — the same reading its frame-side half takes.
  Widget _cellBox({
    required Color plate,
    required ColorScheme colorScheme,
    required EdgeInsets padding,
    Alignment? alignment,
    required Widget child,
  }) => Container(
    key: ValueKey<String>('$_keyPrefix-lane-label-${layer.id}-${lane.laneId}'),
    // Horizontal: the section bracket occupies the leading gutter beside
    // the rail, and lane labels indent past the twirl-down chevron slot.
    width:
        widget.width ??
        (widget.metrics.layerControlsWidth -
            widget.metrics.sectionLabelGutterWidth),
    height: widget.height ?? widget.metrics.layerRowHeight,
    padding: padding,
    decoration: BoxDecoration(
      color: plate,
      border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
    ),
    alignment: alignment,
    child: child,
  );

  /// The rows' section band continues through lane rows (UI-R6 #5); the
  /// lane indent follows it by [gap]. Null off the rail (the sheet has no
  /// leading inset).
  List<Widget>? _sectionLead(double gap) {
    if (widget.axis != Axis.horizontal || widget.leadingInset <= 0) {
      return null;
    }
    return [const LayerSectionBandCell(), SizedBox(width: gap)];
  }

  // ── the group header ──────────────────────────────────────────────────

  /// AE group header ('Transform', an effect): a structural label one indent
  /// LEFT of its member lanes, no navigator/value. The chevron twirls the
  /// group open/closed (default collapsed); pressing the header itself
  /// stands on it. R10 R6: stood up on the sheet, like every other header.
  Widget _headerCell(
    BuildContext context,
    ColorScheme colorScheme,
    Color plate,
  ) {
    return _cellBox(
      plate: plate,
      colorScheme: colorScheme,
      padding: _headerPadding,
      child: Flex(
        direction: widget.axis,
        // START on BOTH axes (user, 2026-08-08): the sheet's headers used
        // to center their contents while the rail's began at the leading
        // edge, so the twirl and the name sat at a different place on each
        // surface for no reason either of them has.
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ...?_sectionLead(10),
          _groupTwirl(),
          // The name takes the leftover; the controls after it are a fixed
          // grid, so `Expanded` (not `Flexible`) — the trailing run has to
          // start at the same place on every header, and shrink-wrapping
          // the name is what made it start wherever a name happened to end.
          Expanded(child: _headerLabel(colorScheme)),
          ..._headerTrailing(context, colorScheme),
        ],
      ),
    );
  }

  EdgeInsets get _headerPadding => widget.axis == Axis.horizontal
      ? const EdgeInsets.only(right: 8)
      : const EdgeInsets.symmetric(horizontal: 2, vertical: 4);

  /// The TWIRL is the chevron's, not the whole header's (R10 #19's rail
  /// half). A header is a row you stand on and — next round — grab to
  /// reorder the chain; a label that toggles instead would have to be
  /// excluded from both, and that exclusion is exactly the kind of
  /// surface-local rule this rail keeps paying for.
  Widget _groupTwirl() {
    final onToggleGroup = widget.onToggleLaneGroup;
    final toggle = onToggleGroup == null
        ? null
        : () => onToggleGroup(layer, lane);
    return ControlPressClaim(
      onPressed: toggle,
      child: InkWell(
        key: ValueKey<String>(
          '$_keyPrefix-lane-group-toggle-${layer.id}-${lane.laneId}',
        ),
        onTap: silentPress(toggle),
        customBorder: const CircleBorder(), // R26 #28
        child: Icon(layerRailTwirlIcon(expanded: lane.groupExpanded), size: 16),
      ),
    );
  }

  /// 'Transform', 'Gaussian Blur' — property names a person reads, so they
  /// stand up on the sheet (user, 2026-08-08).
  Widget _headerLabel(ColorScheme colorScheme) => readableText(
    widget.axis,
    lane.label,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    ),
  );

  /// R5 #7: the group's switch sits in the LAYER ROW'S fx column, through
  /// the layer row's own skeleton. R6 put it straight after the label, which
  /// put it at a different x on every header. The shared `fx` glyph either
  /// way, so restyling fx still happens in exactly one place.
  List<Widget> _headerTrailing(BuildContext context, ColorScheme colorScheme) =>
      layerRailTrailingCells(
        axis: widget.axis,
        columns: widget.metrics.railColumns,
        fillReference: _groupReset(colorScheme),
        fx: _groupFx(context),
        hasOnionColumn: widget.hasOnionColumn,
        hasBlendColumn: widget.hasBlendColumn,
        trailingRegion: _groupPreview(),
      );

  /// R5: AE's group Reset, in the slot immediately left of fx — the one the
  /// fill-reference toggle owns on layer rows, and the two never appear on
  /// the same row.
  Widget? _groupReset(ColorScheme colorScheme) {
    final onReset = widget.onResetLaneGroup;
    if (onReset == null) return null;
    return AppIconButton(
      keyValue: '$_keyPrefix-lane-group-reset-${layer.id}-${lane.laneId}',
      tooltip: AppText.strings.tlResetGroup,
      size: AppIconButtonSize.micro,
      onPressed: () => onReset(layer, lane),
      icon: Icon(
        Icons.settings_backup_restore,
        size: 14,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget? _groupFx(BuildContext context) {
    final enabled = lane.groupEnabled;
    if (enabled == null) return null;
    final onToggle = widget.onToggleLaneGroupEnabled;
    return RailSwipeColumnPointer(
      child: AppIconButton(
        keyValue: '$_keyPrefix-lane-group-fx-${layer.id}-${lane.laneId}',
        tooltip:
            (enabled
                    ? AppText.strings.tlBypassLaneTemplate
                    : AppText.strings.tlApplyLaneTemplate)
                .replaceAll('{name}', lane.label),
        onPressed: onToggle == null ? null : () => onToggle(layer, lane),
        icon: fxGlyph(context: context, active: enabled, fontSize: 11),
      ),
    );
  }

  /// R5 #7: the preview fills the slots RIGHT OF fx as ONE region,
  /// right-aligned — the user's placement ②. It goes through the skeleton
  /// rather than beside it, so it cannot drift from the fx column the way a
  /// hand-placed run did.
  Widget? _groupPreview() {
    final preview = lane.previewText;
    if (preview == null) return null;
    return Align(
      alignment: widget.axis == Axis.horizontal
          ? Alignment.centerRight
          : Alignment.bottomCenter,
      child: SeNameTagLanePreview(
        key: ValueKey<String>(
          '$_keyPrefix-lane-group-preview-${layer.id}-${lane.laneId}',
        ),
        name: preview.name,
        // The dialogue SAMPLE follows the Show Dialogue member — the one
        // thing a fixed-string preview does track.
        line: _previewTag.showLine ? preview.line : '',
        tag: _previewTag,
      ),
    );
  }

  // ── a member lane ─────────────────────────────────────────────────────

  Widget _memberCell(ColorScheme colorScheme, Color plate) {
    final valueLabel = lane.valueLabel?.call(widget.currentFrameIndex);
    // A lane's name reads down its column on the sheet, through the shared
    // vertical-writing table ([readableText]).
    final label = readableText(
      widget.axis,
      lane.label,
      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
    );
    final content = widget.axis == Axis.horizontal
        ? _memberRow(colorScheme, label, valueLabel)
        : _memberColumn(colorScheme, label, valueLabel);
    final lead = _sectionLead(24);
    return _cellBox(
      plate: plate,
      colorScheme: colorScheme,
      padding: _memberPadding,
      // The rail's `centerLeft` transposed: the START of the main axis,
      // centered across it. The sheet centered on BOTH axes, which is what
      // made its lane names float in the middle of a column whose rail twin
      // begins at the leading edge.
      alignment: widget.axis == Axis.horizontal
          ? Alignment.centerLeft
          : Alignment.topCenter,
      child: lead == null
          ? content
          : Row(
              children: [
                ...lead,
                Expanded(child: content),
              ],
            ),
    );
  }

  /// 8 → 2 on the sheet: a 28px column cannot spend 16 of it on side padding.
  EdgeInsets get _memberPadding {
    if (widget.axis != Axis.horizontal) {
      return const EdgeInsets.symmetric(horizontal: 2, vertical: 4);
    }
    return widget.leadingInset > 0
        ? const EdgeInsets.only(right: 8)
        : const EdgeInsets.only(left: 24, right: 8);
  }

  /// Along the rail: navigator, name, value. The NAME takes the leftover and
  /// ellipsises; the VALUE is a fixed column at the end (R5 #20). Two flex
  /// children of equal weight is what put the numbers at a different x on
  /// every row — each was right-aligned inside HALF of whatever its name
  /// left over, and names are not the same length.
  Widget _memberRow(ColorScheme colorScheme, Widget label, String? valueLabel) {
    return Row(
      children: [
        if (lane.showsKeyNavigator) ...[
          _navigator(colorScheme),
          const SizedBox(width: 6),
        ],
        Expanded(child: label),
        const SizedBox(width: 4),
        SizedBox(
          width: layerLaneValueSlotWidth,
          // Reserved even with nothing to show, so the column survives the
          // rows that carry no readout (the Excel-grid rule the control
          // slots already follow).
          child: valueLabel == null
              ? null
              : _editingValue
              ? _valueCell(colorScheme, valueLabel)
              : Align(
                  alignment: Alignment.centerRight,
                  // A truncated coordinate is a WRONG coordinate — the
                  // sheet's stood-up readout already made that call, and a
                  // fixed column is where it starts to matter here too.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: _valueCell(colorScheme, valueLabel),
                  ),
                ),
        ),
      ],
    );
  }

  /// X-sheet lane column header: the same controls stacked vertically, and
  /// the same rule the LAYER heading beside it follows — the NAME is what a
  /// heading is for, so it is paid first and the controls shed.
  ///
  /// R10 R6: without that, the label was simply `Expanded` over whatever the
  /// navigator and the value left, and at the default dock height 'Position'
  /// packed into 35px — 2.6px per glyph, against the layer heading's
  /// guaranteed 48 one column to its left.
  ///
  /// THE RAIL ROW'S ORDER, TRANSPOSED (user, 2026-08-08): navigator, then
  /// the name, then the value at the far end. The sheet used to lead with
  /// the name and put the navigator after it, so the same three controls
  /// read in two different orders depending on which way the panel was
  /// turned. Value first in the GATE (it is a readout, and the same number
  /// is on the timeline rail), then the navigator (whose diamond is also on
  /// the frame axis). The gaps count too: without them the label's floor
  /// was 4px short of what the gate promised at every rung, and nothing
  /// noticed while the label could still pack.
  Widget _memberColumn(
    ColorScheme colorScheme,
    Widget label,
    String? valueLabel,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.maxHeight;
        const gap = 4.0;
        final showsValue =
            valueLabel != null &&
            extent >= _laneLabelFloor + gap + _laneValueExtent;
        final showsNavigator =
            lane.showsKeyNavigator &&
            extent >=
                _laneLabelFloor +
                    gap +
                    _laneNavigatorExtent +
                    (showsValue ? gap + _laneValueExtent : 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showsNavigator) ...[
              _navigator(colorScheme),
              const SizedBox(height: gap),
            ],
            Expanded(child: label),
            if (showsValue) ...[
              const SizedBox(height: gap),
              // A fixed slot, so a long readout ellipsises inside it instead
              // of pushing the heading out of its own column.
              SizedBox(
                height: _laneValueExtent,
                child: _valueCell(colorScheme, valueLabel),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _NavigatorButton extends StatelessWidget {
  const _NavigatorButton({
    required this.buttonKey,
    required this.enabled,
    required this.onTap,
    this.icon,
    this.child,
  });

  final Key buttonKey;
  final bool enabled;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ControlPressClaim(
      onPressed: enabled ? onTap : null,
      child: InkWell(
        key: buttonKey,
        onTap: silentPress(enabled ? onTap : null),
        child: SizedBox(
          width: 16,
          height: 20,
          child: Center(
            child:
                child ??
                Icon(
                  icon,
                  size: 14,
                  color: enabled
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                ),
          ),
        ),
      ),
    );
  }
}

/// The frame-axis band of one property lane: a quiet strip with key markers
/// at keyed frames (AE-style: linear keys are diamonds, HOLD keys squares).
/// Markers drag along the frame axis to move their key (snapping per frame)
/// and open the hold/delete menu on right-click or long-press.
///
/// Horizontal = a row under the layer's frame cells (the timeline);
/// vertical = a column beside the layer's frame cells (the X-sheet).
class TimelineLaneFrameRow extends StatelessWidget {
  const TimelineLaneFrameRow({
    super.key,
    required this.layer,
    required this.lane,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.leadingFrameSpacerWidth,
    required this.trailingFrameSpacerWidth,
    required this.metrics,
    this.laneRange,
    this.axis = Axis.horizontal,
    this.keyPrefix = 'timeline',
  });

  final Layer layer;
  final PropertyLaneRow lane;
  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final double leadingFrameSpacerWidth;
  final double trailingFrameSpacerWidth;
  final TimelineGridMetrics metrics;

  /// The LANE-scoped selection domain (UI-R23 #3 part 2, superseding the
  /// R22-C owner-layer fallback), and since 2026-08-08 the only thing on
  /// this band that answers a pointer wherever it exists: a tap stands
  /// here, a pan outside the selection selects, a pan inside it moves the
  /// selected keys.
  ///
  /// That is the frame BLOCK's rule, which is the point — the key markers
  /// used to sit above this layer with a drag of their own and move a
  /// single key the instant you pulled one, so the same axis had two
  /// grammars depending on whether you happened to grab a diamond.
  ///
  /// Null keeps the band display-only (the storyboard's lanes). Every
  /// timeline and x-sheet lane has one, camera included since 2026-08-08.
  final TimelineLaneRangeCallbacks? laneRange;

  /// Frame-axis direction; only the band's composition transposes.
  final Axis axis;

  /// Key namespace ('timeline' | 'xsheet').
  final String keyPrefix;

  /// ⛔NO GROUND, NO GRID, NO SEAM (I-44). This band used to paint all
  /// three — its composited wash (F-7), a grid instance of its own on it
  /// (D43-2 재개 c) and its own bottom border (D43-2 재개 d) — and to light
  /// with the standing row (F-25). The grid sheet under the rows does every
  /// one of them now, with the rail's own test for the light
  /// ([timelineRowGround]); the band is its gesture and its markers.
  @override
  Widget build(BuildContext context) {
    return _withSpacers(
      Stack(
        clipBehavior: Clip.none,
        children: [?_gestureLayer(), ..._liveMarkers()],
      ),
    );
  }

  double get _cellExtent => metrics.frameCellWidth;

  /// Cross-axis extent: rail-row height in the timeline, column width in
  /// the X-sheet (the transposed metrics carry both as layerRowHeight).
  double get _crossExtent => metrics.layerRowHeight;
  double get _visibleExtent =>
      (frameEndIndexExclusive - frameStartIndex) * _cellExtent;

  /// ONE metric law for every marker on this axis — see
  /// [timelineLaneKeyMarkerSize] / [timelineLaneUnionKeyMarkerSize].
  /// Build-time is correct HERE: the band rebuilds on zoom.
  double get _markerSize => lane.isGroupHeader
      ? timelineLaneUnionKeyMarkerSize(
          _crossExtent,
          frameCellExtent: _cellExtent,
        )
      : timelineLaneKeyMarkerSize(_crossExtent, frameCellExtent: _cellExtent);
  double get _hitSize => (_markerSize + 8).clamp(14.0, _crossExtent).toDouble();

  bool _inWindow(int frame) =>
      frame >= frameStartIndex && frame < frameEndIndexExclusive;

  /// R26 #3: the header row washes when the selection spans its WHOLE
  /// member group — the SAME predicate the gesture uses to decide
  /// move-vs-select, so what looks selected is what a drag grabs.
  bool _selectionCoversRow(TimelineLaneSelection? selection) =>
      laneSelectionCoversBandRow(selection, layer.id, lane.laneId);

  /// The band-wide LANE gesture (UI-R23 #3 part 2), UNDER the markers: pans
  /// on the band select THIS lane; marker drags keep their arena priority
  /// above. The GROUP HEADER band selects too (R26 #3): its anchor spans
  /// the WHOLE member group — the "모두에 적용되는 그 행", collapsed state
  /// included.
  Widget? _gestureLayer() {
    final range = laneRange;
    if (range == null) return null;
    return TimelineLaneRangeGestureLayer(
      key: ValueKey<String>(
        '$keyPrefix-lane-range-gesture-${layer.id}-${lane.laneId}',
      ),
      layer: layer,
      laneId: lane.laneId,
      frameStartIndex: frameStartIndex,
      leadingFrameSpacerWidth: 0,
      frameCellExtent: _cellExtent,
      crossAxisExtent: _crossExtent,
      callbacks: range,
      axis: axis,
    );
  }

  /// Markers follow the LIVE lane selection (value-only — no row rebuild)
  /// so the accent-1 rings track drags per step.
  List<Widget> _liveMarkers() {
    final listenable = laneRange?.selection;
    if (listenable == null) return _markers(null);
    return [
      ValueListenableBuilder(
        valueListenable: listenable,
        builder: (context, selection, _) =>
            Stack(clipBehavior: Clip.none, children: _markers(selection)),
      ),
    ];
  }

  /// R27 #14: the selection BAND is no longer painted here. It rides the
  /// cursor overlay with the cell selection's exact geometry and
  /// decoration, so a key span and a cell span read as one language. (The
  /// band is above the markers there; the key RING below still marks which
  /// keys are in the span.)
  List<Widget> _markers(TimelineLaneSelection? selection) => [
    ..._keyMarkers(selection),
    ..._keyNames(),
  ];

  List<Widget> _keyMarkers(TimelineLaneSelection? selection) => [
    for (final frame in lane.keyedFrames)
      if (_inWindow(frame)) _keyMarker(frame, selection),
  ];

  /// Selected markers ring in ACCENT 1 (UI-R23 #3/#4): the LANE selection
  /// owns the ring now — frame selection is a separate domain and never
  /// rings lane keys. Header union diamonds ring on a whole-group selection
  /// (R26 #3).
  Widget _keyMarker(int frame, TimelineLaneSelection? selection) {
    final hit = _hitSize;
    return placedAlong(
      axis,
      along:
          (frame - frameStartIndex) * _cellExtent + _cellExtent / 2 - hit / 2,
      across: _crossExtent / 2 - hit / 2,
      alongExtent: hit,
      acrossExtent: hit,
      child: TimelineLaneKeyMarker(
        key: ValueKey<String>(
          '$keyPrefix-lane-key-${layer.id}-${lane.laneId}-$frame',
        ),
        shape: lane.keyShapeAt(frame),
        markerSize: _markerSize,
        color: layerMarkColor(layer.mark),
        selected:
            selection != null &&
            _selectionCoversRow(selection) &&
            selection.contains(frame),
      ),
    );
  }

  /// The key's NAME — "same name, same value" made visible where the link
  /// lives (user 2026-07-30), in the middle of its cell over the mark (㉗,
  /// F-17-Q1 답 B).
  ///
  /// ↩️It used to be gone below 14px cells and on the X-sheet — both mine,
  /// 2026-08-11, when the name stood BESIDE the diamond: a word squeezed
  /// between two diamonds read as noise, and a one-cell column had no
  /// "right of the diamond". The name has sat in its own cell since F-17,
  /// so neither reason survived, and the block-word law answers a narrow
  /// cell the way it answers every block: the word keeps its type and
  /// narrows into the cell (B, 유저 2026-09-24 — 「뭐든」).
  List<Widget> _keyNames() => [
    for (final entry in lane.keyNames.entries)
      if (_inWindow(entry.key)) _keyName(entry.key, entry.value),
  ];

  /// ㉗: EVERY key name sits in the middle of its cell — and since F-17
  /// every key name is PRINTED the same way too.
  ///
  /// 🚨THE MEMBER USED TO SIT BESIDE ITS DIAMOND ON MY SAY-SO, not the
  /// user's. 유저 원문 ㉗ said 「**유니언 이름은** 오른쪽 위가 아니라 칸 중앙」
  /// — the union only — and I extended it into a rule for members and wrote
  /// the reason here as if it were theirs. `F-17-Q1` put the real question
  /// to them on 08-26 and the answer was **B — 「마크는 그대로, 이름만 칸
  /// 중앙에」**, with the objection I had assumed waved off in one line:
  /// 「키가 있는건 글자로도 아니까 아무문제없어」.
  ///
  /// ⛔So the 6px mark stays 6px (that was option A, and it was not chosen),
  /// and the name moves to the centre over it. The word itself is what says
  /// a key is there. Display only: the band's own gestures (stand, select,
  /// move) own this axis, and a label is not a second grammar.
  ///
  /// 🚨AND THE MEMBER'S WORD WORE A SECOND RULE — the band's grey and a
  /// smaller type — on my say-so again ("a member's mark is not paper").
  /// 유저 2026-09-01: 「키에 이름 지정시, 헤더엔 제대로 중앙에 검정색으로
  /// 텍스트뜨는데 멤버엔 왜 텍스트가 회색계열인지? … 다른 규칙 두지말라했는데
  /// 왜 자꾸 멋대로 하는거지? 아예 통일하라고」. One print now: the frame
  /// block's type rule, in the paper's ink, one size on the header and the
  /// member alike.
  Widget _keyName(int frame, String text) => placedAlong(
    axis,
    along: (frame - frameStartIndex) * _cellExtent,
    across: 0,
    alongExtent: _cellExtent,
    acrossExtent: _crossExtent,
    child: IgnorePointer(child: _LaneKeyName(text: text)),
  );

  /// The band between its two spacers, along the axis.
  Widget _withSpacers(Widget band) => Flex(
    direction: axis,
    key: ValueKey<String>('$keyPrefix-lane-row-${layer.id}-${lane.laneId}'),
    children: [
      sizedAlong(axis, along: leadingFrameSpacerWidth, across: _crossExtent),
      sizedAlong(
        axis,
        along: _visibleExtent,
        across: _crossExtent,
        child: band,
      ),
      sizedAlong(axis, along: trailingFrameSpacerWidth, across: _crossExtent),
    ],
  );
}

/// A key name's type — the same at every zoom and on every row: the name
/// narrows into its cell instead (B, 유저 2026-09-24).
const double _laneKeyNameFontSize = 8;

/// A named key's label, centred in its cell — a block word whose block is
/// that one cell ([TimelineBlockWord]).
///
/// ↩️It was CLIPPED to the cell (「the first letters are what tell two names
/// apart」 — mine, 2026-08-11) and its type shrank with the zoom; the law
/// every block word keeps now narrows it instead, so the whole name stays.
///
/// 🪦`nameRoom` (the room before the next diamond) and `_laneKeyNameExtent`
/// (a 9px strip above the mark) went with the beside-the-diamond layout
/// they existed to serve — `F-17-Q1` 답 B.
class _LaneKeyName extends StatelessWidget {
  const _LaneKeyName({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return TimelineBlockWord(
      // One cell: the word is centred on both axes whichever way the frame
      // axis runs.
      place: (
        axis: Axis.horizontal,
        cells: 1,
        cellIndex: 0,
        growth: TimelineBlockWordGrowth.towardBlockEnd,
        acrossAlignment: 0,
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        // The frame block's own print — ink, size, weight and the box that
        // makes centring read as centred (유저 2026-09-12: 「내부에 있는
        // 텍스트 디자인? 색도 똑같이 그대로 재사용」).
        style: timelineBlockWordStyle(
          DefaultTextStyle.of(context).style,
          ink: timelineInBlockInk(),
          fontSize: _laneKeyNameFontSize,
          bold: true,
        ),
      ),
    );
  }
}

/// ㉗ (user, 2026-08-12): 「fx(트랜스폼) 헤더의 유니언 마크를 카메라처럼
/// 크게. 멤버 유니언들의 합이라는 느낌이 나야 한다」 — a summary mark
/// stands for several keys at once, so drawing it the size of one of
/// them said the opposite. Relational rather than a second literal: a
/// union is HALF AGAIN a member's key, and it can never outgrow the row
/// it sits in.
///
/// 🚨B4-③ (2026-08-17): these two functions are THE metric law for every
/// key marker on the frame axis — member lanes, the fx transform header's
/// union, and the CAMERA row's union summary. The camera's used to be a
/// text glyph sized by the cell-fit font rule, which is exactly the
/// "subtly different size" the device showed. One constant path now; a
/// size change lands on every mark or on none.
///
/// D39 (2026-08-18): the law follows the ZOOM too — 「프레임블록
/// 텍스트/엣지처럼 줌에 따라 작아지게」. The cross-derived base runs
/// through [timelineFittedGlyphFontSize], so a 4–8px cell no longer wears
/// a fixed 13px diamond spilling across its neighbours. At the default
/// 24px cell nothing changes (the fit's knee is 14).
/// ⚠️The block TEXT this was matched to keeps its type since B (유저
/// 2026-09-24) and narrows into its block instead; a mark cannot narrow on
/// one axis (D39-2 below), so the marks keep this shrink.
double timelineLaneKeyMarkerSize(
  double crossExtent, {
  required double frameCellExtent,
}) => _squareInCell(
  timelineFittedGlyphFontSize(
    (crossExtent * 0.32).clamp(6.0, 11.0).toDouble(),
    frameCellExtent,
    crossExtent: crossExtent,
  ),
  crossExtent: crossExtent,
  frameCellExtent: frameCellExtent,
);

/// The UNION mark's size — half again a member's key (㉗), inside the same
/// cell. The ×1.5 rides ON the fitted member size, so the summary keeps
/// reading as "the sum of members" at every zoom.
double timelineLaneUnionKeyMarkerSize(
  double crossExtent, {
  required double frameCellExtent,
}) => _squareInCell(
  timelineLaneKeyMarkerSize(crossExtent, frameCellExtent: frameCellExtent) *
      1.5,
  crossExtent: crossExtent,
  frameCellExtent: frameCellExtent,
);

/// 🚨D39-2 (유저 스크린샷 3장, 2026-08-22) — **A KEY MARK IS A SQUARE, SO
/// IT IS CAPPED BY THE TIGHTER AXIS OF ITS CELL.**
///
/// > 「1-일반상태, 2-**다이아몬드가 종횡비가 이상해지기 시작**, 3-이상해짐.
/// > 크기가 종횡비 유지한채로 작아지는게아니라 **한 변만 작아지는** 느낌」
///
/// [TimelineLaneKeyMarker] draws one `Container` with an explicit width AND
/// height and rotates it 45°. Ask for more than the cell is wide and the
/// parent's constraint squeezes the WIDTH while the height holds — a
/// rectangle, and a rotated rectangle is a lozenge, not a diamond. That is
/// exactly the degradation the three screenshots step through.
///
/// The member size already ran through [timelineFittedGlyphFontSize], which
/// takes whichever axis is tighter — but two things escaped it: the fit's
/// own 4px floor, and the union's ×1.5 on top. Both are now caught here, in
/// ONE place, so the rule is "a mark never outgrows its cell" rather than a
/// patch on whichever caller showed it first.
///
/// ⚠️The floor yields to the room. A 3px cell gets a 3px mark, because a
/// square that does not fit is not a smaller square.
double _squareInCell(
  double wanted, {
  required double crossExtent,
  required double frameCellExtent,
}) {
  final room = crossExtent < frameCellExtent ? crossExtent : frameCellExtent;
  final floor = _keyMarkerFloor < room ? _keyMarkerFloor : room;
  return wanted.clamp(floor, room).toDouble();
}

/// The smallest a key mark may be drawn while it still has room — the same
/// floor [timelineFittedGlyphFontSize] holds every other mark to.
const double _keyMarkerFloor = 4.0;

/// The union key's WORD for one frame — null when the row names no key
/// there.
///
/// The band's print ([_LaneKeyName]), so the camera row says what every
/// other row says about a named key.
Widget? _unionKeyName(PropertyLaneRow lane, {required int frame}) {
  final name = lane.keyNames[frame];
  if (name == null) {
    return null;
  }
  return IgnorePointer(child: _LaneKeyName(text: name));
}

/// The UNION summary markers of one row, as [TimelineFrameSpan] children
/// for the row's span layout — the CAMERA row's key marks (B4).
///
/// The same drawing ([TimelineLaneKeyMarker]), the same metric law
/// ([timelineLaneUnionKeyMarkerSize]) and the same union data
/// ([transformUnionHeader] builds [lane]) as the fx transform header's
/// band. Only the POSITIONING differs by necessity: a cells row keeps its
/// memo through zoom steps, so the markers ride the span layout (placed at
/// LAYOUT time off the live geometry) instead of build-time `Positioned`
/// math.
List<Widget> timelineUnionKeyMarkerSpans({
  required String keyPrefix,
  required Layer layer,
  required PropertyLaneRow lane,
  required double crossExtent,
}) {
  return [
    for (final frame in lane.keyedFrames.toList()..sort())
      TimelineFrameSpan(
        key: ValueKey<String>(
          '$keyPrefix-lane-key-span-${layer.id}-${lane.laneId}-$frame',
        ),
        // The FULL cell, resolved at layout time — the cells row keeps
        // its memo through zoom steps (R28 #4), so the marker size must
        // not be baked at build. The child reads the laid-out box and
        // asks the SAME metric law (D39); Center inside the marker puts
        // the diamond on the cell centre exactly as the carved-out box
        // used to.
        placement: TimelineFrameSpanPlacement(
          startIndex: frame,
          mainExtentCells: 1,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The tighter box dimension is the cell's zoom-driven extent
            // on either axis (the fit takes the min of both anyway).
            final cellExtent = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final markerSize = timelineLaneUnionKeyMarkerSize(
              crossExtent,
              frameCellExtent: cellExtent,
            );
            final marker = TimelineLaneKeyMarker(
              key: ValueKey<String>(
                '$keyPrefix-lane-key-${layer.id}-${lane.laneId}-$frame',
              ),
              shape: lane.keyShapeAt(frame),
              markerSize: markerSize,
              color: layerMarkColor(layer.mark),
            );
            // The NAME rides the same span — 🗣️유저 2026-09-12:
            // 「카메라레이어만 레이어에 인스턴스 이름이 표시안되」: this row
            // drew the mark and left the word to a band it does not have.
            final word = _unionKeyName(lane, frame: frame);
            return word == null
                ? marker
                : Stack(fit: StackFit.expand, children: [marker, word]);
          },
        ),
      ),
  ];
}

/// One key marker. A DRAWING, and nothing else.
///
/// It used to own a drag that re-timed its own key the instant you pulled
/// it, which is not how anything else on this axis behaves: a frame block
/// is SELECTED first and the next drag moves the selection. The band
/// beneath has implemented exactly that rule the whole time — press outside
/// the selection to select, press inside it to move, tap to stand — so the
/// fix was to stop competing with it (user, 2026-08-08).
///
/// The camera row kept the old drag for one round, because its lanes had no
/// band to defer to. They do now.
///
/// [IgnorePointer] is load-bearing, not tidiness: `RenderDecoratedBox`
/// answers hit tests TRUE anywhere inside its decoration, so a drawn
/// diamond is a hit target in its own right and the Stack would stop at it
/// with the band never seeing the pointer.
///
/// PUBLIC since B4 (2026-08-17): the camera row's union summary mounts this
/// same drawing — one shape law (linear = diamond, hold = square, the frame
/// block's own paper) for every key mark on the frame axis.
class TimelineLaneKeyMarker extends StatelessWidget {
  const TimelineLaneKeyMarker({
    super.key,
    required this.shape,
    required this.markerSize,
    required this.color,
    this.selected = false,
  });

  /// 🚨F-17: a SHAPE, not a `hold` flag. The union needs a third answer —
  /// 「멤버 타입이 서로 다르면 헤더에 동그라미」 — and a second boolean
  /// beside `hold` would have made "hold and mixed at once" something a
  /// caller could hand this widget. [PropertyLaneRow.keyShapeAt] resolves
  /// it once, from sets that cannot overlap.
  final PropertyLaneKeyShape shape;
  final double markerSize;

  /// The row's COLOUR LABEL, exactly as its frame blocks take it (유저
  /// 2026-09-12: 「유니언 키 색은 프레임블록이랑 마찬가지로 색라벨 그대로.
  /// 로직 그대로 재사용해서」) — [layerMarkColor] answers an unmarked row
  /// with the same paper the blocks use, so nothing changes for one.
  final Color color;

  /// Inside the live lane selection (UI-R23 #4): the marker rings in the
  /// accent so selected keys — union diamonds included — read at a glance,
  /// and so it is visible which keys the next drag will carry.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // EVERY key mark fills like the frame blocks (UI-R24 #9 — union
    // headers, member lanes, camera lanes alike), which since 2026-09-12
    // means the row's COLOUR LABEL: 「유니언 키 색은 프레임블록이랑
    // 마찬가지로 색라벨 그대로. 로직 그대로 재사용해서」.
    final plate = Container(
      width: markerSize,
      height: markerSize,
      decoration: BoxDecoration(
        color: color,
        // The MIXED mark is the same plate, round — one drawing with one
        // border rule, so a union's third shape cannot drift in colour or
        // in ring weight from the two that were already here.
        shape: shape == PropertyLaneKeyShape.mixed
            ? BoxShape.circle
            : BoxShape.rectangle,
        // ⛔NO outline of its own (유저 2026-09-12: 「지금 실루엣에 외곽선
        // 회색 존재하는거같은데 삭제. 그냥 심플하게 바탕색만 남겨서」). The
        // one ring left is the SELECTION's, in ACCENT 1 (UI-R23 #4) —
        // colour alone, the selection rule.
        border: selected
            ? Border.all(
                color: AppColors.accent,
                width: _selectedLaneKeyBorderWidth,
              )
            : null,
      ),
    );
    // AE convention: linear keys read as diamonds, hold keys as squares —
    // and a union whose members disagree reads as a circle, which is
    // neither of the two answers it would otherwise have to pick between.
    return IgnorePointer(
      child: Center(
        child: shape == PropertyLaneKeyShape.smooth
            ? Transform.rotate(angle: 0.785398, child: plate)
            : plate,
      ),
    );
  }
}
