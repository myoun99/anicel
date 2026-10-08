import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/transform_track.dart';
import '../../services/canvas_selection_shape.dart';
import '../../services/transform_box_law.dart';
import '../input/finger_mode_devices.dart';
import '../repaint_props.dart';
import '../theme/app_theme.dart';
import '../timeline/memo_token.dart';
import '../widgets/axis_bar_gesture.dart';
import 'box_chrome.dart';
import 'box_press.dart';
import 'canvas_viewport_offset.dart';

/// Where one grab of a row's box lands the value it drives: shown while the
/// hand moves, written once when it lets go (F-195 — the release keeps what
/// the drag showed because it is the drag's own value).
typedef RowBoxLanding<T> = ({
  ValueChanged<T> changed,
  ValueChanged<T> committed,
});

/// What a box's scale handles drive. A box offers the handles its value
/// can take (R5 #10): one scale has the corners, two have the middles of
/// the edges too.
///
/// 🗣️F-222-box-Q2 (유저 2026-10-01): 「모서리만 — 할 수 있는 것만 손잡이로」,
/// when a layer's scale was one number like the camera's zoom.
/// 🗣️F-256-Q1 (유저 2026-10-06) then chose
/// 「가른다 — AE 처럼 Scale X · Y(마이너스 = 반전)」, the option whose terms
/// were 「캔버스의 트랜스폼 상자에도 변 중앙 손잡이가 생긴다. 카메라는 줌 하나
/// 그대로」. Both stand: what a layer's value can take grew, and what a
/// camera's can take did not.
///
/// ⛔Two kinds, and not one landing with a flag beside it: a camera's zoom
/// is ONE number, and a box that could be handed two for it would have to
/// pick which to keep.
sealed class RowBoxScale {
  const RowBoxScale();
}

/// ONE scale along both axes — a camera's zoom, as its frame's own scale.
/// The corners alone, each scaling the whole box alike.
final class RowBoxOneScale extends RowBoxScale {
  const RowBoxOneScale(this.landing);

  final RowBoxLanding<double> landing;
}

/// TWO scales, across and down — a layer's. A corner scales both by ONE
/// factor, so the box keeps the proportions it has (`TransformBoxLaw
/// .scaled`'s law for a corner); an edge's middle drives its one axis.
final class RowBoxTwoScales extends RowBoxScale {
  const RowBoxTwoScales(this.landing);

  final RowBoxLanding<CanvasPoint> landing;
}

/// The EDGES themselves, where they stand on the canvas — a canvas resized
/// on the canvas (I-79). A handle moves its own edges by the hand's travel
/// and the opposite ones stay where they are: I-79-Q2 (유저 2026-10-08)
/// 「따로 안 보인다 — 끄는 변의 반대쪽이 기준」. A corner moves its two,
/// an edge's middle its one; the edges keep to whole pixels and never come
/// closer than one.
///
/// ⛔Not a scale: there is no pivot. Pulling the right edge out leaves the
/// left where it was, which a scale about any centre would not.
final class RowBoxEdges extends RowBoxScale {
  const RowBoxEdges(this.landing);

  final RowBoxLanding<Rect> landing;
}

/// A ROW's transform box on the canvas — a layer's fx transform, the
/// camera's frame, an SE name tag — under the one law every box keeps
/// (F-222): a press takes the cross, a handle, the inside, or outside on
/// stage the turn ([boxPressAt]), and the box wears the transform tool's
/// chrome in the accent ([paintBoxChrome], F-222-box-Q5).
///
/// 🗣️유저 2026-10-01: 「기본적으로 ui는 각 대응하는것으로 변환,삭제 등」 —
/// each grab drives the ONE value it names: the inside the position, a
/// handle the scale, outside the rotation, the cross the anchor point (R5
/// #10, 「잡은 것만」). A box offers what its value can take: a grab with no
/// landing is not on it ([move], [scale], [turn], [cross]).
///
/// The box turns and scales about [TransformPose.center] — where the pose
/// puts its anchor, by construction. What its handles are is its scale's
/// to say ([RowBoxScale]).
///
/// ⚠️[claimsCanvas] says whose the empty canvas is. Standing on the row, the
/// box takes every press under every tool but the two that draw an area on
/// the empty canvas (F-222-box-Q4 「선택 · 잘라내기만 빼고 모든 도구」):
/// under those it takes its cross and its corners alone, and the rest falls
/// to the tool beneath.
class RowTransformBox extends StatefulWidget {
  const RowTransformBox({
    super.key,
    required this.corners,
    required this.pose,
    required this.canvasSize,
    required this.viewport,
    required this.claimsCanvas,
    required this.onCancelled,
    this.outlined = true,
    this.move,
    this.scale,
    this.turn,
    this.turnSpace,
    this.cross,
  });

