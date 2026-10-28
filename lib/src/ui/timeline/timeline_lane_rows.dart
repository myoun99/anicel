import '../widgets/angle_dial.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/boolean_dot.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/field_slider.dart' show FieldSlider;
import '../widgets/instant_tap_region.dart';
import '../widgets/panel_flyout.dart'
    show PanelFlyoutButton, PanelFlyoutChoice, PanelFlyoutValueChoices;
import '../widgets/rail_glyph_button.dart';
import '../widgets/scale_chain_button.dart';
import '../widgets/tick_layer.dart';
import '../input/control_press_claim.dart';
import 'dart:math' as math;
import 'dart:ui' show ClipOp;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/app_input_settings.dart' show AppInput;
import '../../models/key_mark.dart' show KeyMark;
import '../../models/layer.dart';
import '../../models/timeline_frame_range.dart' show TimelineLaneSelection;
import '../../models/timeline_row_address.dart';
import '../theme/app_theme.dart' show AppColors, AppCursors, AppShapes;
import 'layer_label_controls.dart'
    show
        LayerSectionBandCell,
        RailSwipeColumn,
        RailSwipeColumnPointer,
        fxGlyphStyle,
        layerLaneChipsSlotWidth,
        layerLanePinSlotWidth,
        layerLaneValueBoxGap,
        layerMarkColor,
        layerRailColumnWidthsIn,
        railSelectedRowColor;
import 'timeline_block_look.dart';
import 'timeline_current_row.dart';
import '../../models/se_name_tag.dart' show SeNameTag;
import 'se_name_tag_lane_preview.dart' show SeNameTagLanePreview;
import '../text/app_strings.dart' show AppText;
import '../text/readout_text.dart'
    show
        ReadoutPart,
        columnValueOf,
        joinReadoutParts,
        readoutParts,
        readsTurns,
        turnsReadoutText;
import 'layer_rail_columns.dart'
    show
        LayerFoldTwirl,
        LayerRailOptionalColumns,
        layerRailEndPadding,
        layerRailTrailingCells,
        noOptionalRailColumns;
import 'key_mark_glyph.dart' show keyMarkIsHollow, paintKeyMark;
import 'lane_graph.dart'
    show LaneGraphVerbs, LaneGraphsView, TimelineGraphSeat;
import 'lane_graph_seats.dart'
    show laneGraphDrawnLanes, laneGraphHeadedBy, lanePinOf;
import 'lane_graph_toggle.dart';
import 'property_lane_model.dart';
import 'se_name_tag_lane_editing.dart' show parseArgbInput;
import '../widgets/color_swatch_button.dart' show ColorSwatchButton;
import 'transform_lane_policy.dart' show laneSelectionPicksKey;
import 'timeline_block_word.dart';
import '../repaint_props.dart';
import 'timeline_cell_style.dart'
    show
        TimelineBlockWordGrowth,
        timelineBlockNameFontSize,
        timelineBlockWordStyle,
        timelineFittedGlyphFontSize,
        timelineJoiningLineWidth;
import 'timeline_frame_coordinate_policy.dart' show timelineFrameEdge;
import 'timeline_frame_range_gesture.dart'
    show TimelineLaneRangeCallbacks, TimelineLaneRangeGestureLayer;
import 'timeline_frame_span_layout.dart'
    show TimelineFrameSpan, TimelineFrameSpanPlacement;
import 'timeline_grid_metrics.dart';
import 'timeline_span_name.dart' show TimelineSpanName;
import 'axis_turn.dart';
import 'memo_token.dart' show ByList;

/// A selected lane key rings in ACCENT 1 with a thin silhouette stroke
/// (UI-R23 #4): two-thirds of the old 2px so the ring reads as a hairline,
/// not a second block edge.
const double _selectedLaneKeyBorderWidth = 4 / 3;

/// The ring a key inside the live lane selection wears — every key mark
/// on the frame axis that shows one: a lane's row's, and a header graph's
/// (I-3), where its keys are pressed and carried.
({Color color, double width}) get selectedLaneKeyRing =>
    (color: AppColors.accent, width: _selectedLaneKeyBorderWidth);

/// How short a stood-up lane label may get before its column sheds a
/// control instead — two frame rows of vertical writing, the same floor the
/// x-sheet's layer heading keeps (R10 R6). Long names pack into it; what
/// they must not do is pack into three pixels.
const double _laneLabelFloor = 2 * timelineFrameCellWidth;

/// The stood-up navigator: three 20px buttons.
///
/// ↩️It carried a leading gap of 4 from when the navigator stood under the
/// name (R10 R6). Above the name since I-89-Q17, its gap is the one after
/// it ([_laneStoodNavigatorGap]) — and the column paid that 4 twice, so the
/// navigator stood 4px later than it fit (found by a mutant, 2026-10-16).
const double _laneNavigatorExtent = 3 * 20;

/// The stood-up chain of a linkable lane — [AppIconButtonSize.micro]'s
/// height.
const double _laneValueLinkExtent = 18;

/// Between a lane's value and what stands before it, on either axis.
const double _laneValueGap = 4;

/// Between a stood-up lane's navigator and what stands after it.
const double _laneStoodNavigatorGap = 4;

/// A member cell's padding at its END along the rail, past the value.
const double _laneMemberEndPadding = 8;

/// A stood-up cell's padding at either end of its column.
const double _laneColumnEndPadding = 4;

/// A curve chip (I-89 ③) and the gap between two: the colours a lane's
/// numbers are drawn in, at the mock's size (5판).
const double _laneChipSize = 9;
const double _laneChipGap = 2;

