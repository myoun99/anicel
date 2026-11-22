import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'still_raster.dart' show TickSceneLayer;

/// WHERE WHAT A POINTER LIGHTS IS DRAWN — two layers, one under what
/// [child] holds and one over it, each drawn live between a still region's
/// strata and never in them ([TickSceneLayer.alwaysLive]). What stands in
/// [child] lays its looks on them ([LaidLook]) — a face its hover, its
/// press and its focus UNDER its glyph, a grip its band OVER what it
/// lifts — and the region around them keeps its image.
///
/// 🚨WHY (card the-left-tool-strip-rebakes-on-every-hover, 2026-11-22): a
/// face painted its state layer in its own picture, so a pointer passing
/// over a button changed the picture of everything painted with it — and
/// the still region around it let its image go and took it again
/// ([StillRaster]). 🔬A pointer passing down the left tool strip took the
/// strip's image eleven times in 1.1 s (the real app, 144 Hz, the
/// timeline's probe run of 11-22; the same eleven for ten buttons in
/// `a_hover_keeps_its_regions_image_test`). What follows a pointer is not a
/// still region's to hold — the tool cursor's law (F-428, 「펜으로 호버해서
/// 움직이면 그쪽 칸 라인만 진해졌다 연해졌다 반복함」) and a hovered panel
/// tab's (`EditorPanelTabs`, 10-24), said for every light face.
///
/// ⛔Not the region's content on a tick layer, as the panel tabs' strip is:
/// a tick is drawn live WHOLE, and a tool strip drawn live is what F-533
/// took out of every frame. ⛔Not a layer a face: a face new to the pointer
/// is a layer the strata were not cut at, and they are taken again. ⛔Not
/// one layer: a band lies over what it lifts — the colour pair, under the
/// band of its button — and a hover under what it lights.
///
/// ⚠️IT STANDS ON THE GROUND ITS FACES STAND ON: a look laid under is drawn
/// under ALL [child] paints, one laid over, over all of it. So nothing
/// opaque may lie between the sheet and a face that lays a look under —
/// the tool strips' ground is their dock's, painted around the region —
/// and what something is painted over in place stands aside
/// ([LiveSheet.inPlace]). ⏳The canvas capsules and the dock panels paint
/// their ground in their own region, and stand on none yet (card
/// a-hover-in-a-capsule-or-a-dock-takes-the-regions-image-again).
///
/// ⚠️WHAT A LOOK KEEPS OF ITS BOX: where it stands, how large, and the
/// clips it is painted in. Not what is laid over the box's picture as a
/// layer — an opacity, a filter: a box under one stands aside too (none
/// does on the strips, `a_pointer_passing_over_a_strip_takes_no_image_test`).
class LiveSheet extends StatefulWidget {
  const LiveSheet({super.key, required this.child});

  final Widget child;

  /// [child] with what it holds painting its looks in place, as where no
  /// sheet is — what a ground of its own is painted under, or a mark over,
  /// in the order they are painted in.
  static Widget inPlace({required Widget child}) =>
      _LiveSheetScope(under: null, over: null, child: child);

  /// The looks laid under what the sheet [context] is built over holds, or
  /// null where it is built over none.
  static LiveLooks? underOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiveSheetScope>()?.under;

  /// The looks laid over it ([underOf]).
  static LiveLooks? overOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiveSheetScope>()?.over;

  @override
  State<LiveSheet> createState() => _LiveSheetState();
}

class _LiveSheetState extends State<LiveSheet> {
  final LiveLooks _under = LiveLooks._();
  final LiveLooks _over = LiveLooks._();

  @override
  void dispose() {
    _under.dispose();
    _over.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      // A scroll moves what stands in it with no word to its boxes: the
      // looks laid are drawn again where their boxes stand now, in the
      // scroll's own frame.
      NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _under.moved();
          _over.moved();
          return false;
        },
        child: _Host(
          looks: [_under, _over],
          child: Stack(
            // The child's own box: the sheet takes no part in its layout.
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(child: _Sheet(_under)),
              _LiveSheetScope(under: _under, over: _over, child: widget.child),
              Positioned.fill(child: _Sheet(_over)),
            ],
          ),
        ),
      );
}

/// What the sheet's layers lie in, with what they lie under and over — the
/// box a look's place is read in.
class _Host extends SingleChildRenderObjectWidget {
  const _Host({required this.looks, required super.child});

  final List<LiveLooks> looks;

  @override
  _RenderHost createRenderObject(BuildContext context) => _RenderHost(looks);
}

