import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../native/app_gpu_engine.dart';
import '../../native/screen_texture.dart';
import '../engine_screen_texture.dart';
import '../layout/device_grid.dart';
import '../widgets/still_raster.dart';
import 'timeline_grid_tile_picture.dart';

/// How far past what the view shows a screen holds, in device pixels, along
/// an axis on which the box goes on past it (공통 2026-11-09, for 관제's F).
/// A scroll moves the screen's layer and lays nothing while what the view
/// shows stays on the screen; a side that is a whole step already — a panel
/// 1024 across — would leave it no room at all, and every pixel of a scroll
/// would lay it again.
const int _screenRoom = 128;

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
/// one box under them (`_ScreenBox`) shows — laid and presented as the box's
/// layer is composited, so what a frame lays is what that frame shows.
/// ↩️Not a `Texture` widget rebuilt off the texture's id: a rebuild comes a
/// frame late, and the two textures it alternates between would each show a
/// frame old.
///
/// Holds the screen for [child] — the grid's rows — and shows it under
/// them, as big as they are: their slots ([TimelineGridScreenSlot]) lay on
/// it once the app's engine is open ([appGpuEngineOpen]) and the grids'
/// passes are compiled on it ([appGpuGridKernels]); till then, and wherever
/// a row has no slot, a row draws its cells itself. What lies under the
/// rows — the grid's sheet — lies under it.
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
/// the texture it is shown through once the app's engine is open and a row
/// is there to lay on it (관제 2026-11-09 08:07 E③) — as big as what of the
/// box the view shows, with room to scroll ([_screenRoom]), its sides rounded
/// up ([EngineScreenTexture]), in device pixels.
final class _GridScreen {
  _RenderGridScreen? _box;
  final Set<_RenderGridScreenSlot> _slots = {};

  /// What it is shown through, as big as what of the box the view showed in
  /// the frame last composited, and its room.
  late final EngineScreenTexture _shownThrough = EngineScreenTexture(
    asks: () => _box != null && _slots.isNotEmpty,
    opened: (_) {
      // Asked for by the first screen there is to lay on, whoever else
      // asks; compiled behind what the launch compiles for a hand
      // ([appGpuGridKernels]). The rows lay once they have come.
      if (appGpuGridKernels.compiled == null) {
        unawaited(appGpuGridKernels.warm().then((_) => _laysChanged()));
      }
      _laysChanged();
    },
  );

  ScreenTexture? get _texture => _shownThrough.texture;

  /// Where the rows' tiles were last laid, in the box's own pixels, and the
  /// id what was laid is shown by — null where they are to be laid again.
  ({Rect at, int id})? _laid;

  /// Whether a row lays its tiles here: a box shows the screen, its texture
  /// is open and holds what it shows, and the grids' passes are compiled
  /// ([appGpuGridKernels]). ↩️Any texture open: while a bigger one opened,
  /// the rows laid on the one held, and what of them lay past its edge was
  /// shown nowhere (타임라인/콘티 리뷰 2026-11-09 B). ↩️The passes compiled
  /// where the first row laid: a row draws its cells itself till they are,
  /// as it does before the engine is open, and no frame waits for a compile
  /// (🗣️관제 2026-11-10 18:14, gpu-canonical-store ⑦: 「UI 스레드가 직접
  /// 하는 커널 컴파일 0개」).
  bool get lays =>
      _box != null &&
      _shownThrough.holdsWhatIsWanted &&
      appGpuGridKernels.compiled != null;

  void start() => _shownThrough.start();

  void stop() => _shownThrough.stop();

  void showBy(_RenderGridScreen box) {
    assert(_box == null || identical(_box, box), 'one box shows a screen');
    _box = box;
    _laysChanged();
  }

  void hiddenBy(_RenderGridScreen box) {
    if (identical(_box, box)) {
      _box = null;
      _laysChanged();
    }
  }

  void slotCame(_RenderGridScreenSlot slot) {
    _slots.add(slot);
    unawaited(_shownThrough.open());
  }

