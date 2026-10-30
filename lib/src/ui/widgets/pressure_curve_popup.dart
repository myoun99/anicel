import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../../core/neighbour_pairs.dart';

import '../../models/brush_input_source.dart';
import '../../models/brush_pressure_curve.dart';
import '../theme/app_theme.dart';
import 'anchored_popup.dart';
import 'field_slider.dart';
import 'kept_tail_row.dart';
import 'setting_source_button.dart';
import 'owning_axis_grip.dart';
import '../text/app_strings.dart' show AppText;
import '../repaint_props.dart';

/// BB-3 (R26 #11): the shared pen-pressure curve editor — a CSP-style
/// 筆圧設定 popup. One [PressureCurveButton] sits at the right of each
/// pressure-capable slider row (size/opacity/flow/hardness); tapping it
/// opens the small anchored editor. The widget is generic over the value
/// (a [BrushPressureCurve]?), so any future pressure-capable setting can
/// reuse it unchanged.
///
/// Each graph is a [PressureCurveGraph] — the hand every curve in the app is
/// edited by — and a source's name turns it OFF (curve = null) / ON (the
/// identity line).
class PressureCurveButton extends StatelessWidget {
  const PressureCurveButton({
    super.key,
    required this.keyValue,
    required this.target,
    required this.curves,
    required this.onChanged,
    this.enabled = true,
  });

  /// False dims the button and refuses the popup — see
  /// [SettingSourceButton.enabled].
  final bool enabled;

  /// Widget key string for the trigger button ('brush-tool-pressure-size').
  final String keyValue;

  /// The setting these curves drive — see [showPressureCurvePopup].
  final BrushPressureTarget target;

  /// Every input source's curve for this setting; an absent or null entry is
  /// a source that does not drive it.
  final Map<BrushInputSource, BrushPressureCurve?> curves;
  final ValueChanged<Map<BrushInputSource, BrushPressureCurve?>> onChanged;

  @override
  Widget build(BuildContext context) => SettingSourceButton(
    keyValue: keyValue,
    tooltip: AppText.strings.penPressureTitle,
    enabled: enabled,
    // ANY source counts: the button says "this setting is driven", and after
    // the source axis that is no longer a question about pressure alone.
    active: curves.values.any((curve) => curve != null),
    onPressed: (anchor) => showPressureCurvePopup(
      anchor,
      target: target,
      initialCurves: curves,
      onChanged: onChanged,
    ),
    glyph: (ink) => _MiniCurvePainter(
      // The thumbnail draws PRESSURE — the source every device has. A
      // thumbnail that tried to show three would be three unreadable lines
      // at 14x14.
      curve: curves[BrushInputSource.pressure],
      color: ink,
    ),
  );
}

/// The tiny in-button preview: the CURVE when pressure is on, and the off
/// mark ([paintSettingOffMark]) when it is off.
///
/// The OFF state used to draw `evaluate(t) ?? 1.0` — a flat line pinned to
/// the top of the box, which is a perfectly truthful graph of "pressure has
/// no effect" and reads at 22×14px as a graph you have not looked at
/// closely. Worse, an identity curve that has been dragged flat draws the
/// same picture and means the opposite thing.
class _MiniCurvePainter extends CustomPainter with RepaintOnProps {
  const _MiniCurvePainter({required this.curve, required this.color});

