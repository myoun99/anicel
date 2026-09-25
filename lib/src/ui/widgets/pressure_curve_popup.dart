import 'app_tooltip.dart';
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';

import '../../models/brush_input_source.dart';
import '../../models/brush_pressure_curve.dart';
import '../theme/app_theme.dart';
import '../theme/disabled_ink.dart';
import 'anchored_popup.dart';
import 'field_slider.dart' show sliderValueText;
import '../text/app_strings.dart' show AppText;
import '../repaint_props.dart';

/// BB-3 (R26 #11): the shared pen-pressure curve editor — a CSP-style
/// 筆圧設定 popup. One [PressureCurveButton] sits at the right of each
/// pressure-capable slider row (size/opacity/flow/hardness); tapping it
/// opens the small anchored editor. The widget is generic over the value
/// (a [BrushPressureCurve]?), so any future pressure-capable setting can
/// reuse it unchanged.
///
/// Editor grammar (CSP vocabulary):
///  - drag a control point to move it (endpoints keep their x),
///  - press an empty spot on the curve area to ADD a point and drag on,
///  - drag a middle point well outside the graph to REMOVE it,
///  - the switch turns pressure OFF (curve = null) / ON (identity line).
class PressureCurveButton extends StatelessWidget {
  const PressureCurveButton({
    super.key,
    required this.keyValue,
    required this.title,
    required this.curves,
    required this.onChanged,
    this.enabled = true,
  });

  /// False dims the button and refuses the popup (TP2): the tools that take
  /// no pressure keep the control in place and greyed rather than losing it,
  /// so the row never changes shape and "does pressure apply here?" has a
  /// visible answer.
  final bool enabled;

  /// Widget key string for the trigger button ('brush-tool-pressure-size').
  final String keyValue;

  /// Popup header label (the setting's name, e.g. 'Size').
  final String title;

  /// Every input source's curve for this setting; an absent or null entry is
  /// a source that does not drive it.
  final Map<BrushInputSource, BrushPressureCurve?> curves;
  final ValueChanged<Map<BrushInputSource, BrushPressureCurve?>> onChanged;

  /// The OFF state's ink, mark and edge together.
  ///
  /// 유저, R6 #2: 「필압아이콘 필압설정안하면 x잖아. 지금 진하니까 불투명도
  /// 낮은 하얀색 x로」 · 「테두리도 그럼 흐리게하자」.
  ///
  /// ⚠️It is NOT [AppColors.textDim], which is what it used to be and is the
  /// reason it read as loud: that token is 0xFF9DA2A6 against body text's
  /// 0xFFB4B8BB — a "dim" that is only dim beside white, and BRIGHTER than
  /// most of the row it sits in. The one control whose whole message is
  /// "this setting is doing nothing" was the strongest mark on the line.
  ///
  /// A transparent white rather than another opaque grey, so it dims
  /// against whatever surface the button lands on — the tool settings, the
  /// brush panel and the top strip are three different greys.
  static const Color _offInk = Color(0x4DFFFFFF);
  static const Color _offEdge = Color(0x1AFFFFFF);

  /// The mini curve this button paints, and the padding around it. Named
  /// because [slotWidth] is derived from them and a row reserving the slot
  /// must not re-derive either.
  /// ⚠️Two doubles rather than a `Size`: `Size.width` is not a constant
  /// expression, and [slotWidth] has to be one.
  static const double _curveWidth = 22;
  static const double _curveHeight = 14;
  static const Size _curveSize = Size(_curveWidth, _curveHeight);
  static const double _curvePadding = 3;

  /// How wide this button stands in a settings row.
  ///
  /// ⚠️The border is NOT in the sum: a [DecoratedBox] sizes itself to its
  /// child and paints the shape over that box, so the stroke costs no
  /// layout width. (A `Container` with the same decoration would differ —
  /// it applies `decoration.padding`.)
  ///
  /// 🚨A ROW WITHOUT A CURVE BUTTON RESERVES THIS MUCH ANYWAY (유저 09-08:
  /// 「슬라이더 크기는 항상 고정되도록. 압력버튼없으면 그냥 빈공간으로」).
  /// Two of the settings panel's twenty sliders carry a button, and before
  /// this the other eighteen ate the space — the same control at two widths
  /// in one panel, which is the 「자리는 항상 예약하고 내용만 바꾼다」 rule
  /// read backwards.
  ///
  /// ⚠️Kept honest by `pressure_curve_button_slot_test`, which lays the real
  /// button out and fails if its width stops matching this number.
  static const double slotWidth = _curveWidth + _curvePadding * 2;

