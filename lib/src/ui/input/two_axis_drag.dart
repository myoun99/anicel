import 'dart:ui' show SemanticsAction;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../models/app_input_settings.dart'
    show AppInput, CanvasTouchDragAction;
import '../../models/project_frame_rate.dart';
import '../../services/input/pen_sidecars.dart';
import '../timeline/timeline_zoom_limits.dart';
import 'pan_slide.dart';
import 'pen_friendly_scroll_controller.dart';
import 'scroller_drive.dart';

/// 🚨★★A SHEET SCROLLED TWO WAYS IS DRAGGED BOTH WAYS AT ONCE — the
/// timeline's rows and frames, the x-sheet's layers and frames, the conte
/// panel's rows and strip.
///
/// 🗣️F-351 (유저 2026-10-12): 「스페이스바로 타임라인쪽 조작하면 가로/세로
/// 스크롤 통합해서 캔버스 조작하듯이 팬 되는데, 법 통일해서 터치로 해당영역
/// 조작시에도 가로/세로 같이 하도록」.
///
/// Each axis was its own scroller with its own drag, one inside the other,
/// and a drag went to whichever axis the hand moved along first: a finger
/// moved a sheet one way, where Space ([PanelPanDriver]) moves it both. So
/// the axes take no drag of their own ([TwoAxisScrollController]) and this
/// takes it for them — ONE drag, each axis moved by its own part of every
/// movement and flung by its own part of the release. It is Flutter's own
/// two-dimensional scroll (`DiagonalDragBehavior.free`), on the scrollers
/// the sheets already have.
///
/// ⛔It asks what the axes' own drags asked, so nothing else on a sheet
/// changes hands:
///  * the devices are the panel's — a finger count set to 「없음」 still
///    moves nothing ([PanelPanDriver]);
///  * the distance is each axis's own, on the device's slop — the drag
///    starts where either axis's would have;
///  * an axis that cannot scroll takes nothing, as its scroller took no
///    drag, and a sheet that cannot scroll either way takes no drag at all;
///  * a control, an edit drag or a list on the sheet is offered the press
///    before this and answers first, as it did before.
///
/// 🚨One drag, but not always the same two axes: a pull that starts on the
/// layer area moves the layer area — the layers, and the area's own window
/// in place of the frames ([PanSlide], F-351: 「레이어쪽을 잡으면
/// 레이어영역이 팬 작동하도록」).
///
/// ⚠️A pull along an axis that cannot scroll is still the sheet's while the
/// other axis can — the axes' own drags kept it with the press hold, and a
/// scroller around the sheet is never handed it (F-202: 「안에서 동작하는
/// 스크롤이나 드래그는 절대 밖으로 안새게」).
///
/// 🗣️F-506 (유저 2026-10-29): 「타임라인 프레임영역. 두손가락 터치로
/// 타임라인줌변경도 가능하게」. Fingers do on a sheet what the canvas's own
/// setting for that many fingers says (R26 #34, [PanelPanDriver]); where
/// it says 「내비게이트」 — the canvas's pan AND zoom — the fingers zoom the
/// frame axis ([zoom]) by how far they spread, and their middle moves the
/// sheet as one finger's pull would. A pinch that starts on the layer area
/// moves the layer area alone, as a pull there does.
///
/// ⛔Fingers that land TOGETHER are one gesture, the canvas's law (PEN-12
/// #4): the second finger takes the first from an edit drag that has not
/// started yet (결정 10 — one finger is the drawing hand), and a drag that
/// HAS started keeps its finger, as a committed stroke does.
class TwoAxisDrag extends StatelessWidget {
  const TwoAxisDrag({
    super.key,
    required this.axes,
    this.zoom,
    required this.child,
  });

  /// The sheet's two axes.
  final List<TwoAxisScrollController> axes;

  /// What a pinch zooms — null where the sheet's panel names no zoom
  /// writer.
  final SheetZoom? zoom;