  final BrushPressureCurve? curve;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = settingGlyphPaint(color);
    final shape = curve;
    if (shape == null) {
      paintSettingOffMark(canvas, size, paint);
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

/// Popup geometry. The WIDTH is the source windows' frozen one
/// ([SettingSourceButton.windowWidth]); the height is the axis that gives.
const double _popupWidth = SettingSourceButton.windowWidth;

/// The layout after Clip Studio's 影響元設定 (F-176-Q2, 유저 2026-10-18
/// 「첨부한 클튜 팝업창 최대한 참고해서 구현」): a row per input — its tick and
/// its 最小値, 傾き's 最大値 under it — and the graphs side by side beneath.
const double _headerHeight = 24;
const double _nameWidth = 56;
const double _nameGap = 6;
const double _rowGap = 4;
const double _sectionGap = 8;
const double _graphGap = 6;
const double _graphTitleHeight = 16;
const double _axisHeight = 12;

/// The inputs that have a graph — 筆圧 and 傾き, as Clip Studio's
/// 影響元設定 draws them; 速度 and ランダム have a 最小値 alone.
///
/// 🗣️F-456-Q3 (유저 2026-10-23 「속도 그래프를 없애고 두 칸으로」).
/// ↩️速度 had a graph, built on a file read that took 0x20 for 速度 and
/// gave it the graph the file keeps for 傾き.
const List<BrushInputSource> _graphed = [
  BrushInputSource.pressure,
  BrushInputSource.tilt,
];

double get _innerWidth =>
    _popupWidth - AnchoredPopupText.bodyPadding.horizontal;

double get _graphSide =>
    (_innerWidth - _graphGap * (_graphed.length - 1)) / _graphed.length;

/// 🚨The declared popup height and the drawn height are the same number BY
/// CONSTRUCTION: this sums exactly the boxes [_PressureCurveEditorState.build]
/// stacks, so the window is placed for the body it draws.
double _popupHeightFor({required bool ceiling}) {
  final rows = BrushInputSource.values.length + (ceiling ? 1 : 0);
  return AnchoredPopupText.bodyPadding.vertical +
      _headerHeight +
      AnchoredPopupText.titleGap +
      rows * FieldSlider.defaultHeight +
      (rows - 1) * _rowGap +
      _sectionGap +
      _graphTitleHeight +
      _graphSide +
      _axisHeight;
}

/// Shows the anchored curve editor next to [anchorContext]'s widget.
///
/// [initialCurves] is every input source's curve for ONE setting, and
/// [onChanged] hands back every source's curve for that setting — the whole
/// target, every time. [target] names the setting in the header, and offers
/// 傾き's 最大値 only where it can go past its base at all
/// ([BrushPressureTarget.canPassItsBase]).
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
  required BrushPressureTarget target,
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
    height: _popupHeightFor(ceiling: target.canPassItsBase),
    builder: (context, _) => _PressureCurveEditor(
      target: target,
      initialCurves: initialCurves,
      onChanged: onChanged,
    ),
  );
}

class _PressureCurveEditor extends StatefulWidget {
  const _PressureCurveEditor({
    required this.target,
    required this.initialCurves,
    required this.onChanged,
  });

  final BrushPressureTarget target;
  final Map<BrushInputSource, BrushPressureCurve?> initialCurves;
  final ValueChanged<Map<BrushInputSource, BrushPressureCurve?>> onChanged;

  @override
  State<_PressureCurveEditor> createState() => _PressureCurveEditorState();
}

/// One source's working curve while the popup is open — the three facts
/// the model keeps apart: the shape (the graph), the floor and the ceiling.
class _SourceDraft {
  _SourceDraft({
    required this.points,
    required this.minimum,
    required this.maximum,
    required this.enabled,
  });

  List<BrushCurvePoint> points;
  double minimum;
  double maximum;
  bool enabled;
}

class _PressureCurveEditorState extends State<_PressureCurveEditor> {
  /// One working draft per source; the shape survives a toggle OFF so ON
  /// restores it within this popup session.
  final Map<BrushInputSource, _SourceDraft> _drafts = {};