  /// The box on the CANVAS, corner by corner (top-left, top-right,
  /// bottom-right, bottom-left): the outline it draws, the corners it scales
  /// by and the inside it moves by. Empty for a box that is only its cross.
  final List<CanvasPoint> corners;

  /// The value the box stands on, as the canvas shows it — mid-drag the
  /// dragged value, handed back by the host.
  final TransformPose pose;

  final CanvasSize canvasSize;
  final CanvasViewport viewport;

  /// Every press in the viewport is the box's, rather than its handles'
  /// alone.
  final bool claimsCanvas;

  /// A grab went away with nothing to keep — what it showed is dropped.
  final VoidCallback onCancelled;

  /// Whether the box draws its own outline — the camera's frame is drawn as
  /// the camera's, and the box wears its handles on it.
  final bool outlined;

  /// The inside: the position the box moves to, in whole pixels (09-22 ⑭).
  final RowBoxLanding<CanvasPoint>? move;

  /// The handles: the scale the box reaches — 1 being the size it is drawn
  /// at unscaled — one number or two ([RowBoxScale]).
  final RowBoxScale? scale;

  /// Outside, on stage: the rotation, in clockwise degrees.
  final RowBoxLanding<double>? turn;

  /// A canvas point in the space the row's ROTATION lives in — its
  /// parent's. Null for a box whose parent is the canvas itself.
  ///
  /// A row's rotation is its own, in the space the folders above it make.
  /// Under a folder that stretches or flips, the angle a hand makes about
  /// the pivot on the canvas is not the angle the row turns by: measured on
  /// the canvas, the picture ran ahead of the hand or behind it, and inside
  /// a flipped folder it turned against it.
  ///
  /// ↩️It was measured on the canvas, which is the row's own turn while the
  /// folders above could only move, turn and scale evenly — true until a
  /// folder's scale became two numbers (F-256-Q1).
  final CanvasPoint Function(CanvasPoint onCanvas)? turnSpace;

  /// The cross: where it stands on the canvas ([at]), the point a drag
  /// carries ([value], moved by the drag's travel), and where that lands.
  ///
  /// Two points and not one: a layer's cross stands where its anchor LANDS
  /// — the centre the box turns about, After Effects' mark — while a drag
  /// carries the anchor's own VALUE, which keys alone and moves the picture
  /// (F-222-box-Q3).
  final ({
    CanvasPoint at,
    CanvasPoint value,
    RowBoxLanding<CanvasPoint> landing,
  })?
  cross;

  @override
  State<RowTransformBox> createState() => _RowTransformBoxState();
}

class _RowTransformBoxState extends State<RowTransformBox> {
  /// The grab in flight, and the pose and cross it started from — captured
  /// once: [RowTransformBox.pose] is the grabbed value mid-drag, and
  /// measuring against it would count every move twice.
  BoxPress? _grab;
  TransformPose? _start;
  CanvasPoint? _crossStart;
  Offset _press = Offset.zero;

  /// The handle a [BoxPress.handle] grab took ([_screenHandles]' index),
  /// and the box's corners on the canvas as the press found them — an
  /// edge's travel is read against the box it was grabbed on.
  int _grabbedHandle = -1;
  List<CanvasPoint> _startCorners = const [];

  /// The pointer's screen distance from the pivot at the press — a scale is
  /// the ratio of the distance now to it.
  double _pressReach = 1;

  /// The pointer's angle about the pivot at the last move, and the turn so
  /// far ([TransformBoxLaw.turn]).
  double _lastAngle = 0;
  double _turned = 0;

  /// What the last move showed, as the call that writes it — null while
  /// nothing has moved.
  VoidCallback? _commit;

