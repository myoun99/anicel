import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../native/app_gpu_engine.dart';
import '../../native/screen_texture.dart';

/// How a grid's screen is opened: [ScreenTexture.open]. A test reads one
/// back through [ScreenTexture.debugOnSurface].
@visibleForTesting
Future<ScreenTexture> Function(GpuEngine engine, int width, int height)
debugOpenTimelineGridScreen = ScreenTexture.open;

/// A tile a row lays on its grid's screen: the part [from] of its
/// [picture], in the picture's pixels, onto the part [onto] of the row, in
/// the row's own.
typedef TimelineGridScreenTile = ({
  GpuGridPicture picture,
  Rect from,
  Rect onto,
});

/// THE FRAME GRID'S SCREEN ON THE ENGINE (grid-on-the-engine ④ D1, 관제
/// 2026-11-08 20:54): one grid's rows lay their tiles on one screen, which
/// one box under them ([TimelineGridScreen]) shows — laid and presented in
/// the box's own paint, the texture's layer put there by it, so what a
/// frame lays is what that frame shows. ↩️Not a `Texture` widget rebuilt
/// off the texture's id: a rebuild comes a frame late, and the two textures
/// it alternates between would each show a frame old.
///
/// Holds the screen for [child]: the box and the rows' slots
/// ([TimelineGridScreenSlot]) under it lay on it once the app's engine is
/// open ([appGpuEngineOpen]); till then, and wherever a row has no slot,
/// a row draws its cells itself.
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

  @override
  Widget build(BuildContext context) =>
      _GridScreenScope(screen: _screen, child: widget.child);
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
  /// texture is open.
  bool get lays => _box != null && _texture != null;

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
      _size = size;
      unawaited(_open());
    }
  }

  /// Opens a texture of [_size] where the engine is open and the one held
  /// is smaller; the one it replaces is freed once it is shown no more.
  Future<void> _open() async {
    final engine = appGpuEngineOpen.value;
    final (width, height) = _size;
    final held = _texture;
    final fits = held != null && held.width >= width && held.height >= height;
    if (engine == null || _box == null || fits || _opening == _size) {
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
/// the grid's sheet and its rows, as big as the rows' area. Each paint lays
/// what of the rows' tiles the view shows — the box's bounds within every
/// clip over it — and shows it there, snapped to device pixels.
///
/// It paints after the rows it shows, in the frame they paint in: a row
/// marked to paint marks it ([TimelineGridScreenSlot]), and a frame paints
/// what is deeper first ([PipelineOwner.flushPaint]) — so what a row lays
/// in its paint is on the screen the frame shows. A scroll of any
/// scrollable around it lays the screen again; the rows' pictures are kept.
class TimelineGridScreen extends LeafRenderObjectWidget {
  const TimelineGridScreen({super.key});

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

  static (int, int) _sizeOf(BuildContext context) {
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
    final texture = _screen._texture;
    final lay = _screen._lay;
    if (texture == null || lay == null) {
      return;
    }
    // In the view's device pixels: to the root by name, its transform — the
    // ratio — is carried; to `null` it is not.
    final view = owner!.rootNode!;
    final toView = getTransformTo(view);
    final shown = MatrixUtils.transformRect(toView, _shownRect());
    if (shown.isEmpty) {
      return;
    }
    final origin = Offset(shown.left.floorToDouble(), shown.top.floorToDouble());
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
          picture: picture,
          from: (from.left, from.top, from.right, from.bottom),
          onto: (at.left, at.top, at.right, at.bottom),
        ));
      }
    }
    if (laid.isEmpty) {
      return;
    }
    texture.present((next) => lay.lay(next, (0, 0, width, height), laid));
    final screen = origin & Size(width.toDouble(), height.toDouble());
    context.addLayer(
      TextureLayer(
        rect: MatrixUtils.inverseTransformRect(toView, screen).shift(offset),
        textureId: texture.textureId.value,
        filterQuality: FilterQuality.none,
      ),
    );
  }

  /// What of this box the view shows, in its own pixels: its bounds within
  /// the clip each ancestor lays over it, and the view's own.
  Rect _shownRect() {
    var shown = Offset.zero & size;
    RenderObject child = this;
    for (var above = parent; above != null; above = above.parent) {
      final clip = above.describeApproximatePaintClip(child);
      if (clip != null) {
        shown = shown.intersect(
          MatrixUtils.inverseTransformRect(getTransformTo(child), clip),
        );
      }
      child = above;
    }
    return shown.intersect(
      MatrixUtils.inverseTransformRect(getTransformTo(child), child.paintBounds),
    );
  }
}

/// A row's place on its grid's screen ([TimelineGridScreenHost]): what the
/// row under it paints may lay tiles there ([laying]), drawing nothing of
/// their spans itself.
///
/// Its own layer, so a row painting again is a paint of this slot — which
/// marks the screen's box to paint after it, in the same frame.
class TimelineGridScreenSlot extends SingleChildRenderObjectWidget {
  const TimelineGridScreenSlot({super.key, required super.child});

  /// Where the row being painted lays its tiles — null where none does:
  /// no screen over its grid, or none open yet. A row then draws its cells
  /// itself.
  static TimelineGridScreenLaying? get laying {
    final slot = _RenderGridScreenSlot._painting;
    return slot != null && (slot._screen?.lays ?? false) ? slot : null;
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGridScreenSlot(_GridScreenScope.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderGridScreenSlot)._showOn(
        _GridScreenScope.of(context),
      );
}

/// What a row lays its tiles on, while it paints.
abstract interface class TimelineGridScreenLaying {
  /// Lays [tile] on the screen this paint, and every paint of the screen
  /// till the row paints again.
  void lay(TimelineGridScreenTile tile);
}

class _RenderGridScreenSlot extends RenderProxyBox
    implements TimelineGridScreenLaying {
  _RenderGridScreenSlot(this._screen);

  /// The slot whose row is painting.
  static _RenderGridScreenSlot? _painting;

  _GridScreen? _screen;

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
    _screen?._box?.markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _screen?._slots.add(this);
    _screen?._box?.markNeedsPaint();
  }

  @override
  void detach() {
    _leave();
    super.detach();
  }

  void _leave() {
    final screen = _screen;
    if (screen != null && screen._slots.remove(this)) {
      screen._box?.markNeedsPaint();
    }
  }

  @override
  void lay(TimelineGridScreenTile tile) => _laid.add(tile);

  @override
  void paint(PaintingContext context, Offset offset) {
    _laid.clear();
    final outer = _painting;
    _painting = this;
    try {
      super.paint(context, offset);
    } finally {
      _painting = outer;
    }
  }
}