  @override
  void initState() {
    super.initState();
    for (final source in BrushInputSource.values) {
      final curve = widget.initialCurves[source];
      _drafts[source] = _SourceDraft(
        points: List.of((curve ?? BrushPressureCurve.identity()).points),
        minimum: curve?.minimum ?? 0.0,
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
                minimum: _drafts[source]!.minimum,
                maximum: _drafts[source]!.maximum,
              )
            : null,
    });
  }

  void _setEnabled(BrushInputSource source, bool value) {
    setState(() => _drafts[source]!.enabled = value);
    _commit();
  }

  void _setRange(BrushInputSource source, {double? minimum, double? maximum}) {
    setState(() {
      final draft = _drafts[source]!;
      draft.minimum = minimum ?? draft.minimum;
      draft.maximum = maximum ?? draft.maximum;
    });
    _commit();
  }

  void _reset(BrushInputSource source) {
    setState(() {
      // ⛔The floor and the ceiling are NOT reset with the shape: the model
      // keeps them apart deliberately, and they have sliders of their own.
      _drafts[source]!.points = BrushPressureCurve.identity().points;
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    // ⛔No `Material` of its own. The surface, the corner and the lift are
    // the anchored popup's now (R4 #8) — this window is where that shell was
    // designed, and it was the last thing the shell did not own.
    final rows = <Widget>[
      for (final source in BrushInputSource.values) ...[
        _buildSourceRow(source),
        // 傾き's 最大値 sits under its 最小値, as Clip Studio lays it.
        if (widget.target.canPassItsBase && source == BrushInputSource.tilt)
          _buildMaximumRow(source),
      ],
    ];
    return Padding(
      key: const ValueKey<String>('pressure-curve-popup'),
      padding: AnchoredPopupText.bodyPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⛔NO master switch here any more. One switch above the rows is
          // one control answering four questions; each row owns its own.
          SizedBox(
            height: _headerHeight,
            child: AnchoredPopupHeader(
              title:
                  '${_titleOf(widget.target)} — '
                  '${AppText.strings.brushDynamicsTitle}',
            ),
          ),
          const SizedBox(height: AnchoredPopupText.titleGap),
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: _rowGap),
            SizedBox(height: FieldSlider.defaultHeight, child: row),
          ],
          const SizedBox(height: _sectionGap),
          // 🚨EVERY INPUT IS VISIBLE AT ONCE, and that is the design, not a
          // layout convenience. A tab or a segmented selector would put a
          // source BEHIND a click — and the whole reason this axis exists is
          // that the .sut importer already builds tilt and speed curves the
          // user could not see.
          SizedBox(
            height: _graphTitleHeight + _graphSide + _axisHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, source) in _graphed.indexed) ...[
                  if (i > 0) const SizedBox(width: _graphGap),
                  SizedBox(width: _graphSide, child: _buildGraph(source)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The setting's name, as its slider row says it.
  String _titleOf(BrushPressureTarget target) => switch (target) {
    BrushPressureTarget.size => AppText.strings.brSize,
    BrushPressureTarget.opacity => AppText.strings.brOpacity,
    BrushPressureTarget.flow => AppText.strings.brFlow,
    BrushPressureTarget.hardness => AppText.strings.brHardness,
    BrushPressureTarget.roundness => AppText.strings.brRoundness,
    BrushPressureTarget.spacing => AppText.strings.brSpacing,
    BrushPressureTarget.textureDensity => AppText.strings.brTextureDensity,
    BrushPressureTarget.paintAmount => AppText.strings.brPaintAmount,
    BrushPressureTarget.paintDensity => AppText.strings.brPaintDensity,
  };

  String _nameOf(BrushInputSource source) => switch (source) {
    BrushInputSource.pressure => AppText.strings.curveSourcePressure,
    BrushInputSource.tilt => AppText.strings.curveSourceTilt,
    BrushInputSource.speed => AppText.strings.curveSourceSpeed,
    BrushInputSource.random => AppText.strings.curveSourceRandom,
  };

  /// A source's tick and its 最小値.
  Widget _buildSourceRow(BrushInputSource source) {
    final draft = _drafts[source]!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _nameWidth,
          // The NAME is the toggle.
          child: SettingSourceName(
            keyValue: 'curve-source-${source.name}',
            label: _nameOf(source),
            lit: draft.enabled,
            onPressed: () => _setEnabled(source, !draft.enabled),
          ),
        ),
        const SizedBox(width: _nameGap),
        Expanded(
          child: FieldSlider.opacity(
            key: ValueKey<String>('curve-minimum-${source.name}'),
            label: AppText.strings.curveMinimum,
            value: draft.minimum,
            onChanged: (value) => _setRange(source, minimum: value),
          ),
        ),
      ],
    );
  }

  /// 傾き's 最大値 — up to 1000%, Clip Studio's range.
  ///
  /// ↩️This was a READ-ONLY `×max` readout, kept so because "nine of the
  /// twelve cells would be a live control that does nothing": only size
  /// could go past its base. The popup now offers the slider where the
  /// setting can ([BrushPressureTarget.canPassItsBase] — size and spacing),
  /// the way Clip Studio's own panel does, and nowhere else.
  Widget _buildMaximumRow(BrushInputSource source) {
    final draft = _drafts[source]!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(width: _nameWidth + _nameGap),
        Expanded(
          child: FieldSlider(
            key: ValueKey<String>('curve-maximum-${source.name}'),
            label: AppText.strings.curveMaximum,
            value: draft.maximum,
            min: 1,
            max: 10,
            divisions: 900,
            unit: '%',
            displayScale: 100,
            onChanged: (value) => _setRange(source, maximum: value),
          ),
        ),
      ],
    );
  }

  /// One input's graph: its name and reset above, the graph, and — for
  /// 傾き — the ends of its axis beneath.
  ///
  /// 🚨傾き IS DRAWN MIRRORED, 水平 on the left and 垂直 on the right, because
  /// that is how Clip Studio draws it. The curve itself runs the other way —
  /// lean, 0 upright to 1 flat, which is how a .sut stores it — so the flip
  /// is the drawing's alone: [Transform.flip] turns the strip's paint and
  /// its pointer together, and nothing it writes changes.
  Widget _buildGraph(BrushInputSource source) {
    final draft = _drafts[source]!;
    final strip = PressureCurveGraph(
      key: ValueKey<String>('pressure-curve-graph-${source.name}'),
      points: draft.points,
      enabled: draft.enabled,
      onChanged: (points) {
        draft.points = points;
        _commit();
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _graphTitleHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _nameOf(source),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AnchoredPopupText.caption,
                ),
              ),
              _CurveReset(
                keyValue: 'curve-reset-${source.name}',
                onReset: draft.enabled ? () => _reset(source) : null,
              ),
            ],
          ),
        ),
        SizedBox(
          height: _graphSide,
          child: source == BrushInputSource.tilt
              ? Transform.flip(flipX: true, child: strip)
              : strip,
        ),
        SizedBox(
          height: _axisHeight,
          // ↩️A `Row` with a `Spacer`, which ran off the graph wherever its
          // two words outgrew it (a language's words, a wide font — 41px in
          // the test font). Both ends at their own size where they fit.
          child: source == BrushInputSource.tilt
              ? KeptTailRow(
                  // Two glyphs: a CJK end word whole.
                  headKeeps: AnchoredPopupText.caption.fontSize! * 2,
                  head: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppText.strings.curveTiltFlat,
                      style: AnchoredPopupText.caption,
                    ),
                  ),
                  tail: Text(
                    AppText.strings.curveTiltUpright,
                    style: AnchoredPopupText.caption,
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

/// The reset at a graph's head: the shape back to the straight line. A null
/// [onReset] dims it and takes no press — the graph of a source that is off.
class _CurveReset extends StatelessWidget {
  const _CurveReset({required this.keyValue, required this.onReset});

  final String keyValue;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => ControlPressClaim(
    onPressed: onReset,
    child: InkWell(
      mouseCursor: AppCursors.press,
      key: ValueKey<String>(keyValue),
      onTap: silentPress(onReset),
      customBorder: AppShapes.container(3),
      child: Text(
        AppText.strings.commonReset,
        style: TextStyle(
          fontSize: 10,
          color: onReset != null
              ? AppColors.text
              : AppColors.textDim.withValues(alpha: 0.5),
        ),
      ),
    ),
  );
}

/// ONE curve's graph, edited the way Clip Studio's are (BB-3) — and every
/// pressure graph in the app is this one: a brush's 影響元設定 lays two side
/// by side, Preferences' pen response one (F-480).
///
///  - drag a control point to move it (endpoints keep their x),
///  - press an empty spot on the curve area to ADD a point and drag on,
///  - drag a middle point well outside the graph to REMOVE it; dragged back
///    in, it is added again.
///
/// The points are the caller's. The graph edits a copy of its own and hands
/// every edit out as it happens, so readings that land before the caller
/// builds again never edit a list a step behind; points the caller changes
/// itself (a reset) replace the copy.
class PressureCurveGraph extends StatefulWidget {
  const PressureCurveGraph({
    super.key,
    required this.points,
    required this.onChanged,
    this.enabled = true,
    this.onChangeEnd,
  });

  final List<BrushCurvePoint> points;

  /// False draws the input doing nothing and takes no hand.
  final bool enabled;

  /// Every edit, as it happens.
  final ValueChanged<List<BrushCurvePoint>> onChanged;

  /// The hand that held a point let go.
  final VoidCallback? onChangeEnd;

  @override
  State<PressureCurveGraph> createState() => _PressureCurveGraphState();
}

class _PressureCurveGraphState extends State<PressureCurveGraph> {
  static const int _maxPoints = 10;
  static const double _minXGap = 0.02;

  late List<BrushCurvePoint> _points = List.of(widget.points);

  /// The grabbed point during a drag. A grabbed middle point dragged far
  /// outside is REMOVED but stays "in hand" ([_dragRemoved]) so dragging
  /// back in re-adds it.
  int? _dragIndex;
  bool _dragRemoved = false;

  @override
  void didUpdateWidget(PressureCurveGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Points the caller changed itself (a reset) replace the copy, and a
    // hand still on the graph lets go: its point may be gone.
    if (!listEquals(widget.points, _points)) {
      _points = List.of(widget.points);
      _endDrag();
    }
  }

  void _endDrag() {
    _dragIndex = null;
    _dragRemoved = false;
  }

  void _publish() => widget.onChanged(List.unmodifiable(_points));

  void _letGo() {
    final held = _dragIndex != null;
    setState(_endDrag);
    if (held) {
      widget.onChangeEnd?.call();
    }
  }

  /// 🚨THE PAINTED BOX AND THE HIT BOX ARE ONE MEASUREMENT. They used to be
  /// two: `_graphSize` was `Size(196, 150)` — the popup's old width minus its
  /// padding, typed in by hand — while the painter took whatever tight
  /// constraint the column handed it. They agreed only while nobody changed
  /// the width. Widening to 248 with that arrangement would have left the
  /// remove-slack boundary INSIDE the drawn graph, so dragging a middle point
  /// to the right edge would delete it.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        // 🚨A drag on this strip IS the verb — it moves a curve point. So it
        // takes the STRONG claim: no eager pan above may start from here, and
        // the weak claim's absorber stands down for it.
        //
        // F-200: the claim alone let a fast drag leak — the pan waited for
        // its slop, and a scroller above could get there first. The drag
        // takes the arena on its first movement (`axis_bar_gesture.dart`).
        // Both halves are [OwningAxisGrip]'s, a handle dragged both ways.
        return OwningAxisGrip(
          axis: null,
          configure: widget.enabled
              ? (recognizer) {
                  recognizer.onStart = (details) =>
                      _handlePanStart(box, details);
                  recognizer.onUpdate = (details) =>
                      _handlePanUpdate(box, details);
                  recognizer.onEnd = (_) => _letGo();
                }
              : null,
          child: CustomPaint(
            painter: _CurveGraphPainter(
              points: _points,
              enabled: widget.enabled,
              accent: AppColors.accent,
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

  void _handlePanStart(Size box, DragStartDetails details) {
    // Every drag starts empty-handed: one the grip dropped without an end
    // (the graph switched off under the hand) leaves nothing in it.
    _endDrag();
    final local = details.localPosition;
    // Grab the nearest point within reach, else add one at the press.
    //
    // ⛔14 and the remove slack below stay ABSOLUTE across every strip size.
    // They are the reach of a finger, not a fraction of the box — scaling
    // them with the strip would be a rule nobody asked for.
    const grabRadius = 14.0;
    int? nearest;
    var nearestDistance = double.infinity;
    for (var i = 0; i < _points.length; i += 1) {
      final point = _points[i];
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
        _dragIndex = nearest;
        _dragRemoved = false;
      });
      return;
    }
    if (_points.length >= _maxPoints) {
      return;
    }
    _insertPointAt(box, local);
  }

  /// Inserts a point at [local]'s x between its neighbours and starts
  /// dragging it; nothing happens outside the endpoints or where the
  /// neighbours leave no room ([_minXGap]).
  ///
  /// ONE law for the press that adds a point and the drag that brings a
  /// removed point back in (the audit's clone scan, 2026-09-03).
  void _insertPointAt(Size box, Offset local) {
    final unit = _toUnit(box, local);
    var insertAt = _points.length;
    for (var i = 0; i < _points.length; i += 1) {
      if (unit.dx < _points[i].x) {
        insertAt = i;
        break;
      }
    }
    if (insertAt == 0 || insertAt == _points.length) {
      return; // Outside the endpoints' x range (they sit at 0 and 1).
    }
    final clampedX = unit.dx.clamp(
      _points[insertAt - 1].x + _minXGap,
      _points[insertAt].x - _minXGap,
    );
    if (clampedX <= _points[insertAt - 1].x ||
        clampedX >= _points[insertAt].x) {
      return; // Neighbors too close to fit another point.
    }
    setState(() {
      _points.insert(insertAt, BrushCurvePoint(clampedX, unit.dy));
      _dragIndex = insertAt;
      _dragRemoved = false;
    });
    _publish();
  }

  void _handlePanUpdate(Size box, DragUpdateDetails details) {
    final index = _dragIndex;
    if (index == null) {
      return;
    }
    final local = details.localPosition;
    // Middle points dragged far outside the graph are removed (CSP's
    // delete gesture); dragging back inside re-adds them.
    const removeSlack = 28.0;
    final outside =
        local.dx < -removeSlack ||
        local.dx > box.width + removeSlack ||
        local.dy < -removeSlack ||
        local.dy > box.height + removeSlack;
    final isMiddle = !_dragRemoved && index > 0 && index < _points.length - 1;
    if (outside && isMiddle) {
      setState(() {
        _points.removeAt(index);
        _dragRemoved = true;
      });
      _publish();
      return;
    }
    if (_dragRemoved) {
      if (outside) {
        return;
      }
      _insertPointAt(box, local);
      return;
    }
    final unit = _toUnit(box, local);
    final double x;
    if (index == 0) {
      x = 0.0;
    } else if (index == _points.length - 1) {
      x = 1.0;
    } else {
      x = unit.dx.clamp(
        _points[index - 1].x + _minXGap,
        _points[index + 1].x - _minXGap,
      );
    }
    setState(() {
      _points[index] = BrushCurvePoint(x, unit.dy);
    });
    _publish();
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

    Offset at(BrushCurvePoint point) =>
        Offset(point.x * size.width, (1.0 - point.y) * size.height);
    if (enabled) {
      // The line joining the points, under the curve they pull — Clip
      // Studio's graph draws it, and it is what shows a point bending the
      // curve from off it (F-456).
      final polygon = Paint()
        ..color = AppColors.textDim
        ..strokeWidth = 1;
      for (final (from, to) in neighbourPairs(points)) {
        canvas.drawLine(at(from), at(to), polygon);
      }
    }

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
        final rect = Rect.fromCenter(center: at(point), width: 7, height: 7);
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

/// Preferences ▸ Input's pen response (F-480): the button at its row's end
/// wears the curve and opens the window that edits it — the button a
/// brush's curves are opened by.
///
/// 🗣️F-480 (유저 2026-10-26): 「필압곡선은 클튜처럼 그래프창으로」. ↩️It was a
/// soft↔hard bar over one exponent.
class PenResponseButton extends StatelessWidget {
  const PenResponseButton({
    super.key,
    required this.keyValue,
    required this.curve,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String keyValue;
  final BrushPressureCurve curve;

  /// See [showPenResponsePopup].
  final ValueChanged<BrushPressureCurve> onChanged;
  final ValueChanged<BrushPressureCurve> onChangeEnd;

  @override
  Widget build(BuildContext context) => SettingSourceButton(
    keyValue: keyValue,
    tooltip: AppText.strings.inputPressureCurve,
    // The straight line moves no reading, so it is the button's "off".
    active: !curve.isIdentity,
    onPressed: (anchor) => showPenResponsePopup(
      anchor,
      initialCurve: curve,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    ),
    glyph: (ink) => _MiniCurvePainter(curve: curve, color: ink),
  );
}

/// The pen response window: the window's name with its reset, and the graph
/// as wide as the window — the brush window's shell and width.
///
/// [onChanged] hears every step of a hand on the graph, [onChangeEnd] the
/// let-go and the reset: the setting follows the hand and is written down
/// once an edit is done (F-191), as the bars of the same tab are.
Future<void> showPenResponsePopup(
  BuildContext anchorContext, {
  required BrushPressureCurve initialCurve,
  required ValueChanged<BrushPressureCurve> onChanged,
  required ValueChanged<BrushPressureCurve> onChangeEnd,
}) {
  return showAnchoredPopup<void>(
    anchorContext,
    label: 'pen-response-popup',
    width: _popupWidth,
    height:
        AnchoredPopupText.bodyPadding.vertical +
        _headerHeight +
        AnchoredPopupText.titleGap +
        _innerWidth,
    builder: (context, _) => _PenResponseEditor(
      initialCurve: initialCurve,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    ),
  );
}

class _PenResponseEditor extends StatefulWidget {
  const _PenResponseEditor({
    required this.initialCurve,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final BrushPressureCurve initialCurve;
  final ValueChanged<BrushPressureCurve> onChanged;
  final ValueChanged<BrushPressureCurve> onChangeEnd;

  @override
  State<_PenResponseEditor> createState() => _PenResponseEditorState();
}

class _PenResponseEditorState extends State<_PenResponseEditor> {
  late List<BrushCurvePoint> _points = widget.initialCurve.points;

  void _reset() {
    setState(() => _points = BrushPressureCurve.linear.points);
    widget.onChangeEnd(BrushPressureCurve.linear);
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey<String>('pen-response-popup'),
    padding: AnchoredPopupText.bodyPadding,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headerHeight,
          child: AnchoredPopupHeader(
            title: AppText.strings.inputPressureCurve,
            trailing: _CurveReset(
              keyValue: 'pen-response-reset',
              onReset: _reset,
            ),
          ),
        ),
        const SizedBox(height: AnchoredPopupText.titleGap),
        SizedBox(
          height: _innerWidth,
          child: PressureCurveGraph(
            key: const ValueKey<String>('pen-response-graph'),
            points: _points,
            onChanged: (points) {
              _points = points;
              widget.onChanged(BrushPressureCurve(points));
            },
            onChangeEnd: () => widget.onChangeEnd(BrushPressureCurve(_points)),
          ),
        ),
      ],
    ),
  );
}
