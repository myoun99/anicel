import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../native/app_gpu_engine.dart';
import '../../native/screen_texture.dart';
import 'timeline_grid_tile_picture.dart';

/// How a grid's screen is opened: [ScreenTexture.open]. A test reads one
/// back through [ScreenTexture.debugOnSurface].
@visibleForTesting
Future<ScreenTexture> Function(GpuEngine engine, int width, int height)
debugOpenTimelineGridScreen = ScreenTexture.open;

/// A tile a row lays on its grid's screen: the part [from] of its
/// [picture], in the picture's pixels, onto the part [onto] of the row, in
/// the row's own.
typedef TimelineGridScreenTile = ({
  TimelineGridTilePicture picture,
  Rect from,
  Rect onto,
});

/// THE FRAME GRID'S SCREEN ON THE ENGINE (grid-on-the-engine ④ D1, 관제
/// 2026-11-08 20:54): one grid's rows lay their tiles on one screen, which
/// one box under them (`_ScreenBox`) shows — laid and presented in
/// the box's own paint, the texture's layer put there by it, so what a
/// frame lays is what that frame shows. ↩️Not a `Texture` widget rebuilt
/// off the texture's id: a rebuild comes a frame late, and the two textures
/// it alternates between would each show a frame old.
///
/// Holds the screen for [child] — the grid's rows — and shows it under
/// them, as big as they are: their slots ([TimelineGridScreenSlot]) lay on
/// it once the app's engine is open ([appGpuEngineOpen]); till then, and
/// wherever a row has no slot, a row draws its cells itself. What lies
/// under the rows — the grid's sheet — lies under it.
class TimelineGridScreenHost extends StatefulWidget {
  const TimelineGridScreenHost({super.key, required this.child});

  final Widget child;

  @override
  State<TimelineGridScreenHost> createState() => _TimelineGridScreenHostState();
}

class _TimelineGridScreenHostState extends State<TimelineGridScreenHost> {
  final _GridScreen _screen = _GridScreen();

  @override
  void initState() {
    super.initState();
    _screen.start();
  }

  @override
  void dispose() {
    _screen.stop();
    super.dispose();
  }

  // The rows as they were laid out, and drawn, without it.
  @override
  Widget build(BuildContext context) => _GridScreenScope(
    screen: _screen,
    child: Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [const Positioned.fill(child: _ScreenBox()), widget.child],
    ),
  );
}

class _GridScreenScope extends InheritedWidget {
  const _GridScreenScope({required this.screen, required super.child});

  final _GridScreen screen;

  static _GridScreen? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GridScreenScope>()?.screen;

  @override
  bool updateShouldNotify(_GridScreenScope oldWidget) =>
      !identical(oldWidget.screen, screen);
}

/// One grid's screen: the box that shows it, the rows that lay on it, and
/// the texture it is shown through once the app's engine is open — as big
/// as the view, in device pixels: what of the grid the view shows is laid,
/// wherever it is scrolled to.
final class _GridScreen {
  _RenderGridScreen? _box;
  final Set<_RenderGridScreenSlot> _slots = {};
  ScreenTexture? _texture;
  GpuGridLay? _lay;

  /// The view's size in device pixels, which the texture holds.
  (int, int) _size = (0, 0);

  /// The size a texture is being opened at.
  (int, int)? _opening;
  bool _stopped = false;

  /// Whether a row lays its tiles here: a box shows the screen, and its
  /// texture is open and holds the view. ↩️Any texture open: while a bigger
  /// one opened, the rows laid on the one held, and what of them lay past
  /// its edge was shown nowhere (타임라인/콘티 리뷰 2026-11-09 B).
  bool get lays => _box != null && _holdsTheView(_texture);

  bool _holdsTheView(ScreenTexture? texture) {
    final (width, height) = _size;
    return texture != null &&
        texture.width >= width &&
        texture.height >= height;
  }

  void start() => appGpuEngineOpen.addListener(_open);

  void stop() {
    _stopped = true;
    appGpuEngineOpen.removeListener(_open);
    final texture = _texture;
    _texture = null;
    _lay?.free();
    _lay = null;
    unawaited(texture?.free());
  }

  void showBy(_RenderGridScreen box, (int, int) size) {
    assert(_box == null || identical(_box, box), 'one box shows a screen');
    _box = box;
    _size = size;
    unawaited(_open());
    _laysChanged();
  }

  void hiddenBy(_RenderGridScreen box) {
    if (identical(_box, box)) {
      _box = null;
      _laysChanged();
    }
  }

  void sizedBy(_RenderGridScreen box, (int, int) size) {
    if (identical(_box, box) && size != _size) {
      final laid = lays;
      _size = size;
      if (lays != laid) {
        _laysChanged();
      }
      unawaited(_open());
    }
  }