  /// PEN-13: the TOUCH gate, the camera frame's rule and now every box's.
  /// A finger reaches the box only while the one-finger slot draws
  /// ([FingerModeDevices.tool]). The commitment rule mirrors the brush view
  /// (PEN-12 #4): a second finger landing while the touch drag is still
  /// SUB-SLOP converts the pair to a screen gesture (the value snaps back
  /// untouched); once committed, extra fingers are ignored and the drag
  /// lives.
  final Set<int> _touchContacts = <int>{};
  bool _touchDrag = false;
  double _touchTravel = 0;

  static const double _touchCommitSlop = 18;

  List<Offset> get _screenCorners => [
    for (final corner in widget.corners)
      widget.viewport.canvasToViewportOffset(corner),
  ];

  /// The scale handles on screen: the corners, and for a value of two
  /// scales the middles of the edges after them — top, right, bottom, left,
  /// the transform tool's own order (`TransformHandle`).
  List<Offset> get _screenHandles {
    final corners = _screenCorners;
    return switch (widget.scale) {
      null => const [],
      RowBoxOneScale() => corners,
      RowBoxTwoScales() || RowBoxEdges() => [
        ...corners,
        if (corners.length == _edgeCount)
          for (var edge = 0; edge < _edgeCount; edge += 1)
            (corners[edge] + corners[(edge + 1) % _edgeCount]) / 2,
      ],
    };
  }

  Offset? get _crossOnScreen {
    final cross = widget.cross;
    return cross == null
        ? null
        : widget.viewport.canvasToViewportOffset(cross.at);
  }

  BoxPressHit? _pressAt(Offset local) => boxPressAt(
    local,
    anchor: _crossOnScreen,
    handles: _screenHandles,
    inside: (press) =>
        widget.move != null &&
        widget.corners.length >= 3 &&
        CanvasSelectionShape(
          widget.corners,
        ).containsPoint(widget.viewport.viewportOffsetToCanvas(press)),
    onStage: (press) {
      final at = widget.viewport.viewportOffsetToCanvas(press);
      return widget.canvasSize.containsPasteboardPoint(x: at.x, y: at.y);
    },
    turns: widget.turn != null,
  );

  /// Whether a press at [local] is the box's — see
  /// [RowTransformBox.claimsCanvas].
  bool _claims(Offset local) {
    if (widget.claimsCanvas) {
      return true;
    }
    final press = _pressAt(local)?.press;
    return press == BoxPress.anchor || press == BoxPress.handle;
  }

  void _begin(DragStartDetails details) {
    final local = details.localPosition;
    final pose = widget.pose;
    _touchDrag = details.kind == PointerDeviceKind.touch;
    _touchTravel = 0;
    if (_touchDrag && _touchContacts.length > 1) {
      // Two fingers were down before the drag began: the pair is the
      // screen's, and the box takes nothing.
      _grab = null;
      return;
    }
    final hit = _pressAt(local);
    _grab = hit?.press;
    _grabbedHandle = hit?.handle ?? -1;
    _startCorners = widget.corners;
    _start = pose;
    _crossStart = widget.cross?.value;
    _press = local;
    _commit = null;
    _turned = 0;
    final pivot = widget.viewport.canvasToViewportOffset(pose.center);
    // Never zero: a press exactly on the pivot would make every ratio
    // infinite, and the box would jump to nothing on the first move.
    _pressReach = math.max((local - pivot).distance, 0.001);
    _lastAngle = TransformBoxLaw.angleAbout(
      _whereItTurns(pose.center),
      _whereItTurns(widget.viewport.viewportOffsetToCanvas(local)),
    );
  }

  /// [onCanvas] where the row's rotation is measured
  /// ([RowTransformBox.turnSpace]).
  CanvasPoint _whereItTurns(CanvasPoint onCanvas) =>
      widget.turnSpace?.call(onCanvas) ?? onCanvas;

  /// The pointer's travel since the press, on the canvas.
  CanvasPoint _travel(Offset local) => widget.viewport
      .viewportDeltaToCanvasDelta(dx: local.dx - _press.dx, dy: local.dy - _press.dy);

