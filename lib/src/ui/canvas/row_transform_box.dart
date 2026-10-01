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

/// A ROW's transform box on the canvas — a layer's fx transform, the
/// camera's frame, an SE name tag — under the one law every box keeps
/// (F-222): a press takes the cross, a corner, the inside, or outside on
/// stage the turn ([boxPressAt]), and the box wears the transform tool's
/// chrome in the accent ([paintBoxChrome], F-222-box-Q5).
///
/// 🗣️유저 2026-10-01: 「기본적으로 ui는 각 대응하는것으로 변환,삭제 등」 —
/// each grab drives the ONE value it names: the inside the position, a corner
/// the scale, outside the rotation, the cross the anchor point (R5 #10,
/// 「잡은 것만」). A box offers what its value can take: a grab with no
/// landing is not on it ([move], [scale], [turn], [cross]).
///
/// The box turns and scales about [TransformPose.center] — where the pose
/// puts its anchor, by construction — and a corner scales the whole box
/// alike, because the value it drives is one number (F-222-box-Q2 「모서리만
/// — 할 수 있는 것만 손잡이로」).
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

  /// A corner: the scale the box reaches, 1 being the size it is drawn at
  /// [TransformPose.zoom] 1.
  final RowBoxLanding<double>? scale;

  /// Outside, on stage: the rotation, in clockwise degrees.
  final RowBoxLanding<double>? turn;

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

  Offset? get _crossOnScreen {
    final cross = widget.cross;
    return cross == null
        ? null
        : widget.viewport.canvasToViewportOffset(cross.at);
  }

  BoxPressHit? _pressAt(Offset local) => boxPressAt(
    local,
    anchor: _crossOnScreen,
    handles: widget.scale == null ? const [] : _screenCorners,
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
    _grab = _pressAt(local)?.press;
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
      pose.center,
      widget.viewport.viewportOffsetToCanvas(local),
    );
  }

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
        // Distance from the pivot scales linearly with the box, so the
        // ratio IS the scale change — no need to unproject the corner.
        final pivot = widget.viewport.canvasToViewportOffset(start.center);
        final ratio = math.max((local - pivot).distance, 0.001) / _pressReach;
        _show(
          widget.scale!,
          math.max(start.zoom * ratio, 0.001),
          from: start.zoom,
        );
      case BoxPress.turn:
        final step = TransformBoxLaw.turn(
          centre: start.center,
          pointer: widget.viewport.viewportOffsetToCanvas(local),
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
                  handles: widget.scale == null ? const [] : corners,
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