  /// The box tells what of it the view shows, [shown] of [bounds], in device
  /// pixels. ⚠️What that changes, it changes after the frame: the rows of
  /// this frame have laid, or not, by what [lays] said as they painted
  /// ([PipelineOwner.flushPaint] paints what is deeper first), and the box
  /// shows them by the same answer; marked during the frame a row would
  /// paint in none (a frame is not asked for in a frame's own phases).
  ///
  /// ↩️The view's size, off the MediaQuery (타임라인/콘티 리뷰 2026-11-09 A ·
  /// 01:46: a window grown stayed laid at the size it opened at): the view
  /// says nothing of a panel's size, and a texture as big as the view held
  /// a strip's few rows at the price of a whole window (관제 08:07 E②).
  void showed(Rect shown, Rect bounds) {
    final wanted = shown.isEmpty
        ? (0, 0)
        : (
            _sideOf(shown.left, shown.right, bounds.left, bounds.right),
            _sideOf(shown.top, shown.bottom, bounds.top, bounds.bottom),
          );
    if (wanted == _shownThrough.wanted) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final laid = lays;
      _shownThrough.wanted = wanted;
      if (lays != laid) {
        _laysChanged();
      }
      unawaited(_shownThrough.open());
    });
  }

  /// The side that holds [from] to [to], of a box from [boxFrom] to [boxTo],
  /// all on device pixels: with room for a scroll where the box goes on
  /// past it.
  static int _sideOf(double from, double to, double boxFrom, double boxTo) =>
      (to - from).toInt() + (from > boxFrom || to < boxTo ? _screenRoom : 0);

  /// A row's paint, or its going, changed what the screen shows: it is
  /// laid again as the frame's scene is built.
  void _rowChanged() {
    _laid = null;
  }

  /// What lays here changed: every row asks again whether it lays its
  /// tiles here, and the box whether it shows what they lay.
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
/// over it — on a rect of the texture's size around that, in the box's own
/// pixels, so a scroll of anything around it moves it with the rows.
///
/// What a frame's rows lay is on the screen that frame shows: the box's
/// layer lays the screen once the frame has painted ([_ScreenLayer]).
/// ↩️Laid in the box's paint, a row that came after was not on it: a frame
/// paints what is deeper first ([PipelineOwner.flushPaint]), and a row comes
/// in the paint of a layer shallower than the box.
///
/// ↩️Every scroll of any scrollable around it marked it to paint and laid
/// the screen again, on a texture of the view's size at the view's corner
/// (관제 2026-11-09 08:07 F, D1 as drawn: 「픽셀 스크롤은 레이어째 따라가니
/// 다시 깔지 않고, 행이 다시 그려질 때만 깐다」).
class _ScreenBox extends LeafRenderObjectWidget {
  const _ScreenBox();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGridScreen(_GridScreenScope.of(context)!);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderGridScreen)._showOn(
        _GridScreenScope.of(context)!,
      );
}

class _RenderGridScreen extends RenderBox {
  _RenderGridScreen(this._screen);

  _GridScreen _screen;

  void _showOn(_GridScreen screen) {
    if (attached && !identical(screen, _screen)) {
      _screen.hiddenBy(this);
      screen.showBy(this);
    }
    _screen = screen;
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
    _screen.showBy(this);
  }

  @override
  void detach() {
    _screen.hiddenBy(this);
    super.detach();
  }

  // Only where it lays: a grid with no screen is one like any other. It says
  // what it shows all the same, or no texture would ever open. ↩️A texture
  // under no tick kept a dock from being held as a still image (`StillRaster`)
  // for as long as it showed one: under one always live, the region draws it
  // between what it holds (11-09, card the-grid-screen-keeps-the-dock-from-baking).
  @override
  void paint(PaintingContext context, Offset offset) {
    final laid = _screen.lays;
    _measured();
    if (laid) {
      context.addLayer(
        TickSceneLayer(alwaysLive: true)
          ..size = size
          ..append(_ScreenLayer(this)),
      );
    }
  }

  /// What of this box the view shows, in the view's device pixels — told to
  /// its screen — and the transform that took it there. To the root by name,
  /// its transform — the ratio — is carried; to `null` it is not.
  ({Matrix4 toView, Rect shown}) _measured() {
    final view = owner!.rootNode!;
    final toView = getTransformTo(view);
    // ⚠️Asked empty before it is turned: what no clip left anything of is a
    // rect inside out, and a transform turns it right side out again.
    Rect inView(Rect rect) => rect.isEmpty
        ? Rect.zero
        : _outToDevicePixels(MatrixUtils.transformRect(toView, rect));
    final shown = inView(_shownRect());
    _screen.showed(shown, inView(Offset.zero & size));
    return (toView: toView, shown: shown);
  }