class _RenderHost extends RenderProxyBox {
  _RenderHost(this._looks);

  final List<LiveLooks> _looks;

  // In the tree before anything it holds: a box that comes into the tree
  // under it finds it there ([LiveLooks._holds]).
  @override
  void attach(PipelineOwner owner) {
    for (final looks in _looks) {
      looks._host = this;
    }
    super.attach(owner);
  }

  @override
  void detach() {
    super.detach();
    for (final looks in _looks) {
      looks._host = null;
    }
  }
}

class _LiveSheetScope extends InheritedWidget {
  const _LiveSheetScope({
    required this.under,
    required this.over,
    required super.child,
  });

  final LiveLooks? under;
  final LiveLooks? over;

  @override
  bool updateShouldNotify(_LiveSheetScope oldWidget) =>
      !identical(oldWidget.under, under) || !identical(oldWidget.over, over);
}

/// THE LOOKS LAID ON ONE LAYER OF A SHEET ([LiveSheet]) — each box's own,
/// painted where that box stands, in the order they were laid.
final class LiveLooks extends ChangeNotifier {
  LiveLooks._();

  final Map<RenderBox, void Function(Canvas canvas)> _laid =
      <RenderBox, void Function(Canvas canvas)>{};

  /// The sheet's host, while it is in the tree.
  _RenderHost? _host;

  /// How many looks are laid — for tests.
  @visibleForTesting
  int get debugLaid => _laid.length;

  /// Whether [box] stands in what the sheet lies under and over in the
  /// render tree too. A thing built there and drawn elsewhere — an
  /// overlay's — does not, and paints its own look.
  bool _holds(RenderObject box) {
    final host = _host;
    if (host == null) {
      return false;
    }
    for (var above = box.parent; above != null; above = above.parent) {
      if (identical(above, host)) {
        return true;
      }
    }
    return false;
  }

  void _lay(RenderBox box, void Function(Canvas canvas) look) {
    _laid[box] = look;
    notifyListeners();
  }

  void _lift(RenderBox box) {
    if (_laid.remove(box) != null) {
      notifyListeners();
    }
  }

  /// What stands in the sheet may have moved, in this frame.
  void moved() {
    if (_laid.isNotEmpty) {
      notifyListeners();
    }
  }
}

/// WHAT A BOX LAYS ON A SHEET — one look of [L], drawn live there where
/// the box stands, in the box's own coordinates ([LiveSheet]). Where no
/// sheet is under the box it lays nothing, and the box paints its look in
/// its own picture ([onSheet]).
///
/// 🚨THE BOX SAYS WHAT ITS LOOK IS, AND THIS ASKS: as the box says it may
/// be another ([changed]), as the box comes into the tree, and as it comes
/// to stand over another layer. ↩️Each box laid its look again after those
/// two itself until 2026-11-22, and a face did not — one that came to a
/// sheet with the keyboard's focus on it showed that focus in no picture
/// (`live_sheet_test`, a face moved onto a sheet).
///
/// One code for both that lay one: a light face's state layer
/// (`PressFace`) and a grip's band (`LiftingGripBand`).
final class LaidLook<L extends Object> {
  LaidLook(this._box, this._look, this._paint);

  final RenderBox _box;

  /// What the box's look is now — null where it shows none.
  final L? Function() _look;

  /// Paints a look in the box's own coordinates.
  final void Function(Canvas canvas, L look) _paint;

  LiveLooks? _looks;
  bool _onSheet = false;
  L? _laid;

  /// Whether the sheet draws the box's look, and the box paints none.
  bool get onSheet => _onSheet;

  /// The layer the box is built over, as its widget reads it building the
  /// box and building it again ([LiveSheet.underOf], [LiveSheet.overOf]).
  void wear(LiveLooks? looks) {
    if (identical(looks, _looks)) {
      return;
    }
    _liftIt();
    _looks = looks;
    if (_box.attached) {
      attached();
    }
  }

  /// The box came into the tree.
  void attached() {
    final onSheet = _looks?._holds(_box) ?? false;
    if (onSheet != _onSheet) {
      _onSheet = onSheet;
      _box.markNeedsPaint();
    }
    changed();
  }

  /// The box left the tree.
  void detached() {
    _liftIt();
    _onSheet = false;
  }

  /// The box's look may be another now. Equal looks are one look: said
  /// again, nothing is drawn again.
  void changed() {
    final shown = _onSheet ? _look() : null;
    if (shown == _laid) {
      return;
    }
    _laid = shown;
    if (shown == null) {
      _looks?._lift(_box);
    } else {
      _looks!._lay(_box, _draw);
    }
  }