  /// The sheet: the outer of its two scrollers, with the inner inside it.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _SheetDrag: GestureRecognizerFactoryWithHandlers<_SheetDrag>(
          _SheetDrag.new,
          (drag) => drag
            ..axes = axes
            ..zoom = zoom
            ..supportedDevices = behavior.dragDevices
            ..velocityTrackerBuilder = behavior.velocityTrackerBuilder(context)
            ..multitouchDragStrategy = behavior.getMultitouchDragStrategy(
              context,
            )
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
        ),
      },
      child: child,
    );
  }
}

/// What a pinch on a sheet zooms (F-506): the zoom its frame axis is laid
/// out at, the rate of the project its steps are counted for, and the
/// writer every zoom control of its panel writes through — each zoom on a
/// step inside the range ([TimelineZoomLimits.clamped]), as the readout's.
typedef SheetZoom = ({
  double pixelsPerFrame,
  int framesPerSecond,
  ValueChanged<double> onChanged,
});

/// The [SheetZoom] of a sheet laid out at [pixelsPerFrame] for a project of
/// [rate], written through [onChanged] — none without a writer.
SheetZoom? sheetZoom(
  double pixelsPerFrame,
  ProjectFrameRate rate,
  ValueChanged<double>? onChanged,
) => switch (onChanged) {
  final onChanged? => (
    pixelsPerFrame: pixelsPerFrame,
    framesPerSecond: rate.countingBase,
    onChanged: onChanged,
  ),
  null => null,
};

/// The scroll controller of one axis of a sheet a [TwoAxisDrag] drags.
///
/// ⛔Its scroller takes no drag of its own, so the sheet's one drag is the
/// only one there is and nothing races it. ONLY the drag: the wheel, the
/// scrollbar, a key and the code move it as before. `Scrollable` asks its
/// position whether to build its drag recognisers (`setCanDrag`), and that
/// is the one question answered differently here.
class TwoAxisScrollController extends PenFriendlyScrollController {
  TwoAxisScrollController({this.bornAt});

  /// The axis the sheet's host keeps, which every position this controller
  /// makes is born at ([initialScrollOffset]) — read as it is made.
  ///
  /// 🚨Not at zero (F-143): a grid is built afresh while the axis it shares
  /// stands elsewhere — brought forward again, switched in orientation —
  /// and a newborn 0 was read back after layout and recorded as a scroll.
  /// And not where it stood when the controller was made: the storyboard
  /// keeps its State through a fold and builds its body again on the
  /// controllers it had (유저 2026-10-14: 「열려있을때만 지어지는게
  /// 맞는구조」), while the folded row turned the axis.
  final ValueListenable<double>? bornAt;

  @override
  double get initialScrollOffset => bornAt?.value ?? 0;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => super.createScrollPosition(
    physics,
    _withoutItsOwnDrag[context] ??= _NoDragOfItsOwn(context),
    oldPosition,
  );
}

/// ONE per scroller: a position the scroller makes again takes over the one
/// before it only from the same context (`ScrollPosition.absorb`).
final Expando<ScrollContext> _withoutItsOwnDrag = Expando<ScrollContext>(
  'F-351 no drag of its own',
);

class _NoDragOfItsOwn implements ScrollContext {
  _NoDragOfItsOwn(this._scroller);

  final ScrollContext _scroller;

  @override
  void setCanDrag(bool value) => _scroller.setCanDrag(false);

  @override
  BuildContext? get notificationContext => _scroller.notificationContext;

  @override
  BuildContext get storageContext => _scroller.storageContext;

  @override
  TickerProvider get vsync => _scroller.vsync;

  @override
  AxisDirection get axisDirection => _scroller.axisDirection;

  @override
  double get devicePixelRatio => _scroller.devicePixelRatio;

  @override
  void setIgnorePointer(bool value) => _scroller.setIgnorePointer(value);

