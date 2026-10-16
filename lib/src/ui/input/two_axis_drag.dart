import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../services/input/pen_sidecars.dart';
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
class TwoAxisDrag extends StatelessWidget {
  const TwoAxisDrag({super.key, required this.axes, required this.child});

  /// The sheet's two axes.
  final List<TwoAxisScrollController> axes;

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

/// The scroll controller of one axis of a sheet a [TwoAxisDrag] drags.
///
/// ⛔Its scroller takes no drag of its own, so the sheet's one drag is the
/// only one there is and nothing races it. ONLY the drag: the wheel, the
/// scrollbar, a key and the code move it as before. `Scrollable` asks its
/// position whether to build its drag recognisers (`setCanDrag`), and that
/// is the one question answered differently here.
class TwoAxisScrollController extends PenFriendlyScrollController {
  TwoAxisScrollController({super.initialScrollOffset});

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

  /// The latest press — what it landed on is asked when the drag is first
  /// told of it ([_down]), which a press after the first is not.
  PointerEvent? _press;

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
    } else if (event is PointerPanZoomUpdateEvent) {
      _moved += event.panDelta;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final slop = computeHitSlop(
      PenSidecars.kindOf(pointerDeviceKind),
      gestureSettings,
    );
    // The sheet keeps a pull wherever on it the pull lands while any of it
    // can move — one on the layer area included, when only the frames can
    // (F-202: 「안에서 동작하는 스크롤이나 드래그는 절대 밖으로 안새게」).
    return (_drives.isNotEmpty || _stilled.isNotEmpty || _slide != null) &&
        (_moved.dx.abs() > slop || _moved.dy.abs() > slop);
  }

  void _start(DragStartDetails details) {
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
  }
}
