import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../input/app_input_settings.dart' show AppInput;
import '../input/eager_pan_gesture_recognizer.dart';

import '../../models/layer.dart';
import '../../models/timeline_frame_range.dart' show TimelineLaneSelection;
import '../../models/timeline_row_address.dart';
import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart' show AppColors;
import 'layer_label_controls.dart'
    show LayerSectionBandCell, fxGlyph, railSelectedRowColor;
import 'timeline_current_row.dart';
import 'layer_rail_columns.dart' show layerRailTwirlIcon;
import 'property_lane_model.dart';
import 'transform_lane_policy.dart' show laneSelectionCoversBandRow;
import 'timeline_cell_style.dart' show timelineDrawingStartColor;
import 'timeline_frame_range_gesture.dart'
    show TimelineLaneRangeCallbacks, TimelineLaneRangeGestureLayer;
import 'timeline_grid_metrics.dart';

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
    this.axis = Axis.horizontal,
    this.keyPrefix = 'timeline',
    this.width,
    this.height,
    this.minContentExtent,
    this.leadingInset = 0,
    this.currentRowHooks,
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

  /// The owning grid's frame-axis direction (drives only the cell's
  /// composition; every control behaves identically).
  final Axis axis;

  /// Key namespace ('timeline' | 'xsheet') so tests address one
  /// orientation.
  final String keyPrefix;

  /// Explicit cell size; defaults to the horizontal rail-row geometry.
  final double? width;
  final double? height;

  /// What the stood-up contents need along the cell's own axis even when
  /// [height] is less — the cell then CLIPS rather than overflowing, the
  /// same degradation the x-sheet's layer header takes (R10 R6).
  final double? minContentExtent;

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
  late final TextEditingController _valueController = TextEditingController();

  Layer get layer => widget.layer;
  PropertyLaneRow get lane => widget.lane;
  String get _keyPrefix => widget.keyPrefix;

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
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
    _valueController.text = currentValue;
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
    final input = _valueController.text;
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
    return lines.isEmpty ? [label] : lines;
  }

  /// AE's blue value column: the property's value at the playhead; tap to
  /// type (Enter commits and keys the value there), drag to scrub.
  Widget _valueCell(ColorScheme colorScheme, String valueLabel) {
    final laneEdit = widget.laneEdit;
    if (_editingValue) {
      return SizedBox(
        height: 20,
        child: TextField(
          key: ValueKey<String>(
            '$_keyPrefix-lane-value-field-${layer.id}-${lane.laneId}',
          ),
          controller: _valueController,
          autofocus: true,
          style: const TextStyle(fontSize: 11),
          textAlign: widget.axis == Axis.horizontal
              ? TextAlign.right
              : TextAlign.center,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _commitValueEdit(),
          onTapOutside: (_) {
            // Tap-away cancels (Enter commits, AE-style).
            setState(() => _editingValue = false);
          },
        ),
      );
    }

    // Tap types a value; a drag SCRUBS it (AE-style — horizontal for the
    // first component, vertical for Position's y; the drag-axis mapping is
    // the lane's, identical in both orientations) and commits once on
    // release. EAGER slop + the input device policy (UI-R22F #2): a slow
    // scrub must never lose the arena to the grid scroll, and touch
    // follows the timeline policy like every other edit gesture.
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
                    recognizer.supportedDevices =
                        AppInput.timelineEditPanDevices;
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
    if (hooks == null) {
      return _buildCell(context, null);
    }
    return ValueListenableBuilder<TimelineRowAddress?>(
      valueListenable: hooks.currentRow,
      builder: (context, currentRow, _) => _buildCell(context, currentRow),
    );
  }

  Widget _buildCell(BuildContext context, TimelineRowAddress? currentRow) {
    final colorScheme = Theme.of(context).colorScheme;
    // The lane's PLATE: the shared "you are standing here" wash while this
    // row is the verbs' subject — or while you are standing INSIDE the
    // group it leads, so the rail reads as the chain it is (layer ▸ Blur ▸
    // Radius all lit, user 2026-08-07).
    final lit =
        currentRowIsLane(currentRow, layer.id, lane.laneId) ||
        (lane.isGroupHeader &&
            currentRowIsInsideGroup(currentRow, layer.id, lane.laneId));
    final plate = lit ? railSelectedRowColor(colorScheme) : AppColors.washDown;
    if (lane.isGroupHeader) {
      // AE group header ('Transform', an effect): a structural label one
      // indent LEFT of its member lanes, no navigator/value. The chevron
      // twirls the group open/closed (default collapsed); pressing the
      // header itself stands on it.
      final onToggleGroup = widget.onToggleLaneGroup;
      final headerCell = Container(
        key: ValueKey<String>(
          '$_keyPrefix-lane-label-${layer.id}-${lane.laneId}',
        ),
        width:
            widget.width ??
            (widget.metrics.layerControlsWidth -
                widget.metrics.sectionLabelGutterWidth),
        height: widget.height ?? widget.metrics.layerRowHeight,
        decoration: BoxDecoration(
          // A lane row is a PLATE belonging to the layer above it, not one of
          // the three chrome surfaces — the same reading its frame-side half
          // already takes.
          color: plate,
          border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
        ),
        // The TWIRL is the chevron's, not the whole header's (R10 #19's
        // rail half). A header is a row you stand on and — next round —
        // grab to reorder the chain; a label that toggles instead would
        // have to be excluded from both, and that exclusion is exactly the
        // kind of surface-local rule this rail keeps paying for.
        child: Padding(
          padding: widget.axis == Axis.horizontal
              ? const EdgeInsets.only(right: 8)
              : const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          // R10 R6: stood up on the sheet, like every other header.
          child: Flex(
            direction: widget.axis,
            // START on BOTH axes (user, 2026-08-08): the sheet's headers
            // used to center their contents while the rail's began at the
            // leading edge, so the twirl and the name sat at a different
            // place on each surface for no reason either of them has.
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (widget.axis == Axis.horizontal &&
                  widget.leadingInset > 0) ...[
                // The rows' section band continues through lane rows
                // (UI-R6 #5).
                const LayerSectionBandCell(),
                const SizedBox(width: 10),
              ],
              InkWell(
                key: ValueKey<String>(
                  '$_keyPrefix-lane-group-toggle-${layer.id}-${lane.laneId}',
                ),
                onTap: onToggleGroup == null
                    ? null
                    : () => onToggleGroup(layer, lane),
                customBorder: const CircleBorder(), // R26 #28
                child: Icon(
                  layerRailTwirlIcon(expanded: lane.groupExpanded),
                  size: 16,
                ),
              ),
              Flexible(
                child: widget.axis == Axis.horizontal
                    ? Text(
                        lane.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      )
                    : VerticalWritingText(
                        text: lane.label,
                        // 'Transform', 'Gaussian Blur' — property names a
                        // person reads, so they stand up (user, 2026-08-08).
                        latinForm: VerticalLatinForm.upright,
                        mainAlignment: 0,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
              ),
              // R6: the group's own switch, for the headers that have one
              // (each effect). The shared `fx` glyph, so restyling fx
              // still happens in exactly one place.
              if (lane.groupEnabled != null) ...[
                // Along the ROW's axis: a width-only box contributes
                // nothing to a vertical Flex, so on the sheet the switch
                // sat flush against the label.
                SizedBox(
                  width: widget.axis == Axis.horizontal ? 4 : null,
                  height: widget.axis == Axis.horizontal ? null : 4,
                ),
                IconButton(
                  key: ValueKey<String>(
                    '$_keyPrefix-lane-group-fx-${layer.id}-${lane.laneId}',
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 22,
                    minHeight: 22,
                  ),
                  iconSize: 16,
                  tooltip: lane.groupEnabled!
                      ? 'Bypass ${lane.label}'
                      : 'Apply ${lane.label}',
                  onPressed: widget.onToggleLaneGroupEnabled == null
                      ? null
                      : () => widget.onToggleLaneGroupEnabled!(layer, lane),
                  icon: fxGlyph(
                    context: context,
                    active: lane.groupEnabled!,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      return _standable(headerCell);
    }
    final valueLabel = lane.valueLabel?.call(widget.currentFrameIndex);
    final labelStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurfaceVariant,
    );
    // A lane's name reads down its column on the sheet, through the shared
    // vertical-writing table — 'Position' will not fit across 28px, and
    // ellipsis would have left one glyph and a dot. The letters STAND UP
    // in it (user, 2026-08-08) and the column starts at the column's top,
    // which is the rail's `centerLeft` transposed.
    final label = widget.axis == Axis.horizontal
        ? Text(lane.label, overflow: TextOverflow.ellipsis, style: labelStyle)
        : VerticalWritingText(
            text: lane.label,
            latinForm: VerticalLatinForm.upright,
            mainAlignment: 0,
            style: labelStyle,
          );

    final Widget content;
    if (widget.axis == Axis.horizontal) {
      content = Row(
        children: [
          if (lane.showsKeyNavigator) ...[
            _navigator(colorScheme),
            const SizedBox(width: 6),
          ],
          Flexible(child: label),
          const SizedBox(width: 4),
          if (valueLabel != null)
            Expanded(
              child: _editingValue
                  ? _valueCell(colorScheme, valueLabel)
                  : Align(
                      alignment: Alignment.centerRight,
                      child: _valueCell(colorScheme, valueLabel),
                    ),
            )
          else
            const Spacer(),
        ],
      );
    } else {
      // X-sheet lane column header: the same controls stacked vertically,
      // and the same rule the LAYER heading beside it follows — the NAME is
      // what a heading is for, so it is paid first and the controls shed.
      //
      // R10 R6: without that, the label was simply `Expanded` over whatever
      // the navigator and the value left, and at the default dock height
      // 'Position' packed into 35px — 2.6px per glyph, against the layer
      // heading's guaranteed 48 one column to its left.
      content = LayoutBuilder(
        builder: (context, constraints) {
          final extent = constraints.maxHeight;
          // Value first (it is a readout, and the same number is on the
          // timeline rail), then the navigator (whose diamond is also on
          // the frame axis).
          // The gaps count too: without them the label's floor was 4px
          // short of what the gate promised at every rung, and nothing
          // noticed while the label could still pack.
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
          // THE RAIL ROW'S ORDER, TRANSPOSED (user, 2026-08-08): navigator,
          // then the name, then the value at the far end. The sheet used to
          // lead with the name and put the navigator after it, so the same
          // three controls read in two different orders depending on which
          // way the panel was turned.
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
                // A fixed slot, so a long readout ellipsises inside it
                // instead of pushing the heading out of its own column.
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

    final memberCell = Container(
      key: ValueKey<String>(
        '$_keyPrefix-lane-label-${layer.id}-${lane.laneId}',
      ),
      // Horizontal: the section bracket occupies the leading gutter beside
      // the rail, and lane labels indent past the twirl-down chevron slot.
      width:
          widget.width ??
          (widget.metrics.layerControlsWidth -
              widget.metrics.sectionLabelGutterWidth),
      height: widget.height ?? widget.metrics.layerRowHeight,
      padding: widget.axis == Axis.horizontal
          ? (widget.leadingInset > 0
                ? const EdgeInsets.only(right: 8)
                : const EdgeInsets.only(left: 24, right: 8))
          // 8 → 2: a 28px column cannot spend 16 of it on side padding.
          : const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      decoration: BoxDecoration(
        color: plate,
        border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
      ),
      // The rail's `centerLeft` transposed: the START of the main axis,
      // centered across it. The sheet centered on BOTH axes, which is what
      // made its lane names float in the middle of a column whose rail
      // twin begins at the leading edge.
      alignment: widget.axis == Axis.horizontal
          ? Alignment.centerLeft
          : Alignment.topCenter,
      child: widget.axis == Axis.horizontal && widget.leadingInset > 0
          ? Row(
              children: [
                // The rows' section band continues through lane rows
                // (UI-R6 #5); the 24px lane indent follows it.
                const LayerSectionBandCell(),
                const SizedBox(width: 24),
                Expanded(child: content),
              ],
            )
          : _clipToContent(content),
    );
    return _standable(memberCell);
  }

  /// Below the host's stated content extent the cell SCALES instead of
  /// striping — the x-sheet's layer header takes the same degradation, and
  /// a lane column that overflowed while its neighbour shrank would be the
  /// only yellow stripe on the panel.
  Widget _clipToContent(Widget child) {
    final extent = widget.minContentExtent;
    final height = widget.height;
    if (extent == null || height == null || height >= extent || extent <= 0) {
      return child;
    }
    // The OverflowBox hands the child its full extent; `Transform` paints
    // differently but passes the same constraints down.
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: extent,
        maxHeight: extent,
        child: Transform.scale(
          scale: height / extent,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
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
    return InkWell(
      key: buttonKey,
      onTap: enabled ? onTap : null,
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
    this.laneEdit,
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

  /// Reaches the key markers for ONE thing: re-timing a key on a lane that
  /// has no [laneRange] to do it through. See [_LaneKeyMarker.onMoveBy].
  final PropertyLaneEditCallbacks? laneEdit;

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
  /// Null keeps the band display-only (storyboard lanes) or leaves the
  /// markers as the only subject (camera lanes, whose atomic keyframes
  /// have no per-lane span to select).
  final TimelineLaneRangeCallbacks? laneRange;

  /// Frame-axis direction; only the band's composition transposes.
  final Axis axis;

  /// Key namespace ('timeline' | 'xsheet').
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cellExtent = metrics.frameCellWidth;
    // Cross-axis extent: rail-row height in the timeline, column width in
    // the X-sheet (the transposed metrics carry both as layerRowHeight).
    final crossExtent = metrics.layerRowHeight;
    final visibleExtent =
        (frameEndIndexExclusive - frameStartIndex) * cellExtent;
    final markerSize = (crossExtent * 0.32).clamp(6.0, 11.0).toDouble();
    final hitSize = (markerSize + 8).clamp(14.0, crossExtent).toDouble();
    final horizontal = axis == Axis.horizontal;

    // R26 #3: the header row washes when the selection spans its WHOLE
    // member group — the SAME predicate the gesture uses to decide
    // move-vs-select, so what looks selected is what a drag grabs.
    bool selectionCoversRow(TimelineLaneSelection? selection) =>
        laneSelectionCoversBandRow(selection, layer.id, lane.laneId);

    List<Widget> markerChildren(TimelineLaneSelection? selection) => [
      // R27 #14: the selection BAND is no longer painted here. It rides
      // the cursor overlay with the cell selection's exact geometry and
      // decoration, so a key span and a cell span read as one language.
      // (The band is above the markers there; the key RING below still
      // marks which keys are in the span.)
      for (final frame in lane.keyedFrames)
        if (frame >= frameStartIndex && frame < frameEndIndexExclusive)
          Positioned(
            left: horizontal
                ? (frame - frameStartIndex) * cellExtent +
                      cellExtent / 2 -
                      hitSize / 2
                : crossExtent / 2 - hitSize / 2,
            top: horizontal
                ? crossExtent / 2 - hitSize / 2
                : (frame - frameStartIndex) * cellExtent +
                      cellExtent / 2 -
                      hitSize / 2,
            width: hitSize,
            height: hitSize,
            child: _LaneKeyMarker(
              key: ValueKey<String>(
                '$keyPrefix-lane-key-${layer.id}-${lane.laneId}-$frame',
              ),
              hold: lane.holdOutFrames.contains(frame),
              markerSize: markerSize,
              frameCellExtent: cellExtent,
              axis: axis,
              // Selected markers ring in ACCENT 1 (UI-R23 #3/#4): the
              // LANE selection owns the ring now — frame selection is a
              // separate domain and never rings lane keys. Header union
              // diamonds ring on a whole-group selection (R26 #3).
              selected:
                  selection != null &&
                  selectionCoversRow(selection) &&
                  selection.contains(frame),
              // The band's select-then-move is the rule EVERYWHERE the band
              // exists (user, 2026-08-08). It does not exist on a camera
              // lane — atomic keyframes have no per-lane span to select —
              // and there this marker is the only subject a re-time could
              // have, so it keeps a drag. A group header's union diamond
              // never does: it has no single lane to write to.
              onMoveBy: laneRange != null || lane.isGroupHeader
                  ? null
                  : (delta) => laneEdit?.onMoveKey(
                      layer,
                      lane,
                      frame,
                      frame + delta,
                    ),
            ),
          ),
    ];

    final selectionListenable = laneRange?.selection;
    final band = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.washDown.withValues(alpha: 0.6),
        // The divider faces the NEXT lane: below in the timeline, to the
        // right in the X-sheet.
        border: horizontal
            ? Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 0.5,
                ),
              )
            : Border(
                right: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The band-wide LANE gesture (UI-R23 #3 part 2), UNDER the
          // markers: pans on the band select THIS lane; marker drags keep
          // their arena priority above. The GROUP HEADER band selects too
          // (R26 #3): its anchor spans the WHOLE member group — the
          // "모두에 적용되는 그 행", collapsed state included.
          if (laneRange != null)
            TimelineLaneRangeGestureLayer(
              key: ValueKey<String>(
                '$keyPrefix-lane-range-gesture-${layer.id}-${lane.laneId}',
              ),
              layer: layer,
              laneId: lane.laneId,
              frameStartIndex: frameStartIndex,
              leadingFrameSpacerWidth: 0,
              frameCellExtent: cellExtent,
              crossAxisExtent: crossExtent,
              callbacks: laneRange!,
              axis: axis,
            ),
          // Markers follow the LIVE lane selection (value-only — no row
          // rebuild) so the accent-1 rings track drags per step.
          if (selectionListenable == null)
            ...markerChildren(null)
          else
            ValueListenableBuilder(
              valueListenable: selectionListenable,
              builder: (context, selection, _) => Stack(
                clipBehavior: Clip.none,
                children: markerChildren(selection),
              ),
            ),
        ],
      ),
    );

    if (horizontal) {
      return Row(
        key: ValueKey<String>('$keyPrefix-lane-row-${layer.id}-${lane.laneId}'),
        children: [
          SizedBox(width: leadingFrameSpacerWidth, height: crossExtent),
          SizedBox(width: visibleExtent, height: crossExtent, child: band),
          SizedBox(width: trailingFrameSpacerWidth, height: crossExtent),
        ],
      );
    }
    return Column(
      key: ValueKey<String>('$keyPrefix-lane-row-${layer.id}-${lane.laneId}'),
      children: [
        SizedBox(width: crossExtent, height: leadingFrameSpacerWidth),
        SizedBox(width: crossExtent, height: visibleExtent, child: band),
        SizedBox(width: crossExtent, height: trailingFrameSpacerWidth),
      ],
    );
  }
}

/// One key marker. A DRAWING, and nothing else.
///
/// One key marker — a DRAWING, unless it is the only subject there is.
///
/// It used to own a drag that moved its own key the instant you pulled it,
/// which is not how anything else on this axis behaves: a frame block is
/// SELECTED first and the next drag moves the selection. The band beneath
/// has implemented exactly that rule the whole time — press outside the
/// selection to select, press inside it to move — so the fix was to stop
/// competing with it (user, 2026-08-08).
///
/// [onMoveBy] is the ONE exception, and the parent decides it: a CAMERA
/// lane has no selection domain (its keyframes are atomic — one key holds
/// every property, so a per-lane span would be a lie) and therefore no
/// band gesture either. There, this marker is the only subject a re-time
/// could have, and taking its drag away would leave a camera key nothing
/// can move. Null everywhere else, which is everywhere the band exists.
class _LaneKeyMarker extends StatefulWidget {
  const _LaneKeyMarker({
    super.key,
    required this.hold,
    required this.markerSize,
    required this.frameCellExtent,
    required this.axis,
    this.onMoveBy,
    this.selected = false,
  });

  final bool hold;
  final double markerSize;
  final double frameCellExtent;
  final Axis axis;

  /// Commits a frame-snapped re-time of this key. Null makes the marker
  /// pointer-transparent, so the band beneath answers everything.
  final ValueChanged<int>? onMoveBy;

  /// Inside the live lane selection (UI-R23 #4): the marker rings in the
  /// accent so selected keys — union diamonds included — read at a glance,
  /// and so it is visible which keys the next drag will carry.
  final bool selected;

  @override
  State<_LaneKeyMarker> createState() => _LaneKeyMarkerState();
}

class _LaneKeyMarkerState extends State<_LaneKeyMarker> {
  double _dragDelta = 0;
  bool _dragging = false;

  int get _frameDelta => (_dragDelta / widget.frameCellExtent).round();

  void _startDrag() => setState(() => _dragging = true);

  void _updateDrag(DragUpdateDetails details) {
    setState(() {
      _dragDelta += widget.axis == Axis.horizontal
          ? details.delta.dx
          : details.delta.dy;
    });
  }

  void _endDrag() {
    final delta = _frameDelta;
    setState(() {
      _dragging = false;
      _dragDelta = 0;
    });
    if (delta != 0) {
      widget.onMoveBy?.call(delta);
    }
  }

  void _cancelDrag() {
    setState(() {
      _dragging = false;
      _dragDelta = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final horizontal = widget.axis == Axis.horizontal;
    // EVERY key diamond fills WHITE like the frame blocks (UI-R24 #9 —
    // union headers, member lanes, camera lanes alike); selection speaks
    // through the accent silhouette alone.
    final shape = Container(
      width: widget.markerSize,
      height: widget.markerSize,
      decoration: BoxDecoration(
        color: _dragging
            ? timelineDrawingStartColor.withValues(alpha: 0.6)
            : timelineDrawingStartColor,
        // Selected keys ring in ACCENT 1 (UI-R23 #4) — a thin silhouette
        // stroke, color only (the selection rule); accent 2 stays on the
        // repeat wash/outline.
        border: Border.all(
          color: widget.selected ? AppColors.accent : colorScheme.surface,
          width: widget.selected ? _selectedLaneKeyBorderWidth : 1,
        ),
      ),
    );
    // AE convention: linear keys read as diamonds, hold keys as squares.
    final content = Transform.translate(
      // Snap the ghost per frame while dragging (AE feel).
      offset: horizontal
          ? Offset(_dragging ? _frameDelta * widget.frameCellExtent : 0, 0)
          : Offset(0, _dragging ? _frameDelta * widget.frameCellExtent : 0),
      child: Center(
        child: widget.hold
            ? shape
            : Transform.rotate(angle: 0.785398, child: shape),
      ),
    );

    // WHOLLY transparent when the band owns the gesture. Translucent is not
    // enough: `RenderDecoratedBox.hitTestSelf` answers TRUE anywhere inside
    // its decoration, so the drawn diamond is a hit target in its own right
    // and the Stack would stop at it with the band never seeing the
    // pointer.
    if (widget.onMoveBy == null) {
      return IgnorePointer(child: content);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Drag from the DOWN position (R10) — the rule the block edge grips
      // took in the same round. This marker accumulates deltas and rounds
      // them, so discarding the ~18px the recognizer spends on the arena
      // parks the key that far behind the finger for the whole drag.
      dragStartBehavior: DragStartBehavior.down,
      // The key drags along the frame axis of the owning grid.
      onHorizontalDragStart: horizontal ? (_) => _startDrag() : null,
      onHorizontalDragUpdate: horizontal ? _updateDrag : null,
      onHorizontalDragEnd: horizontal ? (_) => _endDrag() : null,
      onHorizontalDragCancel: horizontal ? _cancelDrag : null,
      onVerticalDragStart: horizontal ? null : (_) => _startDrag(),
      onVerticalDragUpdate: horizontal ? null : _updateDrag,
      onVerticalDragEnd: horizontal ? null : (_) => _endDrag(),
      onVerticalDragCancel: horizontal ? null : _cancelDrag,
      child: content,
    );
  }
}