  void _draw(Canvas canvas) {
    if (_laid case final look?) {
      _paint(canvas, look);
    }
  }

  void _liftIt() {
    if (_laid != null) {
      _laid = null;
      _looks?._lift(_box);
    }
  }
}

/// Where a box stands in the sheet's host, and how large.
typedef _Place = ({Matrix4 at, Size size});

class _Sheet extends LeafRenderObjectWidget {
  const _Sheet(this.looks);

  final LiveLooks looks;

  @override
  _RenderSheet createRenderObject(BuildContext context) => _RenderSheet(looks);

  @override
  void updateRenderObject(BuildContext context, _RenderSheet renderObject) {
    assert(identical(renderObject._looks, looks), 'a layer keeps its looks');
  }
}

/// One layer of the sheet: as large as what it lies under or over, on a
/// layer of its own that a still region draws live
/// ([TickSceneLayer.alwaysLive]).
class _RenderSheet extends RenderBox {
  _RenderSheet(this._looks);

  final LiveLooks _looks;

  /// Where each look was last drawn — its box's place in the sheet's host
  /// and its size.
  final Map<RenderBox, _Place> _drawnAt = <RenderBox, _Place>{};
  bool _placesAsked = false;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  /// What is drawn here is seen, not met: a pointer meets the boxes.
  @override
  bool hitTestSelf(Offset position) => false;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant OffsetLayer? oldLayer,
  }) =>
      (oldLayer is TickSceneLayer ? oldLayer : TickSceneLayer(alwaysLive: true))
        ..size = size;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _looks.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _looks.removeListener(markNeedsPaint);
    super.detach();
  }

  /// 🚨WHILE A LOOK IS LAID, THE SHEET ASKS WHERE ITS BOXES STAND ONCE
  /// EVERY FRAME IS DRAWN, and draws the looks again if one stands
  /// elsewhere or is another size: a box is moved with no word to anything
  /// — by a layout above it, by a transform that only moved the layer it is
  /// painted in — and a frame is drawn for whatever moved it.
  ///
  /// ⚠️THE PRICE: such a move is seen in the look one frame after the box.
  /// A scroll is the move that goes on for frames, and says so before its
  /// frame ([LiveLooks.moved]). ⛔Not asked from the box's own paint, as it
  /// was first: a box behind a repaint boundary is not painted again for a
  /// move of the boundary.
  void _askPlacesAfterTheFrame() {
    if (_placesAsked) {
      return;
    }
    _placesAsked = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _placesAsked = false;
      final host = _looks._host;
      if (!attached || host == null || _looks._laid.isEmpty) {
        return;
      }
      for (final box in _looks._laid.keys) {
        if (_placeOf(box, host) != _drawnAt[box]) {
          // Drawn again, it asks again.
          markNeedsPaint();
          return;
        }
      }
      _askPlacesAfterTheFrame();
    });
  }

  static _Place _placeOf(RenderBox box, RenderObject host) =>
      (at: box.getTransformTo(host), size: box.size);

  @override
  void paint(PaintingContext context, Offset offset) {
    _drawnAt.clear();
    final host = _looks._host!;
    final canvas = context.canvas;
    // The host's coordinates, from where the layer lies in it.
    final origin = offset - localToGlobal(Offset.zero, ancestor: host);
    for (final MapEntry(key: box, value: look) in _looks._laid.entries) {
      final place = _placeOf(box, host);
      _drawnAt[box] = place;
      canvas
        ..save()
        ..translate(origin.dx, origin.dy);
      if (_cutOf(box, host) case final cut?) {
        canvas.clipRect(cut);
      }
      canvas.transform(place.at.storage);
      look(canvas);
      canvas.restore();
    }
    if (_drawnAt.isNotEmpty) {
      _askPlacesAfterTheFrame();
    }
  }

  /// What every clip between [box] and [host] leaves of the host — null
  /// where none stands between them. A look is drawn outside the clips its
  /// box is painted in.
  static Rect? _cutOf(RenderBox box, RenderObject host) {
    Rect? cut;
    RenderObject below = box;
    for (var above = box.parent; above != null; above = above.parent) {
      final clip = above.describeApproximatePaintClip(below);
      if (clip != null) {
        final inHost = MatrixUtils.transformRect(
          above.getTransformTo(host),
          clip,
        );
        cut = cut?.intersect(inHost) ?? inHost;
      }
      if (identical(above, host)) {
        break;
      }
      below = above;
    }
    return cut;
  }
}