  @override
  void setSemanticsActions(Set<SemanticsAction> actions) =>
      _scroller.setSemanticsActions(actions);

  @override
  void saveOffset(double offset) => _scroller.saveOffset(offset);
}

/// The sheet's one drag: a pan that starts where either axis's own drag
/// would have, and moves every axis that can scroll by its own part.
class _SheetDrag extends PanGestureRecognizer {
  _SheetDrag() {
    onDown = _down;
    onStart = _start;
    onUpdate = _update;
    onEnd = _end;
    onCancel = _cancel;
  }

  List<TwoAxisScrollController> axes = const [];

  /// What a pinch zooms ([TwoAxisDrag.zoom]).
  SheetZoom? zoom;

  /// The latest press — what it landed on is asked when the drag is first
  /// told of it ([_down]), which a press after the first is not.
  PointerEvent? _press;

  /// Where each finger the drag holds stands now.
  final Map<int, Offset> _fingers = {};

  /// The pinch that holds the sheet, from the finger that makes one until
  /// the last lifts (F-506): the zoom and the spread of the fingers when the
  /// last of them landed or lifted, and where their middle stood last.
  ({double zoom, double spread, Offset middle})? _pinch;

  /// The zoom the pinch wrote last — the sheet is built at it a frame on.
  double? _zoomed;

  /// Whether the press landed on the frames — not on a part that slides by
  /// itself ([PanSlide]), the layer area, where fingers pull as one does.
  bool _onTheFrames = true;

  /// The axes that could scroll when the press landed — the ones whose
  /// scroller would have taken it — that the pull moves.
  List<ScrollerDrive> _drives = const [];

  /// The ones it does not: along what the press landed on, when that slides
  /// ([panMoves]). The press still stops them, as a press anywhere on the
  /// sheet does.
  List<ScrollerDrive> _stilled = const [];

  /// What the press landed on, when it can slide — moved in place of the
  /// axis it slides along.
  PanSlide? _slide;