  /// Opens a texture of [_size] where the engine is open and the one held
  /// is smaller; the one it replaces is freed once it is shown no more.
  Future<void> _open() async {
    final engine = appGpuEngineOpen.value;
    final (width, height) = _size;
    final held = _texture;
    if (engine == null ||
        _box == null ||
        _holdsTheView(held) ||
        _opening == _size) {
      return;
    }
    if (width <= 0 || height <= 0) {
      return;
    }
    final asked = _opening = _size;
    final opened = await debugOpenTimelineGridScreen(engine, width, height);
    if (_stopped || _opening != asked) {
      await opened.free();
      return;
    }
    _opening = null;
    _texture = opened;
    _lay ??= GpuGridLay(engine);
    _laysChanged();
    await held?.free();
  }

  /// A row's paint, or its going, changed what the box shows — nothing
  /// where the screen does not lay: the rows draw their own cells, and a
  /// row painting on a tick layer paints alone (F-244).
  void _rowChanged() {
    if (lays) {
      _box?.markNeedsPaint();
    }
  }

  /// What lays here changed: every row asks again whether it lays its
  /// tiles here, and the box shows what they lay.
  void _laysChanged() {
    for (final slot in _slots) {
      slot.markNeedsPaint();
    }
    _box?.markNeedsPaint();
  }
}

/// The box that shows its grid's screen ([TimelineGridScreenHost]): between
/// the grid's sheet and its rows, as big as the rows' area. It shows what
/// of the rows' tiles the view shows — the box's bounds within every clip
/// over it — there, snapped to device pixels.
///
/// What a frame's rows lay is on the screen that frame shows: a row marked
/// to paint, or come, marks the box to paint in its frame
/// ([TimelineGridScreenSlot]), and the box's layer lays the screen once
/// the frame has painted ([_ScreenLayer]). ↩️Laid in the box's paint, a
/// row that came after was not on it: a frame paints what is deeper first
/// ([PipelineOwner.flushPaint]), and a row comes in the paint of a layer
/// shallower than the box. A scroll of any scrollable around it lays the
/// screen again; the rows' pictures are kept.
class _ScreenBox extends LeafRenderObjectWidget {
  const _ScreenBox();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGridScreen(
    _GridScreenScope.of(context)!,
    size: _sizeOf(context),
    moves: _movesOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderGridScreen)._update(
        _GridScreenScope.of(context)!,
        size: _sizeOf(context),
        moves: _movesOf(context),
      );

  /// The view's size in device pixels. ⚠️Asked of the MediaQuery too —
  /// its size, and its ratio for a window moved to a screen of another
  /// ratio at the size it had — though not read off it: the app's UI scale
  /// rewrites both (`EffectiveDevicePixelRatioScope`). So a view resized
  /// builds the box again: `View.of` tells of another view, not of another
  /// size. ↩️It did not, and a window grown stayed laid at the size it
  /// opened at (타임라인/콘티 리뷰 2026-11-09 A · 01:46).
  static (int, int) _sizeOf(BuildContext context) {
    MediaQuery.sizeOf(context);
    MediaQuery.devicePixelRatioOf(context);
    final size = View.of(context).physicalSize;
    return (size.width.ceil(), size.height.ceil());
  }

  /// The positions of every scrollable around [context].
  static Listenable _movesOf(BuildContext context) => Listenable.merge([
    for (
      var scrollable = Scrollable.maybeOf(context);
      scrollable != null;
      scrollable = Scrollable.maybeOf(scrollable.context)
    )
      scrollable.position,
  ]);
}

class _RenderGridScreen extends RenderBox {
  _RenderGridScreen(
    this._screen, {
    required (int, int) size,
    required Listenable moves,
  }) : _viewSize = size,
       _moves = moves;

  _GridScreen _screen;
  (int, int) _viewSize;
  Listenable _moves;