  /// Spelled out rather than left to [BorderSide]'s default, so the note in
  /// [slotWidth] about the stroke costing no width names a real number.
  static const double _borderWidth = 1;

  @override
  Widget build(BuildContext context) {
    // ANY source counts: the button says "this setting is driven", and after
    // the source axis that is no longer a question about pressure alone.
    final active = enabled && curves.values.any((curve) => curve != null);
    final button = AppTooltip(
      message: AppText.strings.penPressureTitle,
      child: Material(
        color: Colors.transparent,
        child: ControlPressClaim(
          onPressed: enabled
              ? () => showPressureCurvePopup(
                  context,
                  title: title,
                  initialCurves: curves,
                  onChanged: onChanged,
                )
              : null,
          child: InkWell(
            key: ValueKey<String>(keyValue),
            customBorder: AppShapes.container(AppShapes.wellRadius),
            onTap: silentPress(
              enabled
                  ? () => showPressureCurvePopup(
                      context,
                      title: title,
                      initialCurves: curves,
                      onChanged: onChanged,
                    )
                  : null,
            ),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: AppShapes.container(
                  AppShapes.wellRadius,
                  side: BorderSide(
                    color: dimmedIfDisabled(
                      active ? AppColors.accent : _offEdge,
                      enabled: enabled,
                    ),
                    width: _borderWidth,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(_curvePadding),
                child: CustomPaint(
                  size: _curveSize,
                  painter: _MiniCurvePainter(
                    // The thumbnail draws PRESSURE — the source every device
                    // has. A thumbnail that tried to show three would be
                    // three unreadable lines at 22x14.
                    curve: curves[BrushInputSource.pressure],
                    color: dimmedIfDisabled(
                      active ? AppColors.accent : _offInk,
                      enabled: enabled,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The same 40% the field slider dims to, so a disabled group reads as
    // one thing rather than as three different greys — [disabledInkOpacity]
    // is where that figure lives now.
    //
    // 🪦It used to be `Opacity(0.4)` around the whole button, and that is a
    // compositing boundary: it cost the panel it sits in its bake, on every
    // frame (유저 확정 2026-09-22, 보드
    // `a-disabled-bar-dims-without-a-layer-Q1`). The well's own two colours
    // carry the dimming now.
    return button;
  }
}

/// The tiny in-button preview: the CURVE when pressure is on, and an X when
/// it is off.
///
/// 유저, R4 #9: 필압 적용 안 했을 때의 ui, 지금 버튼이 상단정렬된 직선의
/// 그래프가 그대로 보이는데, 그게 아니라 해당 버튼에 그래프 말고 x 이렇게 둬서
/// 필압 적용 안 되어 있다는 거 알기 쉽게.
///
/// The OFF state used to draw `evaluate(t) ?? 1.0` — a flat line pinned to
/// the top of the box, which is a perfectly truthful graph of "pressure has
/// no effect" and reads at 22×14px as a graph you have not looked at
/// closely. Worse, an identity curve that has been dragged flat draws the
/// same picture and means the opposite thing. An X is not a graph at all,
/// which is exactly the point: OFF is a different KIND of state, not a
/// shape the curve can take.
class _MiniCurvePainter extends CustomPainter with RepaintOnProps {
  const _MiniCurvePainter({required this.curve, required this.color});

  final BrushPressureCurve? curve;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      // Round ends so the X's four arms do not read as chipped at this size.
      ..strokeCap = StrokeCap.round;
    final shape = curve;
    if (shape == null) {
      // Inset, so the X is a mark inside the button rather than a cross
      // that touches its border on all four sides.
      const inset = 3.0;
      final box = Rect.fromLTRB(
        inset,
        inset,
        size.width - inset,
        size.height - inset,
      );
      canvas.drawLine(box.topLeft, box.bottomRight, paint);
      canvas.drawLine(box.topRight, box.bottomLeft, paint);
      return;
    }
    canvas.drawPath(pressureCurvePath(shape, size, steps: 12), paint);
  }

  @override
  Object get props => (curve, color);
}

/// [curve] sampled in [steps] equal pressure steps across [size]: pressure
/// runs left→right and a multiplier of 1 sits at the TOP of the box. The
/// one kernel behind the button's mini graph and the editor's big graph —
/// they differ only in how densely they sample.
Path pressureCurvePath(
  BrushPressureCurve curve,
  Size size, {
  required int steps,
}) {
  final path = Path();
  for (var i = 0; i <= steps; i += 1) {
    final t = i / steps;
    final value = curve.evaluate(t);
    final x = t * size.width;
    final y = (1.0 - value) * size.height;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  return path;
}

/// Popup geometry. The WIDTH is frozen at 248 (유저 확정 2026-09-08 ⑧); the
/// height is the axis that gives.
const double _popupWidth = 248;
const double _popupHeight = 316;

/// One source's row: the 60px name column beside the curve strip.
const double _rowHeight = 84;
const double _sourceColumnWidth = 60;
const double _sourceColumnGap = 6;
const double _rowGap = 6;
const double _headerHeight = 24;

/// Shows the anchored curve editor next to [anchorContext]'s widget.
///
/// [initialCurves] is every input source's curve for ONE setting, and
/// [onChanged] hands back every source's curve for that setting — the whole
/// target, every time.
///
/// 🚨IT IS THE WHOLE TARGET ON PURPOSE, and the reason replaced a comment
/// that said the opposite. This used to read "the popup keeps its own working
/// state, so the caller may rebuild freely underneath", which advertised the
/// trap as a safety: `onChanged` closes over the tool state as it was when
/// the BUTTON was built, and that closure outlives every edit in the popup.
/// While one popup wrote one key, three writes off one stale base all landed
/// on the same key and agreed by accident. Three sources do not — clearing
/// tilt and then dragging pressure would read the stale base again and put
/// tilt back. One call, one base.
Future<void> showPressureCurvePopup(
  BuildContext anchorContext, {
  required String title,
  required Map<BrushInputSource, BrushPressureCurve?> initialCurves,
  required ValueChanged<Map<BrushInputSource, BrushPressureCurve?>> onChanged,
}) {
  // R28 #9: placement and dismissal now live in the SHARED sub-window
  // shell — this popup is where that behaviour was designed, and every
  // other anchored window in the app opens through the same function.
  return showAnchoredPopup<void>(
    anchorContext,
    label: 'pressure-curve-popup',
    width: _popupWidth,
    height: _popupHeight,
    builder: (context, _) => _PressureCurveEditor(
      title: title,
      initialCurves: initialCurves,
      onChanged: onChanged,
    ),
  );
}

class _PressureCurveEditor extends StatefulWidget {
  const _PressureCurveEditor({
    required this.title,
    required this.initialCurves,
    required this.onChanged,
  });

  final String title;
  final Map<BrushInputSource, BrushPressureCurve?> initialCurves;
  final ValueChanged<Map<BrushInputSource, BrushPressureCurve?>> onChanged;

  @override
  State<_PressureCurveEditor> createState() => _PressureCurveEditorState();
}

/// One source's working curve while the popup is open.
///
/// The shape and the ceiling are kept apart because the model keeps them
/// apart: points live in the unit square and `evaluate` multiplies by
/// [maximum] afterwards, so the graph physically cannot draw the ceiling.
class _SourceDraft {
  _SourceDraft({
    required this.points,
    required this.maximum,
    required this.enabled,
  });

  List<BrushCurvePoint> points;
  double maximum;
  bool enabled;
}

class _PressureCurveEditorState extends State<_PressureCurveEditor> {
  static const int _maxPoints = 10;
  static const double _minXGap = 0.02;

  /// One working draft per source; the shape survives a toggle OFF so ON
  /// restores it within this popup session.
  final Map<BrushInputSource, _SourceDraft> _drafts = {};

  /// The grabbed point during a drag, and WHICH ROW it belongs to. A grabbed
  /// middle point dragged far outside is REMOVED but stays "in hand"
  /// ([_dragRemoved]) so dragging back in re-adds it.
  BrushInputSource? _dragSource;
  int? _dragIndex;
  bool _dragRemoved = false;

  @override
  void initState() {
    super.initState();
    for (final source in BrushInputSource.values) {
      final curve = widget.initialCurves[source];
      _drafts[source] = _SourceDraft(
        points: List.of((curve ?? BrushPressureCurve.identity()).points),
        maximum: curve?.maximum ?? 1.0,
        enabled: curve != null,
      );
    }
  }

  /// Publishes EVERY source for this setting — see [showPressureCurvePopup]
  /// for why one source at a time would lose an edit.
  void _commit() {
    widget.onChanged({
      for (final source in BrushInputSource.values)
        source: _drafts[source]!.enabled
            ? BrushPressureCurve(
                List.of(_drafts[source]!.points),
                maximum: _drafts[source]!.maximum,
              )
            : null,
    });
  }

  void _setEnabled(BrushInputSource source, bool value) {
    setState(() {
      _drafts[source]!.enabled = value;
      _endDragState();
    });
    _commit();
  }

  void _reset(BrushInputSource source) {
    setState(() {
      // ⛔The ceiling is NOT reset with the shape: the model keeps them apart
      // deliberately, and a reset that silently dropped an imported 最大値
      // would throw away the one fact the graph cannot show.
      _drafts[source]!.points = BrushPressureCurve.identity().points.toList();
      _endDragState();
    });
    _commit();
  }

  void _endDragState() {
    _dragSource = null;
    _dragIndex = null;
    _dragRemoved = false;
  }

  @override
  Widget build(BuildContext context) {
    // ⛔No `Material` of its own. The surface, the corner and the lift are
    // the anchored popup's now (R4 #8) — this window is where that shell was
    // designed, and it was the last thing the shell did not own.
    return Padding(
      key: const ValueKey<String>('pressure-curve-popup'),
      padding: AnchoredPopupText.bodyPadding,
      // 🚨The declared popup height and the drawn height are the same number
      // BY CONSTRUCTION, not by arithmetic that has to be kept in step. The
      // declared height decides where the window is placed and which way it
      // flips, so a body that drew short used to hang that far off its anchor.
      child: SizedBox(
        height:
            _popupHeight -
            AnchoredPopupText.bodyPadding.top -
            AnchoredPopupText.bodyPadding.bottom,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ⛔NO master switch here any more. One switch above three rows is
            // one control answering three questions; each row owns its own.
            SizedBox(
              height: _headerHeight,
              child: AnchoredPopupHeader(
                title: '${widget.title} — ${AppText.strings.brushDynamicsTitle}',
              ),
            ),
            const SizedBox(height: AnchoredPopupText.titleGap),
            for (final source in BrushInputSource.values) ...[
              if (source != BrushInputSource.values.first)
                const SizedBox(height: _rowGap),
              _buildRow(source),
            ],
          ],
        ),
      ),
    );
  }

  /// 🚨ALL THREE SOURCES ARE VISIBLE AT ONCE, and that is the design, not a
  /// layout convenience. A tab or a segmented selector would put a source
  /// BEHIND a click — and the whole reason this axis exists is that the .sut
  /// importer already builds tilt and speed curves the user cannot see. A
  /// picker that hides two of three would leave that gap open by a different
  /// door.
  Widget _buildRow(BrushInputSource source) {
    final draft = _drafts[source]!;
    return SizedBox(
      height: _rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _sourceColumnWidth,
            child: _buildSourceColumn(source, draft),
          ),
          const SizedBox(width: _sourceColumnGap),
          Expanded(child: _buildStrip(source, draft)),
        ],
      ),
    );
  }

  Widget _buildSourceColumn(BrushInputSource source, _SourceDraft draft) {
    final label = switch (source) {
      BrushInputSource.pressure => AppText.strings.curveSourcePressure,
      BrushInputSource.tilt => AppText.strings.curveSourceTilt,
      BrushInputSource.speed => AppText.strings.curveSourceSpeed,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // The NAME is the toggle — 「선택 표시는 색상만」, so on and off differ
        // in ink and in nothing else. Fires on release inside the button:
        // this is not a rail row, so it is not a tap-down.
        SizedBox(
          height: 40,
          child: ControlPressClaim(
            onPressed: () => _setEnabled(source, !draft.enabled),
            child: InkWell(
              key: ValueKey<String>('curve-source-${source.name}'),
              customBorder: AppShapes.container(AppShapes.wellRadius),
              onTap: silentPress(() => _setEnabled(source, !draft.enabled)),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: draft.enabled
                        ? AppColors.accent
                        : PressureCurveButton._offInk,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        // The ceiling, READ-ONLY and ALWAYS drawn — at ×1 too, because a
        // readout that appears when the value leaves its default is UI that
        // pops into existence.
        //
        // ⛔It is not editable, and not because a control would be hard: the
        // ceiling only means anything on SIZE (the other three targets are
        // clamped back into [0,1] downstream), so nine of the twelve cells
        // would be a live control that does nothing. It arrives from an
        // imported 最大値 and this says so.
        SizedBox(
          height: 18,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              // A ceiling read to the tenth, always: `×1` beside `×1.5` was
              // the same digit-count flicker F-34 named on the bars.
              '×${sliderValueText(draft.maximum, decimals: 1)}',
              key: ValueKey<String>('curve-maximum-${source.name}'),
              style: AnchoredPopupText.caption,
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 22,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ControlPressClaim(
              onPressed: draft.enabled ? () => _reset(source) : null,
              child: InkWell(
                key: ValueKey<String>('curve-reset-${source.name}'),
                onTap: silentPress(
                  draft.enabled ? () => _reset(source) : null,
                ),
                customBorder: AppShapes.container(3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    AppText.strings.commonReset,
                    style: TextStyle(
                      fontSize: 10,
                      color: draft.enabled
                          ? AppColors.text
                          : AppColors.textDim.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 🚨THE PAINTED BOX AND THE HIT BOX ARE ONE MEASUREMENT. They used to be
  /// two: `_graphSize` was `Size(196, 150)` — the popup's old width minus its
  /// padding, typed in by hand — while the painter took whatever tight
  /// constraint the column handed it. They agreed only while nobody changed
  /// the width. Widening to 248 with that arrangement would have left the
  /// remove-slack boundary INSIDE the drawn graph, so dragging a middle point
  /// to the right edge would delete it.
  Widget _buildStrip(BrushInputSource source, _SourceDraft draft) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        // 🚨A drag on this strip IS the verb — it moves a curve point. So it
        // takes the STRONG claim: no eager pan above may start from here, and
        // the weak claim's absorber stands down for it.
        return DragVerbClaim(
          behavior: HitTestBehavior.opaque,
          child: GestureDetector(
            key: ValueKey<String>('pressure-curve-graph-${source.name}'),
            behavior: HitTestBehavior.opaque,
            onPanStart: draft.enabled
                ? (details) => _handlePanStart(source, box, details)
                : null,
            onPanUpdate: draft.enabled
                ? (details) => _handlePanUpdate(source, box, details)
                : null,
            onPanEnd: draft.enabled
                ? (_) => setState(_endDragState)
                : null,
            child: CustomPaint(
              painter: _CurveGraphPainter(
                points: draft.points,
                enabled: draft.enabled,
                accent: AppColors.accent,
              ),
            ),
          ),
        );
      },
    );
  }

  Offset _toUnit(Size box, Offset local) => Offset(
    (local.dx / box.width).clamp(0.0, 1.0),
    (1.0 - local.dy / box.height).clamp(0.0, 1.0),
  );

  void _handlePanStart(
    BrushInputSource source,
    Size box,
    DragStartDetails details,
  ) {
    final points = _drafts[source]!.points;
    final local = details.localPosition;
    // Grab the nearest point within reach, else add one at the press.
    //
    // ⛔14 and the remove slack below stay ABSOLUTE across every strip size.
    // They are the reach of a finger, not a fraction of the box — scaling
    // them with the strip would be a rule nobody asked for.
    const grabRadius = 14.0;
    int? nearest;
    var nearestDistance = double.infinity;
    for (var i = 0; i < points.length; i += 1) {
      final point = points[i];
      final position = Offset(
        point.x * box.width,
        (1.0 - point.y) * box.height,
      );
      final distance = (position - local).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = i;
      }
    }
    if (nearest != null && nearestDistance <= grabRadius) {
      setState(() {
        _dragSource = source;
        _dragIndex = nearest;
        _dragRemoved = false;
      });
      return;
    }
    if (points.length >= _maxPoints) {
      return;
    }
    _insertPointAt(source, box, local);
  }

  /// Inserts a point at [local]'s x between its neighbours and starts
  /// dragging it; nothing happens outside the endpoints or where the
  /// neighbours leave no room ([_minXGap]).
  ///
  /// ONE law for the press that adds a point and the drag that brings a
  /// removed point back in (the audit's clone scan, 2026-09-03).
  void _insertPointAt(BrushInputSource source, Size box, Offset local) {
    final points = _drafts[source]!.points;
    final unit = _toUnit(box, local);
    var insertAt = points.length;
    for (var i = 0; i < points.length; i += 1) {
      if (unit.dx < points[i].x) {
        insertAt = i;
        break;
      }
    }
    if (insertAt == 0 || insertAt == points.length) {
      return; // Outside the endpoints' x range (they sit at 0 and 1).
    }
    final clampedX = unit.dx.clamp(
      points[insertAt - 1].x + _minXGap,
      points[insertAt].x - _minXGap,
    );
    if (clampedX <= points[insertAt - 1].x || clampedX >= points[insertAt].x) {
      return; // Neighbors too close to fit another point.
    }
    setState(() {
      points.insert(insertAt, BrushCurvePoint(clampedX, unit.dy));
      _dragSource = source;
      _dragIndex = insertAt;
      _dragRemoved = false;
    });
    _commit();
  }

  void _handlePanUpdate(
    BrushInputSource source,
    Size box,
    DragUpdateDetails details,
  ) {
    final index = _dragIndex;
    // A drag belongs to the row it started in; a pointer that wandered over
    // a neighbouring strip does not hand it over.
    if (index == null || _dragSource != source) {
      return;
    }
    final points = _drafts[source]!.points;
    final local = details.localPosition;
    // Middle points dragged far outside the graph are removed (CSP's
    // delete gesture); dragging back inside re-adds them.
    const removeSlack = 28.0;
    final outside =
        local.dx < -removeSlack ||
        local.dx > box.width + removeSlack ||
        local.dy < -removeSlack ||
        local.dy > box.height + removeSlack;
    final isMiddle = !_dragRemoved && index > 0 && index < points.length - 1;
    if (outside && isMiddle) {
      setState(() {
        points.removeAt(index);
        _dragRemoved = true;
      });
      _commit();
      return;
    }
    if (_dragRemoved) {
      if (outside) {
        return;
      }
      _insertPointAt(source, box, local);
      return;
    }
    final unit = _toUnit(box, local);
    final double x;
    if (index == 0) {
      x = 0.0;
    } else if (index == points.length - 1) {
      x = 1.0;
    } else {
      x = unit.dx.clamp(
        points[index - 1].x + _minXGap,
        points[index + 1].x - _minXGap,
      );
    }
    setState(() {
      points[index] = BrushCurvePoint(x, unit.dy);
    });
    _commit();
  }
}

class _CurveGraphPainter extends CustomPainter {
  const _CurveGraphPainter({
    required this.points,
    required this.enabled,
    required this.accent,
  });

  final List<BrushCurvePoint> points;
  final bool enabled;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = AppColors.surface;
    canvas.drawRect(Offset.zero & size, background);
    final grid = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i += 1) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawRect(
      (Offset.zero & size).deflate(0.5),
      Paint()
        ..color = AppColors.hairline
        ..style = PaintingStyle.stroke,
    );

    final lineColor = enabled ? accent : AppColors.textDim;
    final curvePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    // The disabled graph is a flat line at value 1.0 — "pressure has no
    // effect" — drawn along the top edge; the curve itself is not consulted.
    final path = enabled
        ? pressureCurvePath(
            BrushPressureCurve(List.of(points)),
            size,
            steps: 48,
          )
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0));
    canvas.drawPath(path, curvePaint);

    if (enabled) {
      final handleFill = Paint()..color = accent;
      final handleStroke = Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (final point in points) {
        final center = Offset(
          point.x * size.width,
          (1.0 - point.y) * size.height,
        );
        final rect = Rect.fromCenter(center: center, width: 7, height: 7);
        canvas.drawRect(rect, handleFill);
        canvas.drawRect(rect, handleStroke);
      }
    }
  }

  // The editor mutates its working list in place, so instance identity
  // can't detect changes — the graph is tiny, always repaint.
  @override
  bool shouldRepaint(_CurveGraphPainter oldDelegate) => true;
}