  /// How far the hand has gone along each axis, counted the way each axis's
  /// own drag counted it.
  Offset _moved = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _press = event;
    super.addAllowedPointer(event);
    if (event.kind == PointerDeviceKind.touch) {
      _fingers[event.pointer] = event.position;
      _regrip();
    }
  }

  /// A finger lifted, or went to another gesture: the pinch takes hold of
  /// those left — once the drag has heard it, which lets go of the sheet
  /// when it was the last.
  @override
  void stopTrackingPointer(int pointer) {
    super.stopTrackingPointer(pointer);
    if (_fingers.remove(pointer) != null) {
      _regrip();
    }
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _press = event;
    super.addAllowedPointerPanZoom(event);
  }

  void _down(DragDownDetails details) {
    _moved = Offset.zero;
    final scrollers = [
      for (final axis in axes)
        for (final position in axis.positions)
          if (position.hasContentDimensions &&
              position.physics.shouldAcceptUserOffset(position))
            ScrollerDrive(position)..hold(),
    ];
    // Asked once the press has stopped the sheet: while it coasts, what it
    // shows is out of the hit test (PEN-9).
    final press = _press;
    final slide = press == null ? null : panSlideUnder(press);
    _slide = slide != null && slide.canSlide ? slide : null;
    _onTheFrames = slide == null;
    _drives = [
      for (final drive in scrollers)
        if (panMoves(drive.position, slide)) drive,
    ];
    _stilled = [
      for (final drive in scrollers)
        if (!panMoves(drive.position, slide)) drive,
    ];
    if (scrollers.isNotEmpty) {
      final physics = scrollers.first.position.physics;
      minFlingDistance = physics.minFlingDistance;
      minFlingVelocity = physics.minFlingVelocity;
      maxFlingVelocity = physics.maxFlingVelocity;
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _moved += event.delta;
      if (_fingers.containsKey(event.pointer)) {
        _fingers[event.pointer] = event.position;
        if (_pinch != null) {
          _pinchStep();
        }
      }
    } else if (event is PointerPanZoomUpdateEvent) {
      _moved += event.panDelta;
    }
    super.handleEvent(event);
  }

  /// Whether the fingers down pinch: two or more on the frames, set on the
  /// canvas to 「내비게이트」 — its pan and zoom, which coasts on neither.
  bool get _pinches =>
      _fingers.length > 1 &&
      _onTheFrames &&
      AppInput.touchDragActionFor(_fingers.length) ==
          CanvasTouchDragAction.navigate;

  /// The fingers changed: a pinch under way takes hold again where they
  /// stand — or one begins where they pinch ([_pinches]), taking every
  /// finger's arena for the sheet: none of them edits, none drags a scroller.
  void _regrip() {
    if (_pinch == null && !_pinches) {
      return;
    }
    final begins = _pinch == null;
    final fingers = _fingers.values;
    _pinch = (
      zoom: _zoomed ?? zoom?.pixelsPerFrame ?? 0,
      spread: _spreadOf(fingers),
      middle: _middleOf(fingers),
    );
    if (begins) {
      for (final drive in [..._drives, ..._stilled]) {
        drive.cancel();
      }
      resolve(GestureDisposition.accepted);
    }
  }

  /// The fingers moved: their middle moves the sheet with the hand and,
  /// while they pinch, they zoom it by how far they spread since they took
  /// hold.
  void _pinchStep() {
    final grip = _pinch!;
    final fingers = _fingers.values;
    final middle = _middleOf(fingers);
    _pinch = (zoom: grip.zoom, spread: grip.spread, middle: middle);
    for (final axis in axes) {
      for (final position in axis.positions) {
        scrollWithHand(position, middle - grip.middle);
      }
    }
    final sheet = zoom;
    if (sheet == null || !_pinches || grip.spread == 0) {
      return;
    }
    final to = TimelineZoomLimits.clamped(
      grip.zoom * _spreadOf(fingers) / grip.spread,
      framesPerSecond: sheet.framesPerSecond,
    );
    _zoomed = to;
    sheet.onChanged(to);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final slop = PenSidecars.hitSlopOf(pointerDeviceKind, gestureSettings);
    // The sheet keeps a pull wherever on it the pull lands while any of it
    // can move — one on the layer area included, when only the frames can
    // (F-202: 「안에서 동작하는 스크롤이나 드래그는 절대 밖으로 안새게」).
    return (_drives.isNotEmpty || _stilled.isNotEmpty || _slide != null) &&
        (_moved.dx.abs() > slop || _moved.dy.abs() > slop);
  }

  void _start(DragStartDetails details) {
    if (_pinch != null) {
      return;
    }
    for (final drive in _drives) {
      drive.start(details);
    }
  }

  void _update(DragUpdateDetails details) {
    for (final drive in _drives) {
      drive.update(details);
    }
    _slide?.slideWithHand(details.delta);
  }

  void _end(DragEndDetails details) {
    for (final drive in _drives) {
      drive.end(details);
    }
    _letGo();
  }

  void _cancel() {
    for (final drive in _drives) {
      drive.cancel();
    }
    _letGo();
  }

  void _letGo() {
    for (final drive in _stilled) {
      drive.cancel();
    }
    _drives = const [];
    _stilled = const [];
    _slide = null;
    _pinch = null;
    _zoomed = null;
  }
}

/// The point between [fingers].
Offset _middleOf(Iterable<Offset> fingers) =>
    fingers.fold(Offset.zero, (sum, finger) => sum + finger) /
    fingers.length.toDouble();

/// How far [fingers] stand from the point between them, on average — what
/// a pinch zooms by as it changes.
double _spreadOf(Iterable<Offset> fingers) {
  final middle = _middleOf(fingers);
  return fingers.fold(0.0, (sum, finger) => sum + (finger - middle).distance) /
      fingers.length;
}