  /// [rect], in device pixels, out to the whole ones it touches — by the
  /// grid's own rounding, or a ratio's last bit is a pixel more or less.
  static Rect _outToDevicePixels(Rect rect) {
    const pixels = DeviceGrid(1);
    return Rect.fromLTRB(
      pixels.position(rect.left),
      pixels.position(rect.top),
      pixels.clearance(rect.right),
      pixels.clearance(rect.bottom),
    );
  }

  /// What this frame shows of the screen — laid first where a row changed
  /// or what the view shows has left it — asked as the frame's scene is
  /// built: nothing is told of a move of any scrollable around this box, or
  /// of the growing of a panel it stands in, and a frame built is the one
  /// moment all of them are known to have come to rest.
  ({Rect at, int id})? _composited() {
    final screen = _screen;
    final (:toView, :shown) = _measured();
    if (shown.isEmpty) {
      return null;
    }
    final texture = screen._texture!;
    final laid = screen._laid;
    if (laid != null &&
        _covers(MatrixUtils.transformRect(toView, laid.at), shown)) {
      return laid;
    }
    final window = _windowOf(texture, shown);
    final id = texture.nextTextureId;
    _layAt(
      window.topLeft,
      texture,
      appGpuGridKernels.kept.lay,
      owner!.rootNode!,
    );
    return screen._laid = (
      at: MatrixUtils.inverseTransformRect(toView, window),
      id: id,
    );
  }

  /// Whether the screen, standing at [laid], still has [shown] on it —
  /// [laid] on whole device pixels but for what the box's pixels took off
  /// it and gave back.
  static bool _covers(Rect laid, Rect shown) =>
      laid.left.roundToDouble() <= shown.left &&
      laid.top.roundToDouble() <= shown.top &&
      laid.right.roundToDouble() >= shown.right &&
      laid.bottom.roundToDouble() >= shown.bottom;

  /// A rect as big as [texture] around [shown], on device pixels: what it
  /// spares of the texture half to either side, on an axis where it spares
  /// any — from its start where it is the bigger.
  static Rect _windowOf(ScreenTexture texture, Rect shown) {
    double startOf(double from, double to, int side) =>
        from - (math.max(side - (to - from), 0) / 2).floorToDouble();

    return Rect.fromLTWH(
      startOf(shown.left, shown.right, texture.width),
      startOf(shown.top, shown.bottom, texture.height),
      texture.width.toDouble(),
      texture.height.toDouble(),
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

/// A grid's screen in the frame's layers, asked what it shows
/// ([_RenderGridScreen._composited]) as every frame's scene is built — once
/// every row the frame paints has laid what it lays. So it is added to every
/// scene, retained in none.
class _ScreenLayer extends TextureLayer {
  _ScreenLayer(this._box)
    : super(
        rect: Rect.zero,
        textureId: 0,
        filterQuality: FilterQuality.none,
      );

  final _RenderGridScreen _box;

  ({Rect at, int id})? _shown;

  @override
  Rect get rect => _shown?.at ?? Rect.zero;

  @override
  int get textureId => _shown?.id ?? 0;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    _shown = _box._composited();
    if (_shown != null) {
      super.addToScene(builder);
    }
  }
}

/// A row's place on its grid's screen ([TimelineGridScreenHost]): what the
/// row under it paints may lay tiles there ([laying]), drawing nothing of
/// their spans itself.
///
/// Its own layer, so a row painting again is a paint of this slot alone —
/// what it lays is on the screen as that frame's scene is built.
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
      screen?.slotCame(this);
    }
    _screen = screen;
    markNeedsPaint();
  }

  /// What the row laid in its last paint.
  final List<TimelineGridScreenTile> _laid = [];

  @override
  bool get isRepaintBoundary => true;

  // A slot that comes paints, and so does one that comes back — what it
  // laid was let go as it went ([detach]). ↩️Left to its layout: a slot moved
  // to another parent with the constraints it had is not laid out again, and
  // showed nothing (타임라인/콘티 리뷰 2026-11-09 H).
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _screen?.slotCame(this);
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
    _screen?._rowChanged();
    final outer = _painting;
    _painting = this;
    try {
      super.paint(context, offset);
    } finally {
      _painting = outer;
    }
  }
}