/// The frame a lane row stands on — where its ◆ keys and its value is read
/// and set: its cursor's, or the first without one. A rail's bulk-drag
/// presses a lane it crosses at the same frame (F-475).
int laneRowFrame(ValueListenable<int?>? cursor) => cursor?.value ?? 0;

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
    this.frameCursor,
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
    this.optionalColumns = noOptionalRailColumns,
    this.laneGraphs = LaneGraphsView.none,
    this.laneGraphVerbs,
    this.seat,
    this.folded = false,
  });

  final Layer layer;
  final PropertyLaneRow lane;
  final TimelineGridMetrics metrics;

  /// The frame the row reads its lane AT — the playhead. The row subscribes
  /// to it itself, on a layer of its own (see [build]); null reads frame 0.
  final ValueListenable<int?>? frameCursor;

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
  /// above it uses: matching the answer is what keeps the two in ONE column,
  /// and hand-placing it is exactly how it drifted before.
  final LayerRailOptionalColumns optionalColumns;

  /// The rail's header graphs (I-89 ③): which stand open, which lanes are
  /// pinned — what a header's graph button and a member's pin show.
  final LaneGraphsView laneGraphs;

  /// What those buttons tell; null mounts none.
  final LaneGraphVerbs? laneGraphVerbs;

  /// The open header graph this lane is drawn in — its row's
  /// [TimelineDisplayRow.graph] — or null. A seated lane wears its curve's
  /// chips while the graph draws it, and its name fades while it does not.
  final TimelineGraphSeat? seat;

  /// Whether the enlarged graph folds this lane to a thin strip — its row's
  /// [TimelineDisplayRow.folded]: its plate alone, still the lane's to
  /// stand on (the mock's 5판 empties a thinned lane's rail and keeps it
  /// pressable).
  final bool folded;

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
  Layer get layer => widget.layer;
  PropertyLaneRow get lane => widget.lane;
  String get _keyPrefix => widget.keyPrefix;

  /// The preview's look at the playhead — resolved ONCE per build, since
  /// both the sample text and the styles read it.
  SeNameTag get _previewTag =>
      lane.previewText!.tagAt(_frame);

  @override
  void dispose() {
    // A label taken away mid-scrub (its row folded under it) never sees the
    // release: what it was showing is dropped once the tree settles — a
    // notifier fired while the tree is being torn down would be too soon.
    final endPreview = widget.laneEdit?.onEndPreview;
    if (_scrubbed != null && endPreview != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => endPreview());
    }
    super.dispose();
  }

  int? get _previousKeyFrame {
    int? best;
    for (final frame in lane.keyedFrames) {
      if (frame < _frame && (best == null || frame > best)) {
        best = frame;
      }
    }
    return best;
  }

  int? get _nextKeyFrame {
    int? best;
    for (final frame in lane.keyedFrames) {
      if (frame > _frame && (best == null || frame < best)) {
        best = frame;
      }
    }
    return best;
  }

  // AE-style value scrubbing, ONE NUMBER AT A TIME: a number's own box
  // moves it and no other ([_valueBoxes]) by the drag's
  // whole travel, on the label captured where the drag began — and the
  // release commits ONCE through the normal onSetValue path: one undo.
  // ↩️One drag of the whole value moved its first number along x and its
  // second along y, so a hand off its line moved both (유저 2026-10-10:
  // 「x랑 y값 안그래도 같이움직여서 불편했고」).
  //
  // 🚨F-195 (유저 2026-09-27 「레이어에서 값편집이든 … 실시간으로 화면에
  // 보이도록」): each step is SHOWN through the host's preview, not here.
  // This row used to print the scrubbed text on its own while the picture,
  // the handles and every other panel's copy of the value waited for the
  // release; now the value in flight is the session's, and this label reads
  // it back through the row gate like everything else that shows the row.
  // What stays is the gesture's own accounting — where it started, and the
  // last value it reached, for the release to write.
  String? _scrubBaseLabel;
  double _scrubTravel = 0;
  String? _scrubbed;

  void _startScrub(String currentLabel) {
    _scrubBaseLabel = currentLabel;
    _scrubTravel = 0;
    _scrubbed = null;
  }

  /// The number at [part] dragged [pixels] further. The lane's scrub reads
  /// its first number along x and its second along y, so a number hands
  /// its travel to its own axis alone.
  void _scrubPart(int part, double pixels) {
    final base = _scrubBaseLabel;
    final scrub = lane.scrubValue;
    if (base == null || scrub == null) {
      return;
    }
    _scrubTravel += pixels;
    final value = scrub(
      base,
      offsetAlong(
        part == 0 ? Axis.horizontal : Axis.vertical,
        along: _scrubTravel,
        across: 0,
      ),
    );
    // A move inside one step of the value changes nothing to show.
    if (value == null || value == _scrubbed) {
      return;
    }
    _scrubbed = value;
    widget.laneEdit?.onPreviewValue?.call(layer, lane, _frame, value);
  }

  void _endScrub() {
    final value = _scrubbed;
    _scrubBaseLabel = null;
    _scrubTravel = 0;
    _scrubbed = null;
    if (value != null) {
      widget.laneEdit?.onSetValue?.call(layer, lane, _frame, value);
    } else {
      widget.laneEdit?.onEndPreview?.call();
    }
  }

  /// [typed] in place of the number at [part], and the rest of the value as
  /// it reads — put back in the text form the lane's parser has always
  /// read, so nothing downstream learns about boxes.
  void _typePart(List<ReadoutPart> parts, int part, String typed) =>
      widget.laneEdit?.onSetValue?.call(
        layer,
        lane,
        _frame,
        joinReadoutParts([
          for (final (index, each) in parts.indexed)
            if (index == part)
              (number: typed.trim(), unit: each.unit)
            else
              each,
        ]),
      );

  Widget _navigator(ColorScheme colorScheme) {
    final keyedNow = lane.keyedFrames.contains(_frame);
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
        // A drag from the ◆ sweeps the keys down the rail (F-475); the
        // arrows beside it act, they do not switch.
        RailSwipeColumnPointer(
          column: RailSwipeColumn.laneKey,
          child: _NavigatorButton(
            buttonKey: ValueKey<String>(
              '$_keyPrefix-lane-key-toggle-${layer.id}-${lane.laneId}',
            ),
            enabled: laneEdit != null,
            onTap: () => laneEdit!.onToggleKeyAt(layer, lane, _frame),
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

  /// The VALUE column: the property's value at the playhead — a flag's
  /// ring, a colour's swatch, or its numbers in boxes ([_valueBoxes]). A
  /// drag scrubs a number, a step steps it, and its pencil types it
  /// (Enter commits and keys the value there).
  Widget _valueCell(String valueLabel) {
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
      final on = valueLabel == flagLaneWord(true);
      void flip() =>
          laneEdit!.onSetValue!.call(layer, lane, _frame, flagLaneWord(!on));
      // A drag from the ring sweeps the flags down the rail (F-475).
      return _atValueEnd(
        RailSwipeColumnPointer(
          column: RailSwipeColumn.laneFlag,
          child: ControlPressClaim(
            onPressed: flip,
            child: InkWell(
              mouseCursor: AppCursors.press,
              key: ValueKey<String>(
                '$_keyPrefix-lane-toggle-${layer.id}-${lane.laneId}',
              ),
              onTap: silentPress(flip),
              // The app's one boolean (guide-sym ⑥⑧ — 유저 named this very
              // cell: 「네임태그fx의 bold랑 쇼 다이얼로그」). It drew a check
              // box, and a CHECK MARK is what 「선택 표시는 색상만」 names
              // outright.
              child: SizedBox.square(
                dimension: FieldSlider.defaultHeight,
                child: Center(child: BooleanDot(value: on, size: 14)),
              ),
            ),
          ),
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
        _frame,
        text,
      );
      return _atValueEnd(
        ColorSwatchButton(
          keyValue: '$_keyPrefix-lane-color-${layer.id}-${lane.laneId}',
          color: parseArgbInput(valueLabel),
          onChanged: (argb) => set(formatLaneColorValue(argb)),
          onNone: lane.colorCanBeNone ? () => set('none') : null,
        ),
      );
    }
    // 🗣️I-132-Q6 (유저 2026-10-27): 「레인 하나 — 값이 메뉴, 키프레임은
    // 계단」. A menu value has no digits to scrub or type, so the cell is
    // the app's one list picker, and a pick keys the word there.
    if (lane.valueKind == PropertyLaneValueKind.choice &&
        laneEdit?.onSetValue != null) {
      final words = lane.choices;
      final values = lane.choiceValues.isEmpty ? words : lane.choiceValues;
      final held = lane.choiceHeld ?? valueLabel;
      return Padding(
        padding: const EdgeInsets.only(right: FieldSlider.handsReach),
        child: PanelFlyoutButton(
          key: ValueKey<String>(
            '$_keyPrefix-lane-choice-${layer.id}-${lane.laneId}',
          ),
          label: valueLabel,
          expand: true,
          axis: widget.axis,
          entriesBuilder: () => [
            for (var index = 0; index < words.length; index++) index,
          ].asFlyoutValueChoices(
            current: values.indexOf(held),
            choiceOf: (index) => PanelFlyoutChoice(
              key: '$_keyPrefix-lane-choice-${layer.id}-${lane.laneId}-$index',
              label: words[index],
            ),
            onPicked: (index) => laneEdit!.onSetValue!.call(
              layer,
              lane,
              _frame,
              values[index],
            ),
          ),
        ),
      );
    }
    return _valueBoxes(valueLabel);
  }

  /// The value as the tool settings' NUMBER BOXES ([DragValueLabel.box]),
  /// one for each number, side by side, each with its hands after it — a
  /// single number's box filling the column, so its hands stand where a
  /// pair's second box has its own. The sheet writes the same row, turned
  /// ([_memberColumn]). A drag on a box scrubs its number alone
  /// ([_scrubPart]), a step steps it alone, and its pencil opens it alone
  /// on its number — the whole box a field, no name and no unit.
  ///
  /// 🚨F-22 (유저 2026-08-24): 「**단위 같은 고정요소를 편집창에서 제거**」,
  /// 「**포지션 등 2요소는 각각 편집**(온점 없이)」 — and tool-settings-
  /// panel-tidy (유저 2026-10-10): 「fx에도 텍스트편집하는거 있는데 거기도
  /// 사용하는거 어떻지? x랑 y값 안그래도 같이움직여서 불편했고」 → 「A로하고」;
  /// 「x시트랑 타임라인이랑 동일하게 박스두도록 가능한가? 작아도되니까」;
  /// 「회전의 박스가 다른 박스랑 길이가 살짝 짧거든? … 행 열 느낌나게」.
  /// ↩️The value was blue text shrunk into an 80px column and stacked in
  /// lines down the sheet; a tap opened a field for each number in its
  /// place, and one drag moved both numbers.
  ///
  /// An angle ([readsTurns]) is its turns and its degrees, unnamed, the
  /// dial before them ([_withDial]).
  Widget _valueBoxes(String valueLabel) {
    final parts = readoutParts(valueLabel);
    final turns = readsTurns(parts);
    // A pair prints its unit once, after its second number (`150, 80%` —
    // After Effects' print); each box of the pair wears it.
    final pairUnit = parts.last.unit;
    Widget box(int index, ReadoutPart part) => DragValueLabel.box(
      keyValue: _valueKey(index),
      inputKeyValue: _valueFieldKey(index),
      name: parts.length == 2 && !turns ? _pairNames[index] : null,
      text: '${part.number}${part.unit.isEmpty ? pairUnit : part.unit}',
      turned: widget.axis == Axis.vertical,
      enabled: widget.laneEdit?.onSetValue != null,
      onOperationStart: () => _startScrub(valueLabel),
      onDragDelta: (pixels) => _scrubPart(index, pixels),
      onOperationEnd: _endScrub,
      onEditSubmit: (typed) => _typePart(parts, index, typed),
    );
    return Row(
      children: [
        for (final (index, part) in parts.indexed) ...[
          if (index > 0) const SizedBox(width: layerLaneValueBoxGap),
          Flexible(
            child: turns && index == 0
                ? _withDial(box(index, part), valueLabel)
                : box(index, part),
          ),
        ],
      ],
    );
  }

  /// The angle's dial ([AngleDial]) and its [turns] box after it, in the
  /// place a pair's first box has: the turns are a few digits, and the
  /// degrees keep the second's whole place, so the columns stay columns.
  ///
  /// 🗣️I-132-Q18 b (유저 2026-10-28): 「레인 줄에 작은 다이얼」. A turn of it
  /// is one operation, as a scrub is: shown as it goes, written once on the
  /// release. Upright in the sheet, which stands the value cell up.
  Widget _withDial(Widget turns, String valueLabel) {
    return Row(
      children: [
        RotatedBox(
          quarterTurns: widget.axis == Axis.vertical ? 3 : 0,
          child: AngleDial(
            key: ValueKey<String>(
              '$_keyPrefix-lane-dial-${layer.id}-${lane.laneId}',
            ),
            degrees: columnValueOf(valueLabel) ?? 0,
            enabled: widget.laneEdit?.onSetValue != null,
            onTurnStart: () => _startScrub(valueLabel),
            onTurned: _turnDial,
            onTurnEnd: _endScrub,
          ),
        ),
        const SizedBox(width: layerLaneValueBoxGap),
        Expanded(child: turns),
      ],
    );
  }

  /// The angle where the scrub began, turned [degrees] further by the dial.
  void _turnDial(double degrees) {
    final base = switch (_scrubBaseLabel) {
      final label? => columnValueOf(label),
      null => null,
    };
    if (base == null) {
      return;
    }
    final value = turnsReadoutText(base + degrees);
    if (value == _scrubbed) {
      return;
    }
    _scrubbed = value;
    widget.laneEdit?.onPreviewValue?.call(layer, lane, _frame, value);
  }

  /// Where a ring or a swatch stands in the column: at its END, where every
  /// box of the column ends — short of the boxes' hands, as a settings ring
  /// stands short of the grid's end column (`ToolSettingSurface`). ↩️In the
  /// middle, which in a column made for two boxes left it floating; then
  /// at the column's very end, past the boxes.
  Widget _atValueEnd(Widget control) => Padding(
    padding: const EdgeInsets.only(right: FieldSlider.handsReach),
    child: Align(alignment: Alignment.centerRight, child: control),
  );

  /// What a pair's two boxes are called inside them — across, then down.
  static const List<String> _pairNames = ['X', 'Y'];

  /// The key a number's readout wears. The first keeps the key the whole
  /// value had: it IS that value on every lane that holds one number.
  String _valueKey(int part) => part == 0
      ? '$_keyPrefix-lane-value-${layer.id}-${lane.laneId}'
      : '$_keyPrefix-lane-value-${layer.id}-${lane.laneId}-$part';

  /// The key its field wears while it is typed in.
  String _valueFieldKey(int part) => part == 0
      ? '$_keyPrefix-lane-value-field-${layer.id}-${lane.laneId}'
      : '$_keyPrefix-lane-value-field-${layer.id}-${lane.laneId}-$part';

  /// Pressing anywhere on the label stands on this lane — on the PRESS, as
  /// the layer row's label picks, so a sweep started here stands here first
  /// ([TimelineCurrentRowHooks.onStandOnLane], F-476). OPAQUE so the
  /// padding and the gaps stand too; the navigator buttons, the group
  /// twirl and the value editor sit DEEPER and claim their own presses
  /// (`controlOwnsTap`), which is what makes one press surface over the
  /// whole cell safe.
  Widget _standable(Widget cell) {
    final hooks = widget.currentRowHooks;
    final stand = hooks?.onStandOnLane;
    if (stand == null) {
      return cell;
    }
    final settled = hooks?.onSettledPress;
    return InstantTapRegion(
      key: ValueKey<String>(
        '$_keyPrefix-lane-stand-cell-${layer.id}-${lane.laneId}',
      ),
      behavior: HitTestBehavior.opaque,
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      onTap: (_) => stand(layer.id, lane.laneId),
      onSettledTap: settled == null ? null : (_) => settled(),
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
    // 🚨A TICK LAYER (I-22 ③): the row shows its lane AT the cursor, so it
    // rebuilds on every frame played. Its three hosts — the rail, the
    // sheet's header, the storyboard's rail — each subscribed for it, and
    // each rebuild landed bare in the host's layout scope: the rail laid
    // out again and the panel around it repainted on every playback frame.
    // It subscribes itself now, inside a layer of its own box's size.
    return SizedBox(
      width: _cellWidth,
      height: _cellHeight,
      child: TickLayer(
        // 🚨A LANE ROW IS 「레이어 쪽」 too (유저 확정 2026-08-30): 「레이어
        // 쪽 버튼은 탭다운, 헤더쪽은 손떼면」. Said once for the whole row,
        // so the lane's twirl and its value button cannot drift from the
        // swipe columns standing beside them.
        child: PressFireScope(
          fireOn: PressFire.down,
          child: _onTheCursor(
            context,
            hooks == null
                ? (context) => _buildCell(context, null)
                : (context) => ValueListenableBuilder<TimelineRowAddress?>(
                    valueListenable: hooks.currentRow,
                    builder: (context, currentRow, _) =>
                        _buildCell(context, currentRow),
                  ),
          ),
        ),
      ),
    );
  }

  /// The frame the row reads its lane at, current whenever [_onTheCursor]
  /// builds.
  int get _frame => laneRowFrame(widget.frameCursor);

  /// [cell], built again on every frame the cursor moves to.
  Widget _onTheCursor(BuildContext context, WidgetBuilder cell) {
    final cursor = widget.frameCursor;
    if (cursor == null) {
      return cell(context);
    }
    return ValueListenableBuilder<int?>(
      valueListenable: cursor,
      builder: (context, _, _) => cell(context),
    );
  }

  Widget _buildCell(BuildContext context, TimelineRowAddress? currentRow) {
    final colorScheme = Theme.of(context).colorScheme;
    final plate = _plate(colorScheme, currentRow);
    return _standable(
      lane.isGroupHeader
          ? _headerCell(context, colorScheme, plate)
          : _memberCell(colorScheme, plate, currentRow),
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

  /// The cell's size, the same for a header and a member: the rail's row
  /// width (the sheet's column) and the row height. Horizontal: the section
  /// bracket occupies the leading gutter beside the rail, and lane labels
  /// indent past the twirl-down chevron slot.
  double get _cellWidth =>
      widget.width ??
      (widget.metrics.layerControlsWidth -
          widget.metrics.sectionLabelGutterWidth);
  double get _cellHeight => widget.height ?? widget.metrics.layerRowHeight;

  /// The cell's box, the same for a header and a member: the plate and its
  /// hairline, filling the size [build] gives the row. A lane row is a
  /// PLATE belonging to the layer above it, not one of the three chrome
  /// surfaces — the same reading its frame-side half takes.
  Widget _cellBox({
    required Color plate,
    required ColorScheme colorScheme,
    required EdgeInsets padding,
    Alignment? alignment,
    required Widget child,
  }) => Container(
    key: ValueKey<String>('$_keyPrefix-lane-label-${layer.id}-${lane.laneId}'),
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
    return [LayerSectionBandCell(), SizedBox(width: gap)];
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
          ?_groupGraph(),
          ..._headerTrailing(context, colorScheme),
        ],
      ),
    );
  }

  EdgeInsets get _headerPadding => widget.axis == Axis.horizontal
      ? const EdgeInsets.only(right: layerRailEndPadding)
      : const EdgeInsets.symmetric(horizontal: 2, vertical: 4);

  /// The TWIRL is the chevron's, not the whole header's (R10 #19's rail
  /// half). A header is a row you stand on and — next round — grab to
  /// reorder the chain; a label that toggles instead would have to be
  /// excluded from both, and that exclusion is exactly the kind of
  /// surface-local rule this rail keeps paying for.
  ///
  /// The app's one twirl, as small as the glyph it was — and a drag from it
  /// sweeps the group twirls down the rail, as the eye's does its column
  /// (F-475).
  Widget _groupTwirl() {
    final onToggleGroup = widget.onToggleLaneGroup;
    return RailSwipeColumnPointer(
      column: RailSwipeColumn.laneGroupToggle,
      child: LayerFoldTwirl(
        name: '$_keyPrefix-lane-group-toggle-${layer.id}-${lane.laneId}',
        axis: widget.axis,
        expanded: lane.groupExpanded,
        across: 16,
        onToggle: onToggleGroup == null
            ? null
            : () => onToggleGroup(layer, lane),
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
        clip: _groupReset(colorScheme),
        fx: _groupFx(context),
        optionalColumns: widget.optionalColumns,
        trailingRegion: _groupPreview(),
      );

  /// I-89 ③: the group's graph button — its lanes as one graph, in their
  /// own place, and back — at the end of the header's name, out of its room
  /// (I-89 Q1: 「이름공간을 줄여서 오른쪽정렬로」).
  Widget? _groupGraph() {
    final verbs = widget.laneGraphVerbs;
    final key = laneGraphHeadedBy(layer, lane);
    if (verbs == null || key == null) return null;
    return LaneGraphToggle(
      kind: LaneGraphToggleKind.graph,
      name: '$_keyPrefix-lane-group-graph-${layer.id}-${lane.laneId}',
      axis: widget.axis,
      on: widget.laneGraphs.open.containsKey(key),
      onToggle: () => verbs.toggle(key),
    );
  }

  /// R5: AE's group Reset, in the slot immediately left of fx — the one the
  /// clip toggle owns on layer rows, and the two never appear on
  /// the same row.
  Widget? _groupReset(ColorScheme colorScheme) {
    final onReset = widget.onResetLaneGroup;
    if (onReset == null) return null;
    return RailGlyphButton(
      name: '$_keyPrefix-lane-group-reset-${layer.id}-${lane.laneId}',
      tooltip: AppText.strings.tlResetGroup,
      size: AppIconButtonSize.micro,
      onPressed: () => onReset(layer, lane),
      glyph: RailIconGlyph(
        Icons.settings_backup_restore,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget? _groupFx(BuildContext context) {
    final enabled = lane.groupEnabled;
    if (enabled == null) return null;
    final onToggle = widget.onToggleLaneGroupEnabled;
    return RailSwipeColumnPointer(
      column: RailSwipeColumn.fx,
      child: RailGlyphButton(
        name: '$_keyPrefix-lane-group-fx-${layer.id}-${lane.laneId}',
        tooltip:
            (enabled
                    ? AppText.strings.tlBypassLaneTemplate
                    : AppText.strings.tlApplyLaneTemplate)
                .replaceAll('{name}', lane.label),
        onPressed: onToggle == null ? null : () => onToggle(layer, lane),
        size: AppIconButtonSize.bar,
        glyph: RailTextGlyph(
          'fx',
          style: fxGlyphStyle(context: context, active: enabled, fontSize: 11),
        ),
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
      alignment: centerEndAlong(widget.axis),
      child: SeNameTagLanePreview(
        key: ValueKey<String>(
          '$_keyPrefix-lane-group-preview-${layer.id}-${lane.laneId}',
        ),
        name: preview.name,
        // The dialogue SAMPLE follows the Show Dialogue member — the one
        // thing a fixed-string preview does track.
        line: _previewTag.showLine ? preview.line : '',
        tag: _previewTag,
        axis: widget.axis,
      ),
    );
  }

  // ── a member lane ─────────────────────────────────────────────────────

  Widget _memberCell(
    ColorScheme colorScheme,
    Color plate,
    TimelineRowAddress? currentRow,
  ) {
    if (widget.folded) {
      return _cellBox(
        plate: plate,
        colorScheme: colorScheme,
        padding: EdgeInsets.zero,
        child: const SizedBox.shrink(),
      );
    }
    final valueLabel = lane.valueLabel?.call(_frame);
    final seat = widget.seat;
    final drawn = seat == null
        ? null
        : laneGraphDrawnLanes(seat, currentRow).contains(lane.laneId);
    final ink = colorScheme.onSurfaceVariant;
    // A lane's name reads down its column on the sheet, through the shared
    // vertical-writing table ([readableText]). One its graph does not draw
    // reads OFF, in the app's one off language (the mock's 0.45, 5판).
    final label = readableText(
      widget.axis,
      lane.label,
      style: TextStyle(
        fontSize: 12,
        color: drawn == false
            ? ink.withValues(alpha: AppColors.offAlpha)
            : ink,
      ),
    );
    final content = widget.axis == Axis.horizontal
        ? _memberRow(colorScheme, label, valueLabel, drawn)
        : _memberColumn(colorScheme, label, valueLabel, drawn);
    // Right after the section band, not an indent past it (F-409, 유저
    // 2026-10-19: 「fx(변형이든 카메라든 뭐든)의 멤버, < 마름모 > 이름 이거,
    // 이거 다 왼쪽정렬로 왼쪽에 붙어있도록. 공간만들고싶은거임」). ↩️It stood
    // 24 in — one indent right of its group's header.
    final lead = _sectionLead(0);
    return _cellBox(
      plate: plate,
      colorScheme: colorScheme,
      padding: _memberPadding,
      // The rail's `centerLeft` transposed: the START of the main axis,
      // centered across it. The sheet centered on BOTH axes, which is what
      // made its lane names float in the middle of a column whose rail twin
      // begins at the leading edge.
      alignment: centerStartAlong(widget.axis),
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

  /// Along the cell only, never across it — on the sheet as on the rail.
  /// The sheet's column holds the rail's value row turned on its side, so
  /// it gives it the rail row's breadth: a settings bar's 24 between the
  /// cell's two hairlines, with nothing spent beside it. ↩️8 → 2 a side
  /// (R10 R6: a 28px column cannot spend 16 of it on side padding), and
  /// then 2 left the turned bar 23 and it ran over by one (2026-10-11).
  EdgeInsets get _memberPadding {
    if (widget.axis != Axis.horizontal) {
      return const EdgeInsets.symmetric(vertical: _laneColumnEndPadding);
    }
    return const EdgeInsets.only(right: _laneMemberEndPadding);
  }

  /// Along the rail: navigator, name, value. The NAME takes the leftover and
  /// ellipsises; the VALUE is a fixed column at the end (R5 #20). Two flex
  /// children of equal weight is what put the numbers at a different x on
  /// every row — each was right-aligned inside HALF of whatever its name
  /// left over, and names are not the same length.
  ///
  /// I-89 ③: on a rail that carries the header graphs, the curve's chips
  /// and the pin at the end of the name, before the value, each in a slot
  /// every lane keeps — so the name starts right after the key buttons and
  /// the chips and the pins stand in one column whichever lanes wear them
  /// (I-89-Q17, 유저 2026-10-12: 「키쪽에 기준점같은 이름 텍스트 딱 붙여서
  /// 공간만듬」). On both axes ([_memberColumn]).
  ///
  /// ↩️The chips stood before the name, between it and the key buttons,
  /// and the rail paid the two slots, 44 wider, from 2026-10-11 to 10-12: a
  /// row's own buttons come out of its name (I-89 Q1, 「이름공간을 줄여서
  /// 오른쪽정렬로 … 즉 레이어 이름행이 2개분 줄어드는거지」).
  Widget _memberRow(
    ColorScheme colorScheme,
    Widget label,
    String? valueLabel,
    bool? drawn,
  ) {
    final graphs = _drawsGraphs;
    return Row(
      children: [
        if (lane.showsKeyNavigator) ...[
          _navigator(colorScheme),
          const SizedBox(width: 6),
        ],
        Expanded(child: label),
        ?_valueLink(),
        if (graphs) ...[
          SizedBox(width: layerLaneChipsSlotWidth, child: _curveChips(drawn)),
          SizedBox(width: layerLanePinSlotWidth, child: _lanePin()),
        ],
        const SizedBox(width: _laneValueGap),
        SizedBox(
          // As wide as its boxes' widest number where the rail is shown: a
          // truncated coordinate is a WRONG coordinate. ↩️The readout shrank
          // into a fixed 80 instead.
          width: layerRailColumnWidthsIn(context).laneValue,
          // Reserved even with nothing to show, so the column survives the
          // rows that carry no readout (the Excel-grid rule the control
          // slots already follow).
          child: valueLabel == null
              ? null
              : _valueCell(valueLabel),
        ),
      ],
    );
  }

  /// THE CHAIN of a lane whose value is a linked pair — a layer's Scale
  /// ([ScaleChainButton], the one the transform tool wears). One press flips
  /// the switch the rail handed over. Always on the row that has one: what a
  /// press changes is its colour, never whether it is there.
  ///
  /// Null on every lane that is not [PropertyLaneRow.linkable], and on a
  /// rail that was handed no chain.
  Widget? _valueLink() {
    final link = widget.laneEdit?.valueLink;
    if (!lane.linkable || link == null) {
      return null;
    }
    return ListenableBuilder(
      listenable: link.changes,
      builder: (context, _) => ScaleChainButton(
        keyValue: '$_keyPrefix-lane-value-link-${layer.id}-${lane.laneId}',
        isOn: link.isOn(),
        onPressed: link.toggle,
      ),
    );
  }

  /// I-89 ③: the colours this lane's numbers are drawn in, while its
  /// group's graph [drawn] it — the graph's key, in the lane's own row
  /// (시안 5판). Nothing while it is not drawn, its slot kept.
  ///
  /// The corner is [AppShapes]' control family, which scales with its size:
  /// the mock's chip at 9px, where a container's absolute corner would
  /// have rounded it into a dot.
  Widget? _curveChips(bool? drawn) {
    final curve = lane.curve;
    if (drawn != true || curve == null) {
      return null;
    }
    return Flex(
      direction: widget.axis,
      children: [
        for (final (index, colour) in curve.parts.indexed) ...[
          if (index > 0) const SizedBox.square(dimension: _laneChipGap),
          DecoratedBox(
            key: ValueKey<String>(
              '$_keyPrefix-lane-chip-${layer.id}-${lane.laneId}-$index',
            ),
            decoration: ShapeDecoration(
              color: colour,
              shape: AppShapes.control(_laneChipSize),
            ),
            child: const SizedBox.square(dimension: _laneChipSize),
          ),
        ],
      ],
    );
  }

  /// Whether this rail draws header graphs at all (I-89 ③) — what keeps a
  /// member's chips and pin slots, whichever lanes wear them.
  bool get _drawsGraphs => widget.laneGraphVerbs != null;

  /// I-89 ③: the lane PINNED to every open graph, or let go — AE's graph
  /// editor set, the one way a lane reaches another group's graph. On a
  /// lane that draws a curve ([lanePinOf]).
  Widget? _lanePin() {
    final verbs = widget.laneGraphVerbs;
    final key = lanePinOf(layer, lane);
    if (verbs == null || key == null) {
      return null;
    }
    return LaneGraphToggle(
      kind: LaneGraphToggleKind.pin,
      name: '$_keyPrefix-lane-pin-${layer.id}-${lane.laneId}',
      axis: widget.axis,
      on: widget.laneGraphs.pinned.contains(key),
      onToggle: () => verbs.togglePin(key),
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
  ///
  /// THE VALUE IS THE RAIL'S VALUE COLUMN, TURNED: its row as the rail
  /// writes it, a quarter on its side, as Latin turns in vertical writing —
  /// the same length the rail gives it (유저 2026-10-11: 「진짜로
  /// 90도눕혀서 쓰는것처럼 하면 길이 다 타임라인이랑 똑같이 들어갈거같은데
  /// 그렇게하자. 약간 워드에서도 세로쓰기 있는데 뭐 검증된 방식이잖아」).
  /// The steps and the pencil turn with it, − reading as a bar: asked
  /// whether to stand them upright, the user kept them turned (유저
  /// 2026-10-11 「여쭐것 둘다 문제없음」).
  /// ↩️Stood up: two small boxes one under the other, each with its pencil
  /// under it, and no ± (2026-10-10).
  ///
  /// The name starts right under the key buttons, on one line across a
  /// group's columns (I-89-Q17, 유저 2026-10-12: 「x시트만 뒤죽박죽인데
  /// 일정하게 위쪽정렬되도록」): the chips stand at its end with the pin.
  /// ↩️Above it, they pushed it down in the columns long enough to pay them
  /// and not in the rest — a chained lane pays them later.
  Widget _memberColumn(
    ColorScheme colorScheme,
    Widget label,
    String? valueLabel,
    bool? drawn,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final link = valueLabel == null ? null : _valueLink();
        final shows = _stoodShows(
          constraints.maxHeight,
          hasValue: valueLabel != null,
          hasLink: link != null,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shows.navigator) ...[
              _navigator(colorScheme),
              const SizedBox(height: _laneStoodNavigatorGap),
            ],
            Expanded(child: label),
            if (shows.link)
              SizedBox(
                height: _laneValueLinkExtent,
                child: Center(child: link),
              ),
            if (shows.chips)
              SizedBox(
                height: layerLaneChipsSlotWidth,
                child: _curveChips(drawn),
              ),
            if (shows.pin)
              SizedBox(
                height: layerLanePinSlotWidth,
                child: Center(child: _lanePin()),
              ),
            if (shows.value && valueLabel != null) ...[
              const SizedBox(height: _laneValueGap),
              SizedBox(
                height: layerRailColumnWidthsIn(context).laneValue,
                child: RotatedBox(
                  quarterTurns: 1,
                  child: _valueCell(valueLabel),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// What a stood-up member column [extent] long shows: the NAME is paid
  /// first, then each control in turn, and what does not fit is shed.
  ///
  /// 🚨ONE LAW FOR EVERY CONTROL, written once: each is paid after every
  /// control before it that the LANE HAS — not after the ones this column
  /// is showing — so what a column grew to show stays as it grows on. The
  /// order is the gate's (2026-08-08): the value, the navigator, the
  /// chain, the pin, the chips.
  ///
  /// The chain is paid after the value and the navigator, once everything
  /// the column already showed has its room: it links the value, so it is
  /// never there without it, and no key button is shed to make it room.
  /// Asked of the navigator the LANE has, not of whether it is showing — or
  /// the chain would come and go and come again as the column grew.
  ///
  /// I-89 ③: the graph's pin and chips are paid after the chain, asked the
  /// same way — of what the lane HAS, the value it will show among it — so
  /// carrying them sheds nothing the column showed before they came.
  /// ↩️Asked of what was showing, the pin stood in a column too short for
  /// the value and went again as the column grew to take it — a window the
  /// turned value column, as long as the rail's value cell is wide, opened
  /// (2026-10-11).
  /// ↩️The navigator was the last one asked of the value SHOWING: it stood
  /// in a column too short for the value, made way when the value came and
  /// stood again further up (10-11 to 10-16, board:
  /// xsheet-stood-navigator-comes-and-goes). Each control spelled its own
  /// floor then, and the one that drifted is why they are one walk now.
  _StoodShows _stoodShows(
    double extent, {
    required bool hasValue,
    required bool hasLink,
  }) {
    var floor = _laneLabelFloor;
    bool paid(bool has, double slot) {
      final fits = has && extent >= floor + slot;
      if (has) {
        floor += slot;
      }
      return fits;
    }

    final value = paid(
      hasValue,
      _laneValueGap + layerRailColumnWidthsIn(context).laneValue,
    );
    final navigator = paid(
      lane.showsKeyNavigator,
      _laneStoodNavigatorGap + _laneNavigatorExtent,
    );
    final link = paid(hasValue && hasLink, _laneValueLinkExtent);
    final graphs = _drawsGraphs;
    final pin = paid(graphs, layerLanePinSlotWidth);
    final chips = paid(graphs, layerLaneChipsSlotWidth);
    return (
      value: value,
      navigator: navigator,
      link: link,
      pin: pin,
      chips: chips,
    );
  }
}

/// What a stood-up member column shows of its controls
/// ([_TimelineLaneControlsRowState._stoodShows]).
typedef _StoodShows = ({
  bool value,
  bool navigator,
  bool link,
  bool pin,
  bool chips,
});

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
        mouseCursor: AppCursors.press,
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
/// at keyed frames (AE-style: a half for each side of the key —
/// [paintKeyMark]). The markers are drawings; the band under them takes the
/// press ([TimelineLaneKeyMarker]).
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
  /// Null keeps the band display-only, for a host that hands no lane verbs.
  /// Every timeline and x-sheet lane has one, camera included since
  /// 2026-08-08, and every lane of the storyboard's rail since R5 ③b.
  /// ↩️It named the storyboard's lanes as the display-only ones.
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
  /// ([timelineRowGround]); the band is its gesture, the line between its
  /// keys and its markers.
  @override
  Widget build(BuildContext context) {
    return _withSpacers(
      Stack(
        clipBehavior: Clip.none,
        children: [?_gestureLayer(), ?_keysLine(), ..._liveMarkers()],
      ),
    );
  }

  double get _cellExtent => metrics.frameCellWidth;

  /// Cross-axis extent: rail-row height in the timeline, column width in
  /// the X-sheet (the transposed metrics carry both as layerRowHeight).
  double get _crossExtent => metrics.layerRowHeight;
  double get _visibleExtent => _edge(frameEndIndexExclusive);

  /// [frame]'s leading boundary along this band — the frame axis' one law
  /// ([timelineFrameEdge]), from the band's first frame.
  double _edge(int frame) =>
      timelineFrameEdge(frame, _cellExtent) -
      timelineFrameEdge(frameStartIndex, _cellExtent);

  /// ONE metric law for every marker on this axis — see
  /// [timelineLaneKeyMarkerSize] / [timelineLaneUnionKeyMarkerSize] — in
  /// [frame]'s cell as the axis lays it, between its two boundaries
  /// ([_edge]): the cell a camera row's key fills too ([timelineLaneKeySpan]
  /// reads its laid-out box). Build-time is correct HERE: the band rebuilds
  /// on zoom.
  ///
  /// ↩️It read the zoom ([_cellExtent]), which was the cell while every
  /// zoom was a whole pixel (D39, 08-18); since F-220 a cell is its zoom
  /// give or take a pixel, and the band's union and the camera row's stood
  /// a fraction of one apart (F-403 opens a cut at 19.2).
  Size _markerSizeAt(int frame) => timelineLaneKeyMarkerSizeOf(
    _crossExtent,
    frameCellExtent: _edge(frame + 1) - _edge(frame),
    heads: lane.isGroupHeader,
  );

  /// The mark's box grown by 4px each side, either way held to the row —
  /// the floor yields to the room, as a mark's does ([_markInCell]): a lane
  /// the enlarged graph folds is thinner than it (I-89 ③D).
  Size _hitSizeAt(int frame) {
    double grown(double side) => (side + 8)
        .clamp(math.min(14.0, _crossExtent), _crossExtent)
        .toDouble();
    final mark = _markerSizeAt(frame);
    return Size(grown(mark.width), grown(mark.height));
  }

  bool _inWindow(int frame) =>
      frame >= frameStartIndex && frame < frameEndIndexExclusive;

  /// The line between this lane's keys ([TimelineLaneKeysLine]) — the part
  /// of it the band's window holds, UNDER the markers.
  Widget? _keysLine() {
    final span = timelineKeysLineSpan(lane.keyedFrames);
    if (span == null ||
        span.last < frameStartIndex ||
        span.first >= frameEndIndexExclusive) {
      return null;
    }
    final from = math.max(span.first, frameStartIndex);
    final past = math.min(span.last + 1, frameEndIndexExclusive);
    return placedAlong(
      axis,
      along: _edge(from),
      across: 0,
      alongExtent: _edge(past) - _edge(from),
      acrossExtent: _crossExtent,
      child: TimelineLaneKeysLine(
        key: ValueKey<String>(
          '$keyPrefix-lane-keys-line-${layer.id}-${lane.laneId}',
        ),
        axis: axis,
        cells: past - from,
        layer: layer,
        startsAtKey: from == span.first,
        endsAtKey: past == span.last + 1,
        // The marks the band draws ([_keyMarkers]).
        rings: [
          for (final frame in timelineHollowKeyFrames(lane))
            if (_inWindow(frame)) (cell: frame - from, band: 1),
        ],
      ),
    );
  }

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
    final hit = _hitSizeAt(frame);
    return placedAlong(
      axis,
      along: (_edge(frame) + _edge(frame + 1)) / 2 - hit.width / 2,
      across: _crossExtent / 2 - hit.height / 2,
      alongExtent: hit.width,
      acrossExtent: hit.height,
      child: TimelineLaneKeyMarker(
        key: ValueKey<String>(
          '$keyPrefix-lane-key-${layer.id}-${lane.laneId}-$frame',
        ),
        mark: lane.keyMarkAt(frame),
        axis: axis,
        markerSize: _markerSizeAt(frame),
        layer: layer,
        selected: laneSelectionPicksKey(
          selection,
          layer.id,
          lane.laneId,
          frame,
        ),
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
    along: _edge(frame),
    across: 0,
    alongExtent: _edge(frame + 1) - _edge(frame),
    acrossExtent: _crossExtent,
    child: IgnorePointer(child: _LaneKeyName(text: text, layer: layer)),
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

/// A named key's label, centred in its cell — a block word whose block is
/// that one cell ([TimelineBlockText]), in a frame block name's type at
/// every zoom and on every row: it narrows into its cell instead (B, 유저
/// 2026-09-24).
///
/// ↩️Its type was a fixed 8px, sized to sit inside the mark (F-367 —
/// [timelineBlockNameFontSize]).
///
/// ↩️It was CLIPPED to the cell (「the first letters are what tell two names
/// apart」 — mine, 2026-08-11) and its type shrank with the zoom; the law
/// every block word keeps now narrows it instead, so the whole name stays.
///
/// 🪦`nameRoom` (the room before the next diamond) and `_laneKeyNameExtent`
/// (a 9px strip above the mark) went with the beside-the-diamond layout
/// they existed to serve — `F-17-Q1` 답 B.
class _LaneKeyName extends StatelessWidget {
  const _LaneKeyName({required this.text, required this.layer});

  final String text;

  /// The row whose key it names — its ink is the key's ([timelineRowLookOf]).
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return TimelineBlockText(
      text: text,
      // One cell: the word is centred on both axes whichever way the frame
      // axis runs.
      place: (
        axis: Axis.horizontal,
        cells: 1,
        cellIndex: 0,
        growth: TimelineBlockWordGrowth.towardBlockEnd,
        acrossAlignment: 0,
      ),
      // The frame block's own print — ink, size, weight and the box that
      // makes centring read as centred (유저 2026-09-12: 「내부에 있는 텍스트
      // 디자인? 색도 똑같이 그대로 재사용」).
      style: timelineBlockWordStyle(
        style,
        ink: timelineRowLookOf(context, layer).ink,
        fontSize: timelineBlockNameFontSize(style),
        bold: true,
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
/// 🗣️F-367 (유저 2026-10-16): 「fx등의 키가 너무 작은데 최대한 키우도록. 칸
/// 그냥 차지는 마름모라던가. 원도 칸 다 차지한다던가. 헤더는 그렇게하고
/// 멤버키는 작게하는 구분 좋으니 그거보다 좀 더 작게」 — the union FILLS its
/// cell ([timelineLaneUnionKeyMarkerSize]) and a member is the ㉗ step under
/// it. ↩️The member was the row's 0.32 (6–11px) and the union half again
/// that: 8.96 and 13.44px in a 24×28 cell.
///
/// D39 (2026-08-18): the law follows the ZOOM too — 「프레임블록
/// 텍스트/엣지처럼 줌에 따라 작아지게」 — and a mark that fills its cell
/// does it by being the cell. ↩️The row's share ran through
/// [timelineFittedGlyphFontSize] while the marks were sized off the row.
///
/// A box as the timeline lays it — its width along the frame axis, its
/// height across ([keyMarkPath]).
Size timelineLaneKeyMarkerSize(
  double crossExtent, {
  required double frameCellExtent,
}) => _markInCell(
  timelineLaneUnionKeyMarkerSize(
        crossExtent,
        frameCellExtent: frameCellExtent,
      ) /
      _unionStep,
  crossExtent: crossExtent,
  frameCellExtent: frameCellExtent,
);

/// The UNION mark's box — the whole of its cell (F-367): as high as the
/// row, and as wide as the cell where the cell is the narrower
/// (F-367-Q4) — never wider than it is high.
Size timelineLaneUnionKeyMarkerSize(
  double crossExtent, {
  required double frameCellExtent,
}) => Size(math.min(crossExtent, frameCellExtent), crossExtent);

/// How much bigger a union is than a member's key: half again (㉗).
const double _unionStep = 1.5;

/// The size of the key marks of a lane that [heads] a group or not: a
/// header's union ([timelineLaneUnionKeyMarkerSize]), a member's key
/// ([timelineLaneKeyMarkerSize]) — the band's one answer, wherever a lane's
/// keys are drawn ([TimelineLaneFrameRow], the storyboard's camera rows
/// through [timelineLaneKeySpan], the flip window's slots).
Size timelineLaneKeyMarkerSizeOf(
  double crossExtent, {
  required double frameCellExtent,
  required bool heads,
}) => heads
    ? timelineLaneUnionKeyMarkerSize(
        crossExtent,
        frameCellExtent: frameCellExtent,
      )
    : timelineLaneKeyMarkerSize(crossExtent, frameCellExtent: frameCellExtent);

/// 🚨F-367-Q4 (유저 2026-10-18 「세로 유지 · 가로만 줄임(프레임 블록처럼)」,
/// asked at 00:39 「내가 타임라인등 줌 줄이면 프레임블록등이랑 같은 규칙으로
/// 세로길이 최대한 유지한채 가로만 줄이라고 하지않았나?」) — **A KEY MARK
/// KEEPS ITS HEIGHT AND NARROWS WITH ITS CELL**, as a frame block's word
/// does: the row says how high it stands, the cell how wide.
///
/// ↩️🚨D39-2 (유저 스크린샷 3장, 2026-08-22) made it a SQUARE capped by the
/// tighter axis of its cell: 「1-일반상태, 2-**다이아몬드가 종횡비가
/// 이상해지기 시작**, 3-이상해짐. 크기가 종횡비 유지한채로 작아지는게아니라
/// **한 변만 작아지는** 느낌」. What those screenshots stepped through was one
/// `Container` rotated 45° (the halves came with I-89 ②): asked for more
/// than the cell is wide, the parent's constraint squeezed the WIDTH while
/// the height held — a rectangle, and a rotated rectangle is a lozenge, not
/// a diamond. The shapes are DRAWN in their box now ([keyMarkPath]), so a
/// narrowed diamond keeps a point on each of the box's four edges.
///
/// The rule is still said in ONE place rather than as a patch on whichever
/// caller showed it first: [TimelineLaneKeyMarker] asks for a box of an
/// explicit width AND height, and no mark outgrows its cell or its row.
/// (↩️Two sizes had escaped the glyph fit the member ran through: the fit's
/// own 4px floor, and the union's ×1.5 on top.)
///
/// ⚠️The floor yields to the room. A 3px cell gets a mark 3px wide, because
/// a mark that does not fit is not a smaller mark.
Size _markInCell(
  Size wanted, {
  required double crossExtent,
  required double frameCellExtent,
}) => Size(
  _heldIn(wanted.width, frameCellExtent),
  _heldIn(wanted.height, crossExtent),
);

/// [wanted] held inside [room], and above the floor while there is room
/// for it.
double _heldIn(double wanted, double room) {
  final floor = _keyMarkerFloor < room ? _keyMarkerFloor : room;
  return wanted.clamp(floor, room).toDouble();
}

/// The smallest a key mark may be drawn while it still has room — the same
/// floor [timelineFittedGlyphFontSize] holds every other mark to.
const double _keyMarkerFloor = 4.0;

/// A lane key's WORD for one frame — null when the lane names no key
/// there.
///
/// The band's print ([_LaneKeyName]), so the camera row says what every
/// other row says about a named key — [layer]'s.
Widget? _laneKeyWord(PropertyLaneRow lane, Layer layer, {required int frame}) {
  final name = lane.keyNames[frame];
  if (name == null) {
    return null;
  }
  return IgnorePointer(child: _LaneKeyName(text: name, layer: layer));
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
  required Axis axis,
}) {
  return [
    // UNDER the marks.
    ?_unionKeysLineSpan(
      keyPrefix: keyPrefix,
      layer: layer,
      lane: lane,
      axis: axis,
    ),
    for (final stretch in lane.stretchWords)
      timelineStretchWordSpan(
        keyPrefix: keyPrefix,
        layer: layer,
        stretch: stretch,
        axis: axis,
      ),
    for (final frame in lane.keyedFrames.toList()..sort())
      timelineLaneKeySpan(
        keyPrefix: keyPrefix,
        layer: layer,
        lane: lane,
        frame: frame,
        crossExtent: crossExtent,
        axis: axis,
      ),
  ];
}

/// ONE key of [lane] — its mark and its name — as the span it stands on:
/// the cell of the key at [frame], or the cell [at] where a row draws the
/// key somewhere other than its own frame (the storyboard's camera rows
/// draw each cut's keys at the cut's place on the track, I-73 ④).
///
/// [crossExtent] is the band the mark stands in, across — the row's whole
/// extent, or with [crossInset] the part of it from there (the camera row's
/// upper and lower lines over an O.L). The mark's size reads it, as it
/// reads the row's: one metric law ([timelineLaneKeyMarkerSizeOf] — a
/// header's union, or a member's key, as the band draws them).
///
/// [named] false leaves the key's name off — the camera row's two lines
/// have no room for it (the drawn proposal's 「키 이름은 한 줄일 때만」).
/// [selected] rings the mark, as the band rings a key its lane selection
/// holds.
///
/// ↩️`timelineUnionKeySpan` while the camera row's union was the one lane
/// drawn this way; the storyboard's camera LANES are drawn so too (I-73
/// ④ⓔ).
TimelineFrameSpan timelineLaneKeySpan({
  required String keyPrefix,
  required Layer layer,
  required PropertyLaneRow lane,
  required int frame,
  required double crossExtent,
  required Axis axis,
  int? at,
  double? crossInset,
  bool named = true,
  bool selected = false,
}) {
  final cell = at ?? frame;
  return TimelineFrameSpan(
    key: ValueKey<String>(
      '$keyPrefix-lane-key-span-${layer.id}-${lane.laneId}-$frame',
    ),
    // The FULL cell, resolved at layout time — the cells row keeps its memo
    // through zoom steps (R28 #4), so the marker size must not be baked at
    // build. The child reads the laid-out box and asks the SAME metric law
    // (D39); Center inside the marker puts the diamond on the cell centre
    // exactly as the carved-out box used to.
    placement: TimelineFrameSpanPlacement(
      startIndex: cell,
      endIndexExclusive: cell + 1,
      crossInset: crossInset ?? 0,
      crossExtent: crossInset == null ? null : crossExtent,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // The box along the frame axis is the cell's zoom-driven extent.
        final markerSize = timelineLaneKeyMarkerSizeOf(
          crossExtent,
          frameCellExtent: extentAlong(axis, constraints.biggest),
          heads: lane.isGroupHeader,
        );
        final marker = TimelineLaneKeyMarker(
          key: ValueKey<String>(
            '$keyPrefix-lane-key-${layer.id}-${lane.laneId}-$frame',
          ),
          mark: lane.keyMarkAt(frame),
          axis: axis,
          markerSize: markerSize,
          layer: layer,
          selected: selected,
        );
        // The NAME rides the same span — 🗣️유저 2026-09-12:
        // 「카메라레이어만 레이어에 인스턴스 이름이 표시안되」: this row drew
        // the mark and left the word to a band it does not have.
        final word = named ? _laneKeyWord(lane, layer, frame: frame) : null;
        return word == null
            ? marker
            : Stack(fit: StackFit.expand, children: [marker, word]);
      },
    ),
  );
}

/// One word over the line between two of a row's keys ([LaneStretchWord])
/// as the span it is laid out over — from the first key's cell through the
/// next key's, the box an instruction span's name stands in
/// ([TimelineSpanName]), so the word sits over the line's middle. A row
/// that draws its keys somewhere other than their own frames hands the
/// stretch over where it draws it (the storyboard's camera row, I-73 ④).
///
/// The word wears the row's key colour, as its keys' line does (유저
/// 2026-10-12: 「카메라 키 사이 PAN 표시되는거, 보이는데 너무 연해서
/// 있는지도몰랏어. 키 색(즉 색라벨 색)이랑 똑같이」) — ↩️it wore its term's
/// ink from the vocabulary, as a direction row's span does.
TimelineFrameSpan timelineStretchWordSpan({
  required String keyPrefix,
  required Layer layer,
  required LaneStretchWord stretch,
  required Axis axis,
}) => TimelineFrameSpan(
  key: ValueKey<String>(
    '$keyPrefix-lane-stretch-word-${layer.id}-${stretch.from}',
  ),
  placement: TimelineFrameSpanPlacement(
    startIndex: stretch.from,
    endIndexExclusive: stretch.to + 1,
  ),
  child: IgnorePointer(
    child: Builder(
      builder: (context) => TimelineSpanName(
        axis: axis,
        text: stretch.word,
        ink: timelineRowLookOf(context, layer).paper!,
      ),
    ),
  ),
);

/// The line between a union row's keys, as the span it is laid out over —
/// the band's own drawing ([TimelineLaneKeysLine]), from the first key's
/// cell through the last's — or null while the row has no two keys to join.
TimelineFrameSpan? _unionKeysLineSpan({
  required String keyPrefix,
  required Layer layer,
  required PropertyLaneRow lane,
  required Axis axis,
}) {
  final span = timelineKeysLineSpan(lane.keyedFrames);
  if (span == null) {
    return null;
  }
  return TimelineFrameSpan(
    key: ValueKey<String>(
      '$keyPrefix-lane-keys-line-span-${layer.id}-${lane.laneId}',
    ),
    placement: TimelineFrameSpanPlacement(
      startIndex: span.first,
      endIndexExclusive: span.last + 1,
    ),
    child: TimelineLaneKeysLine(
      key: ValueKey<String>(
        '$keyPrefix-lane-keys-line-${layer.id}-${lane.laneId}',
      ),
      axis: axis,
      cells: span.last - span.first + 1,
      layer: layer,
      rings: [
        for (final frame in timelineHollowKeyFrames(lane))
          (cell: frame - span.first, band: 1),
      ],
    ),
  );
}

/// The frames the line between a row's keys runs over — from its first key
/// to its last, both included — or null while it has no two keys to join.
({int first, int last})? timelineKeysLineSpan(Iterable<int> keyedFrames) {
  int? first;
  int? last;
  for (final frame in keyedFrames) {
    if (first == null || frame < first) {
      first = frame;
    }
    if (last == null || frame > last) {
      last = frame;
    }
  }
  return first == null || last == null || first == last
      ? null
      : (first: first, last: last);
}

/// The frames of [lane]'s keys whose marks are hollow ([keyMarkIsHollow]) —
/// where the line between its keys stops ([TimelineLaneKeysLine.rings]).
Iterable<int> timelineHollowKeyFrames(PropertyLaneRow lane) => [
  for (final MapEntry(key: frame, value: mark) in lane.keyMarks.entries)
    if (keyMarkIsHollow(mark)) frame,
];

/// THE LINE BETWEEN A ROW'S KEYS (I-73, 유저 2026-10-08). A DRAWING, and
/// nothing else — the band beneath it owns every pointer.
///
/// 「슬슬 키가 2개이상일땐 키 끼리 선으로 이어주는거? … 점선말고
/// 이어진선으로하자 … 그 선을 fx나 카메라나 동일하게 적용되는거 맞지? 아무튼
/// 키에도 적용. se 글로벌행도 타임라인패널에서 똑같이」 — and where it runs:
/// 「첫 키 앞은 비움. 근데 키 하나면 여전히 선 안넣고, 두개일때만 처음이랑
/// 마지막 사이에 선 그리도록하자. 즉 마지막 키 뒷부분은 선 안그림. se행이든
/// 트랜스폼이든 카메라든 전부 동일. 즉 사이만 존재하도록」.
///
/// So ONE line from the row's first key to its last ([timelineKeysLineSpan])
/// — every key between them stands on it — and none where a key is not on
/// both sides: before the first, after the last, beside a key alone. One
/// drawing for every key mark on the frame axis, as [TimelineLaneKeyMarker]
/// is: a member lane, a group header's union, the camera row's summary.
///
/// It fills the box of the [cells] it is laid over and strokes from the
/// middle of the first to the middle of the last, where the two marks
/// stand. A box that stops short of a key — a band's window does — has the
/// line run to that edge instead ([startsAtKey], [endsAtKey]).
///
/// It runs across the box at [crossFraction], and where a row draws its
/// keys at another height part of the way along — the storyboard's camera
/// row, whose cut moves to the upper or the lower line where it shares its
/// frames with a neighbour over an O.L (I-73 ④) — it STEPS there
/// ([steps]): 유저 2026-10-08, 「ol쪽 만나면 선을 뭔가 꺾어서 위로 향하게
/// 해서 직선 잇는다던가?」. A step is a slope across its cell edge, as wide
/// as half a cell and never wider than [timelineKeysLineBendReach] on
/// either side, so the line stays one line.
///
/// A HOLLOW mark — a union's ◉, where its members disagree
/// ([keyMarkIsHollow]) — is not run through: the line stops at the edge of
/// its box and goes on past it ([rings]), so its gap stays clear, as the
/// drawing the user picked has it (I-89 ②, option 나 — 유저 2026-10-10
/// 「2. 추천대로」, for the ○ it was then); a ring with the line through it
/// is another mark.
/// ⛔Every other mark stands ON the line, which shows wherever the mark
/// leaves it room — an hourglass's sides, a chevron's notch — as that
/// drawing has it too.
class TimelineLaneKeysLine extends StatelessWidget {
  const TimelineLaneKeysLine({
    super.key,
    required this.axis,
    required this.cells,
    required this.layer,
    this.startsAtKey = true,
    this.endsAtKey = true,
    this.crossFraction = 0.5,
    this.steps = const [],
    this.rings = const [],
  });

  final Axis axis;

  /// How many frame cells the box spans — the cell's extent is DERIVED from
  /// the box, so a zoom step lays this out again and rebuilds nothing.
  final int cells;

  /// The row whose keys it joins — drawn in its COLOUR LABEL as its key
  /// marks take it ([timelineRowLookOf]).
  final Layer layer;

  final bool startsAtKey;
  final bool endsAtKey;

  /// Where across the box the line starts: 0 at the leading side, 1 at the
  /// trailing — the middle, where a key mark stands, unless the row says.
  final double crossFraction;

  /// Where the line moves across, in box order: at the leading edge of the
  /// box's cell [TimelineKeysLineStep.edge] it goes to
  /// [TimelineKeysLineStep.to].
  final List<TimelineKeysLineStep> steps;

  /// The hollow marks standing on the line, where it stops and goes on
  /// past. A ring is a union's — only a union's members can disagree — so
  /// its box is a union mark's ([timelineLaneUnionKeyMarkerSize]).
  final List<TimelineKeysLineRing> rings;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _KeysLinePainter(
          this,
          color: timelineRowLookOf(context, layer).paper!,
        ),
      ),
    );
  }
}

/// One step of a [TimelineLaneKeysLine]: at the leading edge of the box's
/// cell [edge] — counted from the box's first cell — the line moves across
/// to [to] (0 the leading side, 1 the trailing).
typedef TimelineKeysLineStep = ({int edge, double to});

/// A hollow mark on a [TimelineLaneKeysLine]: the box's [cell] it stands
/// in, counted from the box's first, and how much of the box across the
/// [band] it stands in takes — all of it, but on the camera row's two
/// lines over an O.L. The two a mark's size reads.
typedef TimelineKeysLineRing = ({int cell, double band});

/// How far along the line a step's slope may reach on either side of its
/// edge, at most — half a cell when a cell is narrower than twice this.
const double timelineKeysLineBendReach = 6;

/// THE COURSE [line] strokes through, in a box [along] long and [across]
/// wide: from the middle of the first of its cells (or the box's edge,
/// where it does not start at a key) to the middle of the last (or the far
/// edge), at its cross fraction, and at each of its steps a slope from
/// where it was to where the step sends it — reaching half a cell either
/// side of the step's edge, never more than [timelineKeysLineBendReach],
/// never past the line's own ends. Empty where the box holds no line.
///
/// ★What the painter draws and what a pin reads are this one answer.
List<({double along, double across})> timelineKeysLineCourse(
  TimelineLaneKeysLine line, {
  required double along,
  required double across,
}) {
  final cell = _cellAlong(line, along);
  final from = line.startsAtKey ? cell / 2 : 0.0;
  final to = line.endsAtKey ? along - cell / 2 : along;
  if (to <= from) {
    return const [];
  }
  final reach = math.min(cell / 2, timelineKeysLineBendReach);
  double held(double value) => value.clamp(from, to).toDouble();
  var at = across * line.crossFraction;
  final course = [(along: from, across: at)];
  for (final step in line.steps) {
    final edge = step.edge * cell;
    final next = across * step.to;
    course
      ..add((along: held(edge - reach), across: at))
      ..add((along: held(edge + reach), across: next));
    at = next;
  }
  course.add((along: to, across: at));
  return course;
}

/// How long one of [line]'s cells is, in a box [along] long.
double _cellAlong(TimelineLaneKeysLine line, double along) =>
    line.cells < 1 ? 0.0 : along / line.cells;

/// Where [line] stops for its [TimelineLaneKeysLine.rings], in a box
/// [along] long and [across] wide: each ring's box along the line —
/// centred in its cell, as every mark is, and as long as a union mark in
/// its band is wide.
///
/// ★What the painter keeps the line out of and what a pin reads are this
/// one answer.
List<({double from, double to})> timelineKeysLineGaps(
  TimelineLaneKeysLine line, {
  required double along,
  required double across,
}) {
  final cell = _cellAlong(line, along);
  ({double from, double to}) gapAt(TimelineKeysLineRing ring) {
    final middle = (ring.cell + 0.5) * cell;
    final wide = timelineLaneUnionKeyMarkerSize(
      across * ring.band,
      frameCellExtent: cell,
    ).width;
    return (from: middle - wide / 2, to: middle + wide / 2);
  }

  return [for (final ring in line.rings) gapAt(ring)];
}

/// [stroke]s the line between a row's keys kept out of [hollows] — the
/// boxes of the hollow marks standing on it ([keyMarkIsHollow]) — so each
/// ring stays empty ([TimelineLaneKeysLine]). Every painter of the line
/// strokes through here: the panels' and the flip window's.
void strokeKeysLineClearOf(
  Canvas canvas,
  List<Rect> hollows,
  void Function() stroke,
) {
  if (hollows.isEmpty) {
    stroke();
    return;
  }
  canvas.save();
  for (final box in hollows) {
    canvas.clipRect(box, clipOp: ClipOp.difference);
  }
  stroke();
  canvas.restore();
}

class _KeysLinePainter extends CustomPainter with RepaintOnProps {
  _KeysLinePainter(this.line, {required this.color});

  final TimelineLaneKeysLine line;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = line.axis;
    final along = extentAlong(axis, size);
    final across = extentAcross(axis, size);
    final course = timelineKeysLineCourse(line, along: along, across: across);
    if (course.length < 2) {
      return;
    }
    final points = [
      for (final point in course)
        offsetAlong(axis, along: point.along, across: point.across),
    ];
    final paint = Paint()
      ..color = color
      ..strokeWidth = timelineJoiningLineWidth;
    strokeKeysLineClearOf(
      canvas,
      [
        // The whole box across: a ring on the camera row's upper line or
        // its lower one is kept clear of where the line steps to it.
        for (final gap in timelineKeysLineGaps(
          line,
          along: along,
          across: across,
        ))
          Rect.fromPoints(
            offsetAlong(axis, along: gap.from, across: 0),
            offsetAlong(axis, along: gap.to, across: across),
          ),
      ],
      () => _stroke(canvas, points, paint),
    );
  }

  /// [points] stroked as one line: a straight one where there are two, a
  /// path where it steps.
  static void _stroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length == 2) {
      canvas.drawLine(points.first, points.last, paint);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  @override
  Object get props => (
    line.axis,
    line.cells,
    color,
    line.startsAtKey,
    line.endsAtKey,
    line.crossFraction,
    ByList(line.steps),
    ByList(line.rings),
  );
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
/// [IgnorePointer] is load-bearing, not tidiness: a painted mark answers hit
/// tests anywhere inside its box, so a drawn key is a hit target in its own
/// right and the Stack would stop at it with the band never seeing the
/// pointer.
///
/// PUBLIC since B4 (2026-08-17): the camera row's union summary mounts this
/// same drawing — one mark law ([paintKeyMark]) for every key mark on the
/// frame axis.
class TimelineLaneKeyMarker extends StatelessWidget {
  const TimelineLaneKeyMarker({
    super.key,
    required this.mark,
    required this.axis,
    required this.markerSize,
    required this.layer,
    this.selected = false,
  });

  /// 🚨F-17: what the key IS — its two sides' kinds, or a union's
  /// disagreement — resolved once ([PropertyLaneRow.keyMarkAt]), never flags
  /// a caller could combine into a key no lane has.
  final KeyMark mark;

  /// The frame axis the mark stands on — the X-sheet's stands it up, the
  /// half arriving at the key toward the frames before it ([paintKeyMark]).
  final Axis axis;

  /// The mark's box as the timeline lays it — its width along the frame
  /// axis, its height across ([timelineLaneKeyMarkerSizeOf]).
  final Size markerSize;

  /// The row whose key it is: the mark wears its COLOUR LABEL, exactly as
  /// its frame blocks take it (유저 2026-09-12: 「유니언 키 색은
  /// 프레임블록이랑 마찬가지로 색라벨 그대로. 로직 그대로 재사용해서」) —
  /// [layerMarkColor] answers an unmarked row with the same paper the blocks
  /// use, so nothing changes for one — and as its blocks show it, switched
  /// off with its eye ([timelineRowLookOf], I-129).
  final Layer layer;

  /// Inside the live lane selection (UI-R23 #4): the marker rings in the
  /// accent so selected keys — union diamonds included — read at a glance,
  /// and so it is visible which keys the next drag will carry.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: CustomPaint(
          size: axis == Axis.vertical ? markerSize.flipped : markerSize,
          painter: _KeyMarkPainter(
            mark: mark,
            standing: axis == Axis.vertical,
            // EVERY key mark fills like the frame blocks (UI-R24 #9 — union
            // headers, member lanes, camera lanes alike), which since
            // 2026-09-12 means the row's COLOUR LABEL: 「유니언 키 색은
            // 프레임블록이랑 마찬가지로 색라벨 그대로. 로직 그대로
            // 재사용해서」.
            color: timelineRowLookOf(context, layer).paper!,
            // ⛔NO outline of its own (유저 2026-09-12: 「지금 실루엣에 외곽선
            // 회색 존재하는거같은데 삭제. 그냥 심플하게 바탕색만 남겨서」). The
            // one ring left is the SELECTION's, in ACCENT 1 (UI-R23 #4) —
            // colour alone, the selection rule.
            ring: selected ? selectedLaneKeyRing : null,
          ),
        ),
      ),
    );
  }
}

class _KeyMarkPainter extends CustomPainter with RepaintOnProps {
  const _KeyMarkPainter({
    required this.mark,
    required this.standing,
    required this.color,
    required this.ring,
  });

  final KeyMark mark;
  final bool standing;
  final Color color;
  final ({Color color, double width})? ring;

  @override
  void paint(Canvas canvas, Size size) => paintKeyMark(
    canvas,
    mark,
    center: size.center(Offset.zero),
    box: standing ? size.flipped : size,
    standing: standing,
    color: color,
    ring: ring,
  );

  @override
  Object get props => (mark, standing, color, ring);
}