  void _update(
    _GridScreen screen, {
    required (int, int) size,
    required Listenable moves,
  }) {
    if (attached) {
      _moves.removeListener(markNeedsPaint);
      moves.addListener(markNeedsPaint);
      if (!identical(screen, _screen)) {
        _screen.hiddenBy(this);
        screen.showBy(this, size);
      }
      screen.sizedBy(this, size);
    }
    _screen = screen;
    _viewSize = size;
    _moves = moves;
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _screen.showBy(this, _viewSize);
    _moves.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _moves.removeListener(markNeedsPaint);
    _screen.hiddenBy(this);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_screen.lays) {
      return;
    }
    final texture = _screen._texture!;
    final lay = _screen._lay!;
    // In the view's device pixels: to the root by name, its transform — the
    // ratio — is carried; to `null` it is not.
    final view = owner!.rootNode!;
    final toView = getTransformTo(view);
    final shown = MatrixUtils.transformRect(toView, _shownRect());
    if (shown.isEmpty) {
      return;
    }
    final origin = Offset(shown.left.floorToDouble(), shown.top.floorToDouble());
    final screen =
        origin & Size(texture.width.toDouble(), texture.height.toDouble());
    context.addLayer(
      _ScreenLayer(
        rect: MatrixUtils.inverseTransformRect(toView, screen).shift(offset),
        textureId: texture.nextTextureId,
        lay: () => _layAt(origin, texture, lay, view),
      ),
    );
  }

  /// Presents every slot's tiles on [texture], from [origin] in the device
  /// pixels of [view] — what of them it holds, the rest of it clear.
  void _layAt(
    Offset origin,
    ScreenTexture texture,
    GpuGridLay lay,
    RenderObject view,
  ) {
    final (width, height) = (texture.width, texture.height);
    final laid = <GpuGridLaid>[];
    for (final slot in _screen._slots) {
      if (slot._laid.isEmpty) {
        continue;
      }
      final slotToView = slot.getTransformTo(view);
      for (final (:picture, :from, :onto) in slot._laid) {
        final at = MatrixUtils.transformRect(slotToView, onto).shift(-origin);
        if (at.right <= 0 || at.bottom <= 0 || at.left >= width) {
          continue;
        }
        if (at.top >= height) {
          continue;
        }
        laid.add((
          picture: picture.picture,
          from: (from.left, from.top, from.right, from.bottom),
          onto: (at.left, at.top, at.right, at.bottom),
        ));
      }
    }
    texture.present((next) => lay.lay(next, (0, 0, width, height), laid));
  }

  /// What of this box the view shows, in its own pixels: its bounds within
  /// the clip each ancestor lays over it — in that ancestor's own pixels
  /// ([RenderObject.describeApproximatePaintClip]) — and the view's own.
  Rect _shownRect() {
    var shown = Offset.zero & size;
    RenderObject child = this;
    for (var above = parent; above != null; above = above.parent) {
      final clip = above.describeApproximatePaintClip(child);
      if (clip != null) {
        shown = shown.intersect(
          MatrixUtils.inverseTransformRect(getTransformTo(above), clip),
        );
      }
      child = above;
    }
    return shown.intersect(
      MatrixUtils.inverseTransformRect(getTransformTo(child), child.paintBounds),
    );
  }
}

/// A grid's screen in the frame's layers, laid as the frame's scene is
/// built ([addToScene]) — once every row the frame paints has laid what it
/// lays — and shown by the id its texture shows that next frame by.
class _ScreenLayer extends TextureLayer {
  _ScreenLayer({
    required super.rect,
    required super.textureId,
    required void Function() lay,
  }) : _lay = lay,
       super(filterQuality: FilterQuality.none);

  /// Laid once: a scene built of this layer again shows what it laid.
  void Function()? _lay;

  @override
  void addToScene(ui.SceneBuilder builder) {
    final lay = _lay;
    _lay = null;
    lay?.call();
    super.addToScene(builder);
  }
}

/// A row's place on its grid's screen ([TimelineGridScreenHost]): what the
/// row under it paints may lay tiles there ([laying]), drawing nothing of
/// their spans itself.
///
/// Its own layer, so a row painting again is a paint of this slot — which
/// marks the screen's box to paint after it, in the same frame.
class TimelineGridScreenSlot extends SingleChildRenderObjectWidget {
  const TimelineGridScreenSlot({super.key, this.clip, required super.child});

  /// The clip the row is drawn within, where one stands between it and its
  /// grid's screen — which is not under that clip, so the slot lays the
  /// row's tiles within it ([TimelineGridScreenClip.rectsIn]).
  final TimelineGridScreenClip? clip;

  /// Where the row being painted lays its tiles — null where none does:
  /// no screen over its grid, or none open yet. A row then draws its cells
  /// itself.
  static TimelineGridScreenLaying? get laying {
    if (_debugLaying case final laying?) {
      return laying;
    }
    final slot = _RenderGridScreenSlot._painting;
    return slot != null && (slot._screen?.lays ?? false) ? slot : null;
  }

  /// Runs [paint] — a row a test paints by hand, outside any slot — as a
  /// row whose grid's screen takes its tiles through [laying].
  @visibleForTesting
  static void debugLayThrough(
    TimelineGridScreenLaying laying,
    void Function() paint,
  ) {
    final outer = _debugLaying;
    _debugLaying = laying;
    try {
      paint();
    } finally {
      _debugLaying = outer;
    }
  }