  void _update(DragUpdateDetails details) {
    final start = _start;
    final grab = _grab;
    if (start == null || grab == null) {
      return;
    }
    if (_touchDrag) {
      _touchTravel += details.delta.distance;
    }
    final local = details.localPosition;
    switch (grab) {
      case BoxPress.inside:
        final travel = TransformBoxLaw.wholePixels(_travel(local));
        _show(
          widget.move!,
          CanvasPoint(x: start.center.x + travel.x, y: start.center.y + travel.y),
          from: start.center,
        );
      case BoxPress.handle:
        switch (widget.scale!) {
          case RowBoxOneScale(:final landing):
            _show(
              landing,
              start.scaleX * _cornerFactor(local, start),
              from: start.scaleX,
            );
          case RowBoxTwoScales(:final landing):
            _show(landing, _twoScalesAt(local, start), from: start.scale);
          case RowBoxEdges(:final landing):
            _show(landing, _edgesAt(local), from: _startEdges);
        }
      case BoxPress.turn:
        final step = TransformBoxLaw.turn(
          centre: _whereItTurns(start.center),
          pointer: _whereItTurns(
            widget.viewport.viewportOffsetToCanvas(local),
          ),
          lastAngle: _lastAngle,
        );
        _lastAngle = step.angle;
        _turned += step.turned;
        _show(
          widget.turn!,
          start.rotationDegrees + _turned,
          from: start.rotationDegrees,
        );
      case BoxPress.anchor:
        final from = _crossStart!;
        final travel = _travel(local);
        _show(
          widget.cross!.landing,
          CanvasPoint(x: from.x + travel.x, y: from.y + travel.y),
          from: from,
        );
    }
  }

  /// A CORNER's factor: distance from the pivot scales linearly with the
  /// box, so the ratio of the hand's reach now to its reach at the press IS
  /// the scale change — no need to unproject the corner.
  ///
  /// ↩️The box wrote `max(zoom · ratio, 0.001)`: one number, held above
  /// zero because a scale had to be. A scale may be zero now
  /// (`TransformPose.scaleX`) and the ratio is never zero or infinite
  /// ([_pressReach]), so the floor went with its reason.
  double _cornerFactor(Offset local, TransformPose start) {
    final pivot = widget.viewport.canvasToViewportOffset(start.center);
    return math.max((local - pivot).distance, 0.001) / _pressReach;
  }

  /// The two scales the grabbed handle reaches.
  ///
  /// 🚨A CORNER IS ONE FACTOR FOR BOTH AXES, NOT ONE SCALE (`TransformBoxLaw
  /// .scaled`): it keeps the proportions the row has — a flip and a stretch
  /// its Scale lane or an edge made included (F-256-Q1). An EDGE's middle
  /// moves its one axis and leaves the other as it is, wherever the anchor
  /// stands.
  CanvasPoint _twoScalesAt(Offset local, TransformPose start) {
    final edge = _grabbedHandle - _edgeCount;
    if (edge < 0) {
      final factor = _cornerFactor(local, start);
      return CanvasPoint(x: start.scaleX * factor, y: start.scaleY * factor);
    }
    final factor = _edgeFactor(edge, local, start);
    return _edgeIsAcross(edge)
        ? CanvasPoint(x: start.scaleX * factor, y: start.scaleY)
        : CanvasPoint(x: start.scaleX, y: start.scaleY * factor);
  }

  /// An EDGE's factor for the one axis it drives: how far from the pivot it
  /// stands along that axis once the hand has carried it, over how far it
  /// stood at the press.
  ///
  /// Both are read in the box's OWN two sides as the canvas shows them
  /// ([_startCorners]) — so it is the row's own scale that changes, exactly,
  /// however the folders above it turn, stretch or flip the picture. Carried
  /// past the pivot the factor is a minus, which is the flip it should be
  /// (the transform tool's edges mirror the same way), and on the pivot it
  /// is zero: the row shown as nothing.
  ///
  /// The edge moves by the hand's TRAVEL, not onto the hand (F-127: a pen
  /// always moves, so a handle put under the pointer jumped on the first
  /// move).
  ///
  /// 1 — nothing to change — for an edge that stands ON the pivot's line
  /// (it has no distance to take a ratio of) and for a box shown as
  /// nothing, whose sides span no plane.
  double _edgeFactor(int edge, Offset local, TransformPose start) {
    final corners = _startCorners;
    final across = _from(corners[0], corners[1]);
    final down = _from(corners[0], corners[3]);
    final handle = CanvasPoint.lerp(
      corners[edge],
      corners[(edge + 1) % _edgeCount],
      0.5,
    );
    final stood = _alongSides(_from(start.center, handle), across, down);
    final carried = _alongSides(_travel(local), across, down);
    if (stood == null || carried == null) {
      return 1;
    }
    final (from, by) = _edgeIsAcross(edge)
        ? (stood.across, carried.across)
        : (stood.down, carried.down);
    return from == 0 ? 1 : (from + by) / from;
  }