  static TimelineGridScreenLaying? _debugLaying;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGridScreenSlot(_GridScreenScope.of(context), clip);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderGridScreenSlot)
        .._showOn(_GridScreenScope.of(context))
        .._clipBy(clip);
}

/// A clip of rects, as a row's cells are clipped to the stretches of it
/// they show: a path for the clip over the row's own drawing, and the rects
/// it is made of for its tiles on the screen under it, which a path cannot
/// tell ([TimelineGridScreenSlot.clip]).
abstract class TimelineGridScreenClip extends CustomClipper<Path> {
  const TimelineGridScreenClip({super.reclip});

  /// The rects of the clip, in the row's own pixels.
  List<Rect> rectsIn(Size size);

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final rect in rectsIn(size)) {
      path.addRect(rect);
    }
    return path;
  }
}

/// What a row lays its tiles on, while it paints.
abstract interface class TimelineGridScreenLaying {
  /// Lays [tile] on the screen this paint, and every paint of the screen
  /// till the row paints again — holding its picture till then.
  void lay(TimelineGridScreenTile tile);
}

class _RenderGridScreenSlot extends RenderProxyBox
    implements TimelineGridScreenLaying {
  _RenderGridScreenSlot(this._screen, this._clip);

  /// The slot whose row is painting.
  static _RenderGridScreenSlot? _painting;

  _GridScreen? _screen;
  TimelineGridScreenClip? _clip;

  /// A clip that moves lays its row's tiles again — as the row's own
  /// clip ([ClipPath]) clips again.
  void _clipBy(TimelineGridScreenClip? clip) {
    final was = _clip;
    if (identical(clip, was)) {
      return;
    }
    if (attached) {
      was?.removeListener(markNeedsPaint);
      clip?.addListener(markNeedsPaint);
    }
    _clip = clip;
    if (clip == null ||
        was == null ||
        clip.runtimeType != was.runtimeType ||
        clip.shouldReclip(was)) {
      markNeedsPaint();
    }
  }

  void _showOn(_GridScreen? screen) {
    if (identical(screen, _screen)) {
      return;
    }
    if (attached) {
      _leave();
      screen?._slots.add(this);
    }
    _screen = screen;
    markNeedsPaint();
  }

  /// What the row laid in its last paint.
  final List<TimelineGridScreenTile> _laid = [];

  @override
  bool get isRepaintBoundary => true;

  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    _screen?._rowChanged();
  }

  // A slot that comes paints, and so does one that comes back — what it
  // laid was let go as it went ([detach]) — and so does the box
  // ([markNeedsPaint]). ↩️Left to its layout: a slot moved to another parent
  // with the constraints it had is not laid out again, and showed nothing
  // (타임라인/콘티 리뷰 2026-11-09 H).
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _screen?._slots.add(this);
    _clip?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void detach() {
    _clip?.removeListener(markNeedsPaint);
    _leave();
    _letGo();
    super.detach();
  }

  /// Lets go of what the row laid.
  void _letGo() {
    for (final (:picture, from: _, onto: _) in _laid) {
      picture.letGo();
    }
    _laid.clear();
  }

  void _leave() {
    final screen = _screen;
    if (screen != null && screen._slots.remove(this)) {
      screen._rowChanged();
    }
  }

  /// The rects of [_clip] in the paint under way: asked once a paint that
  /// lays, not once a tile (타임라인/콘티 리뷰 2026-11-09 I).
  List<Rect>? _clipRects;

  @override
  void lay(TimelineGridScreenTile tile) {
    final rects = _clipRects ??= _clip?.rectsIn(size);
    for (final part in rects == null
        ? [tile]
        : [for (final rect in rects) ?_within(tile, rect)]) {
      part.picture.hold();
      _laid.add(part);
    }
  }

  /// What of [tile] lies within [rect] of the row: that part of its
  /// picture onto that part of the row — null where none does.
  static TimelineGridScreenTile? _within(
    TimelineGridScreenTile tile,
    Rect rect,
  ) {
    final (:picture, :from, :onto) = tile;
    final part = onto.intersect(rect);
    if (part.width <= 0 || part.height <= 0) {
      return null;
    }
    double x(double at) =>
        from.left + (at - onto.left) * from.width / onto.width;
    double y(double at) =>
        from.top + (at - onto.top) * from.height / onto.height;
    return (
      picture: picture,
      from: Rect.fromLTRB(
        x(part.left),
        y(part.top),
        x(part.right),
        y(part.bottom),
      ),
      onto: part,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _letGo();
    _clipRects = null;
    final outer = _painting;
    _painting = this;
    try {
      super.paint(context, offset);
    } finally {
      _painting = outer;
    }
  }
}