  /// The box's edges as the press found them: its corners' bounds on the
  /// canvas.
  Rect get _startEdges => Rect.fromLTRB(
    _startCorners[0].x,
    _startCorners[0].y,
    _startCorners[2].x,
    _startCorners[2].y,
  );

  /// The edges the grabbed handle has carried ([RowBoxEdges]): its own by
  /// the hand's travel in whole pixels (F-127: by the travel, not onto the
  /// hand), the others where they were.
  Rect _edgesAt(Offset local) {
    final travel = TransformBoxLaw.wholePixels(_travel(local));
    final start = _startEdges;
    final handle = _grabbedHandle;
    // Corners first (top-left, top-right, bottom-right, bottom-left), then
    // the middles of the edges (top, right, bottom, left).
    final left = handle == 0 || handle == 3 || handle == 7;
    final right = handle == 1 || handle == 2 || handle == 5;
    final top = handle == 0 || handle == 1 || handle == 4;
    final bottom = handle == 2 || handle == 3 || handle == 6;
    return Rect.fromLTRB(
      left ? math.min(start.left + travel.x, start.right - 1) : start.left,
      top ? math.min(start.top + travel.y, start.bottom - 1) : start.top,
      right ? math.max(start.right + travel.x, start.left + 1) : start.right,
      bottom ? math.max(start.bottom + travel.y, start.top + 1) : start.bottom,
    );
  }

  /// Shows [value] on [landing] — and keeps the call that writes it, unless
  /// the hand is back where it started.
  void _show<T>(RowBoxLanding<T> landing, T value, {required T from}) {
    landing.changed(value);
    _commit = value == from ? null : () => landing.committed(value);
  }

  void _end() {
    final grabbed = _grab != null;
    final commit = _commit;
    _grab = null;
    _start = null;
    _commit = null;
    if (commit != null) {
      commit();
    } else if (grabbed) {
      widget.onCancelled();
    }
  }

  void _cancel() {
    final grabbed = _grab != null;
    _grab = null;
    _start = null;
    _commit = null;
    if (grabbed) {
      widget.onCancelled();
    }
  }

  /// A second finger landing during a SUB-SLOP touch drag: the pair is a
  /// screen gesture — the value snaps back untouched.
  void _fingerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    _touchContacts.add(event.pointer);
    if (_touchContacts.length >= 2 &&
        _touchDrag &&
        _grab != null &&
        _touchTravel < _touchCommitSlop) {
      _cancel();
    }
  }

  void _fingerGone(int pointer) => _touchContacts.remove(pointer);

  @override
  void dispose() {
    // A box taken away mid-grab never sees its release: what it was showing
    // is dropped once the tree settles — a notifier fired while the tree is
    // being torn down would be too soon.
    if (_grab != null) {
      final cancel = widget.onCancelled;
      WidgetsBinding.instance.addPostFrameCallback((_) => cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final corners = _screenCorners;
    return _BoxPressArea(
      claims: _claims,
      // PEN-13: raw contact tracking for the touch gate — the pan callbacks
      // alone cannot see the finger count.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _fingerDown,
        onPointerUp: (event) => _fingerGone(event.pointer),
        onPointerCancel: (event) => _fingerGone(event.pointer),
        // TS9: a finger drives the box only while the one-finger slot draws
        // — stated as devices, so the recognizer stays out of the arena and
        // the screen gestures take the touch ([AppInput.toolPointerDevices]).
        child: FingerModeDevices.tool(
          builder: (context, devices) => RawGestureDetector(
            key: const ValueKey<String>('row-transform-box'),
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              _BoxPanGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _BoxPanGestureRecognizer
                  >(() => _BoxPanGestureRecognizer(debugOwner: this), (
                    recognizer,
                  ) {
                    recognizer.supportedDevices = devices;
                    // A LATE touch never joins the pan (the default
                    // latest-pointer strategy would hand the drag to the
                    // idle newcomer, freezing the box mid-drag) — the
                    // finger that started the drag keeps driving it.
                    recognizer.extraTouchRejected = (event) =>
                        event.kind == PointerDeviceKind.touch &&
                        _touchContacts.isNotEmpty;
                    recognizer.gestureSettings =
                        MediaQuery.maybeGestureSettingsOf(context);
                    // The handles are small: the press is decided where the
                    // pointer went DOWN, not where the drag was accepted.
                    recognizer.dragStartBehavior = DragStartBehavior.down;
                    recognizer.onStart = _begin;
                    recognizer.onUpdate = _update;
                    recognizer.onEnd = (_) => _end();
                    recognizer.onCancel = _cancel;
                  }),
            },
            child: CustomPaint(
              painter: _RowBoxPainter(
                chrome: (
                  box: widget.outlined ? corners : const [],
                  handles: _screenHandles,
                  anchor: _crossOnScreen,
                ),
                color: AppColors.accent,
              ),
              // A bare CustomPaint sizes to zero under loose constraints;
              // the box must cover (and hit-test across) the whole viewport.
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// A box has four edges, and their middles are listed after its four
/// corners: top, right, bottom, left.
const int _edgeCount = 4;

/// Whether [edge] — top, right, bottom, left — drives the scale ACROSS: the
/// right and the left do, the top and the bottom drive the scale down.
bool _edgeIsAcross(int edge) => edge.isOdd;

CanvasPoint _from(CanvasPoint a, CanvasPoint b) =>
    CanvasPoint(x: b.x - a.x, y: b.y - a.y);

/// [vector] as so much of [across] and so much of [down] — null when the
/// two sides span no plane.
({double across, double down})? _alongSides(
  CanvasPoint vector,
  CanvasPoint across,
  CanvasPoint down,
) {
  final area = across.x * down.y - across.y * down.x;
  if (area == 0) {
    return null;
  }
  return (
    across: (vector.x * down.y - vector.y * down.x) / area,
    down: (across.x * vector.y - across.y * vector.x) / area,
  );
}

/// PEN-13: the box's pan never hands its drag to a late finger —
/// [extraTouchRejected] filters newcomers at the arena door, so the finger
/// that started the drag keeps driving it (committed drags survive palm
/// rests; the box's Listener handles the sub-slop abort separately).
///
/// 🗣️F-194 (유저 2026-09-27, Android): 「카메라 레이어 조작하려고 스타일러스
/// 펜으로 캔버스에서 실루엣 꼭짓점같은거 이동하려니 조작안됨」. H24: the
/// canvas under this takes the arena on the FIRST movement, and a stock pan
/// waits for its slop — 2px for a mouse, so the mouse won, and 36px for a
/// pen or a finger, so they never did. It takes the arena on the first
/// movement too, deeper, so it is asked first ([OwningPanGestureRecognizer]).
///
/// ⚠️Nothing is lost by the win: the canvas's flip and pan read raw
/// pointers, which no arena takes away.
class _BoxPanGestureRecognizer extends OwningPanGestureRecognizer {
  _BoxPanGestureRecognizer({super.debugOwner});

  bool Function(PointerDownEvent event)? extraTouchRejected;

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event is PointerDownEvent &&
        (extraTouchRejected?.call(event) ?? false)) {
      return false;
    }
    return super.isPointerAllowed(event);
  }
}

/// A hit test that answers only where [claims] says the press is the box's
/// — so a press it does not claim falls to the tool beneath.
class _BoxPressArea extends SingleChildRenderObjectWidget {
  const _BoxPressArea({required this.claims, super.child});

  final bool Function(Offset local) claims;

  @override
  _RenderBoxPressArea createRenderObject(BuildContext context) =>
      _RenderBoxPressArea(claims);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBoxPressArea renderObject,
  ) {
    renderObject.claims = claims;
  }
}

class _RenderBoxPressArea extends RenderProxyBox {
  _RenderBoxPressArea(this.claims);

  bool Function(Offset local) claims;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      size.contains(position) &&
      claims(position) &&
      super.hitTest(result, position: position);
}

class _RowBoxPainter extends CustomPainter with RepaintOnProps {
  const _RowBoxPainter({required this.chrome, required this.color});

  final SelectionTransformChrome chrome;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintBoxChrome(canvas, chrome, color: color);
  }

  @override
  Object get props => (
    color,
    chrome.anchor,
    ByList(chrome.box),
    ByList(chrome.handles),
  );
}
