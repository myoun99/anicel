import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../native/app_gpu_engine.dart';
import '../../native/engine_faces.dart';
import '../../native/screen_texture.dart';
import '../engine_screen_texture.dart';
import '../layout/device_grid.dart';
import '../widgets/still_raster.dart';
import 'timeline_grid_tile_picture.dart';
import '../listenable_rebind.dart';

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

  /// The rows this screen, open, told to draw their cells themselves: the
  /// texture held had not what the view showed of them on it ([_answers]).
  /// Asked again as a scene is built, once it has
  /// ([_RenderGridScreen._askRowsAgain]).
  final Set<_RenderGridScreenSlot> _unheld = {};

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
      // And the faces its tiles' words are set in, read while those
      // compile: a word waits for them once a process, and a tile asked
      // for before they are read is drawn off the paint
      // (`TimelineGridTileStore._glyphNow`).
      unawaited(EngineFaces.bundled());
      _textureCame();
    },
    // No row lays here till the next engine's is open: each paints again,
    // lets go of the tiles it laid, and draws its cells itself.
    letGo: _laysChanged,
    // The rows' tiles, laid as the GPU finished them, are shown by the
    // next scene — and laid again there where they changed meanwhile.
    putUp: ({required behind}) {
      if (behind) {
        _laid = null;
      }
      _box?.markNeedsPaint();
      // A row that laid what the frame up was not laid with drew it itself
      // as well ([TimelineGridScreenLaying.lay]): it asks again.
      for (final slot in _slots) {
        if (slot._drawsWhatIsNotUp) {
          slot.markNeedsPaint();
        }
      }
    },
  );

  ScreenTexture? get _texture => _shownThrough.texture;

  /// Where the rows' tiles were last laid, in the box's own pixels — null
  /// where they are to be laid again. What is shown is the frame the GPU
  /// finished last, where it was laid ([ScreenTexture.shownFor]).
  Rect? _laid;

  /// How many times the rows' tiles have been laid ([_RenderGridScreen
  /// ._layAt]) — each lay drawn for its count ([_LaidFor]), so the frame up
  /// tells which lay it shows.
  int _laysMade = 0;

  /// The lay the frame up shows — null where none is up
  /// ([ScreenTexture.shownFor]).
  int? get _layUp => switch (_texture) {
    final texture? when texture.showsAFrame => switch (texture.shownFor) {
      final _LaidFor up => up.lay,
      _ => null,
    },
    _ => null,
  };

  /// Whether rows lay their tiles here at all: a box shows the screen, a
  /// texture is open for it, and the grids' passes are compiled
  /// ([appGpuGridKernels]). ↩️The passes compiled where the first row laid:
  /// a row draws its cells itself till they are, as it does before the
  /// engine is open, and no frame waits for a compile (🗣️관제 2026-11-10
  /// 18:14, gpu-canonical-store ⑦: 「UI 스레드가 직접 하는 커널 컴파일
  /// 0개」).
  bool get shows =>
      _box != null && _texture != null && appGpuGridKernels.compiled != null;

  /// 🚨A ROW LAYS ITS TILES HERE WHERE THE TEXTURE HELD HAS WHAT THE VIEW
  /// SHOWS OF IT, and draws its cells itself where it has not — each row
  /// by its own answer ([_RenderGridScreen._holds]), given as it paints.
  ///
  /// ↩️Any texture open: while a bigger one opened, the rows laid on the one
  /// held, and what of them lay past its edge was shown nowhere
  /// (타임라인/콘티 리뷰 2026-11-09 B).
  /// ↩️One answer for the whole screen — B's: no row laid till the texture
  /// held what the view showed. A row past the edge of the one held was
  /// drawn, and so was every row within it: 🔬the whole workspace, the
  /// timeline, a row's lanes opened so its rows' area passed a step of the
  /// texture's side (140 to 196 px at a ratio of 3: 420 to 588 device
  /// pixels, past 512) — the frame after, each of the five rows already
  /// there was painted again with no painter asking, and its still image
  /// let go; and once more as the bigger one opened (card
  /// the-first-lanes-opened-retake-the-rows-already-there, 11-22). And the
  /// row that CAME past the edge laid there for the frame it came in,
  /// shown nowhere: it asks as it paints now, and draws itself.
  bool laysFor(_RenderGridScreenSlot slot) => shows && _box!._holds(slot);

  /// [slot]'s row is about to paint: whether it lays its tiles here
  /// ([laysFor]), kept where the screen, open, tells it not to ([_unheld]).
  bool _answers(_RenderGridScreenSlot slot) {
    final lays = laysFor(slot);
    if (shows && !lays) {
      _unheld.add(slot);
    } else {
      _unheld.remove(slot);
    }
    return lays;
  }

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
  /// pixels: a texture that holds it is opened after the frame. The rows
  /// of this frame have laid on the one held, or not, each by what the one
  /// held has of it ([laysFor]) — and those the view has grown round, which
  /// paint nothing by themselves, are asked again as the frame's scene is
  /// built ([_RenderGridScreen._askRowsAgain]).
  /// ↩️What it showed changed the whole screen's one answer after the
  /// frame, and every row painted again by it.
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
      _shownThrough.wanted = wanted;
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

  /// Whether rows lay here changed ([shows]): every row asks again whether
  /// it lays its tiles here, and the box whether it shows what they lay.
  void _laysChanged() {
    for (final slot in _slots) {
      slot.markNeedsPaint();
    }
    _box?.markNeedsPaint();
  }

  /// A texture has just been opened — the first, or one bigger than the one
  /// held: the rows that drew their cells themselves ask again, and those
  /// that lay are laid on it as the next scene is built, unpainted — what a
  /// row laid is its tiles' pictures, of no texture's.
  void _textureCame() {
    _laid = null;
    for (final slot in _slots) {
      if (!slot._lays) {
        slot.markNeedsPaint();
      }
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
    final shows = _screen.shows;
    _measured();
    if (shows) {
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
    final shown = _inView(toView, _shownRect());
    _screen.showed(shown, _inView(toView, Offset.zero & size));
    return (toView: toView, shown: shown);
  }

  /// [rect] taken to the view by [toView], on whole device pixels.
  /// ⚠️Asked empty before it is turned: what no clip left anything of is a
  /// rect inside out, and a transform turns it right side out again.
  static Rect _inView(Matrix4 toView, Rect rect) => rect.isEmpty
      ? Rect.zero
      : _outToDevicePixels(MatrixUtils.transformRect(toView, rect));

  /// Whether the texture held has on it what the view shows of [slot]'s
  /// row, where this frame's scene lays it ([_composited]): around what the
  /// view shows of the box, and from its start along a side the texture is
  /// outgrown on ([EngineScreenTexture.windowOf]). Asked as the row paints
  /// — the frame is laid out by then, the box with it.
  bool _holds(_RenderGridScreenSlot slot) {
    final view = owner!.rootNode!;
    final shown = _inView(getTransformTo(view), _shownRect());
    return shown.isEmpty ||
        _holdsOn(
          EngineScreenTexture.windowOf(_screen._texture!, shown),
          shown,
          slot,
          view,
        );
  }

  /// Whether [window], in the device pixels of [view], has on it what of
  /// [slot]'s row lies within [shown]: all of it, or the row draws its
  /// cells itself — a row is not laid in part.
  static bool _holdsOn(
    Rect window,
    Rect shown,
    _RenderGridScreenSlot slot,
    RenderObject view,
  ) {
    final row = _inView(
      slot.getTransformTo(view),
      Offset.zero & slot.size,
    ).intersect(shown);
    return row.width <= 0 ||
        row.height <= 0 ||
        (window.left <= row.left &&
            window.top <= row.top &&
            window.right >= row.right &&
            window.bottom >= row.bottom);
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
  /// or moved ([_aRowMoved]), or what the view shows has left it — asked
  /// as the frame's scene is built: nothing is told of a move of any
  /// scrollable around this box, or of the growing of a panel it stands
  /// in, and a frame built is the one moment all of them are known to have
  /// come to rest.
  ({Rect at, int id})? _composited() {
    final screen = _screen;
    final (:toView, :shown) = _measured();
    if (shown.isEmpty) {
      return null;
    }
    final texture = screen._texture!;
    _askRowsAgain(texture, shown);
    final laid = screen._laid;
    if (laid == null ||
        !_has(MatrixUtils.transformRect(toView, laid), shown) ||
        _aRowMoved()) {
      final window = EngineScreenTexture.windowOf(texture, shown);
      final at = MatrixUtils.inverseTransformRect(toView, window);
      _layAt(
        window.topLeft,
        texture,
        appGpuGridKernels.kept.lay,
        owner!.rootNode!,
        drawnFor: at,
      );
      screen._laid = at;
    }
    return switch (texture.shownFor) {
      final _LaidFor up when texture.showsAFrame => (
        at: up.at,
        id: texture.textureId.value,
      ),
      _ => null,
    };
  }

  /// Whether a row that lays here stands elsewhere on this box than where
  /// the screen last laid it ([_RenderGridScreenSlot._standing]).
  ///
  /// 🗣️F-602 (유저 2026-11-16): 「레이어 위치관계 드래그로 바꾸면 … 프레임
  /// 블록쪽이 갱신이 이상하게되있음. 비슷한 문제 가끔 나오는 것 같은데
  /// 근본·구조적으로」 — two rows swapped by a drag each showed the other's
  /// blocks. A row that only moves keeps its picture (its slot is a repaint
  /// boundary) and paints nothing, so its paint never told the screen; the
  /// screen asks where its rows stand instead, as it asks what the view
  /// shows. Against the BOX, not the view: a scroll moves the box and its
  /// rows together, and lays nothing.
  bool _aRowMoved() {
    for (final slot in _screen._slots) {
      if (slot._laid.isNotEmpty &&
          slot._standing != slot.getTransformTo(this)) {
        return true;
      }
    }
    return false;
  }

  /// The rows whose answer — lay on the texture held, or draw their cells
  /// themselves ([_GridScreen.laysFor]) — is no longer the one they painted
  /// by, painted again after this frame: a row that lays and stands past
  /// what the texture has of [shown] now (the view grew round it, and it
  /// paints nothing by itself), and a row that drew itself and is held now.
  ///
  /// Asked as the scene is built, as where the screen is laid is
  /// ([_composited]) — and of no row where the texture has all the view
  /// shows and none drew itself: every frame but the few a bigger one
  /// opens in.
  void _askRowsAgain(ScreenTexture texture, Rect shown) {
    final screen = _screen;
    final outgrown =
        texture.width < shown.width || texture.height < shown.height;
    if (!outgrown && screen._unheld.isEmpty) {
      return;
    }
    final view = owner!.rootNode!;
    final window = EngineScreenTexture.windowOf(texture, shown);
    final again = [
      for (final slot in outgrown ? screen._slots : screen._unheld)
        if (slot._lays != _holdsOn(window, shown, slot, view)) slot,
    ];
    if (again.isEmpty) {
      return;
    }
    // Asked once: a row marked and out of what is painted is told no more
    // till it paints, and answers then.
    screen._unheld.removeAll(again);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final slot in again) {
        if (slot.attached && identical(slot._screen, screen)) {
          slot.markNeedsPaint();
        }
      }
    });
  }

  /// Whether the screen, standing at [laid], still has on it what it can
  /// of [shown] — [laid] on whole device pixels but for what the box's
  /// pixels took off it and gave back. Along a side as long as what is
  /// shown, all of it; along one [shown] has outgrown, from its start —
  /// where it is laid ([EngineScreenTexture.windowOf]) — so a frame that
  /// moved nothing lays nothing while a bigger one opens, either.
  static bool _has(Rect laid, Rect shown) =>
      _hasAlong(laid.left, laid.right, shown.left, shown.right) &&
      _hasAlong(laid.top, laid.bottom, shown.top, shown.bottom);

  static bool _hasAlong(
    double from,
    double to,
    double shownFrom,
    double shownTo,
  ) {
    final (start, end) = (from.roundToDouble(), to.roundToDouble());
    return end - start >= shownTo - shownFrom
        ? start <= shownFrom && end >= shownTo
        : start == shownFrom;
  }

  /// Presents every slot's tiles on [texture], from [origin] in the device
  /// pixels of [view] — what of them it holds, the rest of it clear — drawn
  /// for [drawnFor], where it stands in the box.
  void _layAt(
    Offset origin,
    ScreenTexture texture,
    GpuGridLay lay,
    RenderObject view, {
    required Rect drawnFor,
  }) {
    final (width, height) = (texture.width, texture.height);
    final laid = <GpuGridLaid>[];
    for (final slot in _screen._slots) {
      if (slot._laid.isEmpty) {
        continue;
      }
      slot._standing = slot.getTransformTo(this);
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
    texture.present(
      (next) => lay.lay(next, (0, 0, width, height), laid),
      drawnFor: (at: drawnFor, lay: ++_screen._laysMade),
    );
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

/// What a frame of a grid's screen was drawn for: where the box stood, and
/// which lay of the rows' tiles it shows ([_GridScreen._laysMade]).
typedef _LaidFor = ({Rect at, int lay});

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
  /// no screen over its grid, none open yet, or one that has not what the
  /// view shows of the row on it ([_GridScreen.laysFor]). A row then draws
  /// its cells itself.
  static TimelineGridScreenLaying? get laying {
    if (_debugLaying case final laying?) {
      return laying;
    }
    final slot = _RenderGridScreenSlot._painting;
    return slot != null && slot._lays ? slot : null;
  }

  /// A slot on no screen, for a row a test paints by hand: it takes the
  /// row's tiles as a slot on a screen takes them — its own
  /// [TimelineGridScreenLaying.lay], held till the row paints through it
  /// again ([TimelineGridScreenDebugSlot.paintThrough]).
  /// ↩️A test laid them through a laying of its own, which took a tile
  /// without holding it: the store's letting go of a tile the row had laid
  /// freed it there, where the screen keeps it till the row paints again
  /// (관제 2026-11-15 —
  /// a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles).
  ///
  /// Its frame up shows what the row lays where [shownUp] — else, as a
  /// screen whose GPU has not finished the lay, it shows none of it.
  @visibleForTesting
  static TimelineGridScreenDebugSlot debugSlot({bool shownUp = true}) =>
      _RenderGridScreenSlot(null, null, debugShownUp: shownUp);

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
  /// till the row paints again — holding its picture till then — and
  /// answers whether the frame up already shows what of the row it lays
  /// ([of]: the same from paint to paint, a span, a band). Where it does
  /// not, the row draws that itself as well, till a frame up does.
  ///
  /// 🚨WHAT A ROW STOPS DRAWING IS ON THE FRAME UP, or the row goes on
  /// drawing it (card a-fast-vertical-timeline-scroll-paints-row-pictures-
  /// a-notch-behind-their-labels, 관제 2026-11-25 08:1x): the frame up is
  /// the one the GPU finished last ([ScreenTexture.present]). ↩️A span the
  /// row drew while its tile was rastered stopped being drawn in the paint
  /// its tile came in, and stood on no frame till the GPU finished the one
  /// that laid it: 🧪the dialogue's ground gone under its words · the cell
  /// bars gone beside their numbers, as a fast scroll came to rest.
  bool lay(TimelineGridScreenTile tile, {required Object of});
}

/// A slot on no screen that a test paints a row through by hand
/// ([TimelineGridScreenSlot.debugSlot]).
abstract interface class TimelineGridScreenDebugSlot {
  /// Paints a row through the slot — [paint] paints it — as a paint of the
  /// slot does, letting go of what it laid before: answers what it lays
  /// now, held till it paints again or [letGo].
  List<TimelineGridScreenTile> paintThrough(void Function() paint);

  /// Lets go of what the row laid.
  void letGo();
}

class _RenderGridScreenSlot extends RenderProxyBox
    implements TimelineGridScreenLaying, TimelineGridScreenDebugSlot {
  _RenderGridScreenSlot(this._screen, this._clip, {bool debugShownUp = true})
    : _debugShownUp = debugShownUp;

  /// What a slot on no screen answers of the frame up
  /// ([TimelineGridScreenSlot.debugSlot]).
  final bool _debugShownUp;

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
      rebindListener(was, clip, markNeedsPaint);
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

  /// The lay of the screen each part of the row its last paint laid ([of])
  /// was first laid with: on the frame up once that lay is ([_layUp]).
  Map<Object, int> _laidSince = {};

  /// Whether the row's last paint laid what the frame up does not show —
  /// and so drew it itself as well, till a frame up does.
  bool _drawsWhatIsNotUp = false;

  /// Whether the row's last paint laid its tiles on the screen: the answer
  /// it was given as it painted ([_GridScreen._answers]) — false till it
  /// has painted on a screen that shows.
  bool _lays = false;

  /// Where the row stood on the screen's box when the screen last laid its
  /// tiles ([_RenderGridScreen._layAt]), asked of it as every frame's scene
  /// is built ([_RenderGridScreen._aRowMoved]).
  Matrix4? _standing;

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
    _lays = false;
    // Laid on that screen, by its count: on another, or back on it, the
    // row's parts are laid anew.
    _laidSince = {};
    screen?._unheld.remove(this);
    if (screen != null && screen._slots.remove(this)) {
      screen._rowChanged();
    }
  }

  /// The rects of [_clip] in the paint under way: asked once a paint that
  /// lays, not once a tile (타임라인/콘티 리뷰 2026-11-09 I).
  List<Rect>? _clipRects;

  @override
  bool lay(TimelineGridScreenTile tile, {required Object of}) {
    final up = _isUp(of);
    final rects = _clipRects ??= _clip?.rectsIn(size);
    for (final part in rects == null
        ? [tile]
        : [for (final rect in rects) ?_within(tile, rect)]) {
      part.picture.hold();
      _laid.add(part);
    }
    return up;
  }

  /// Whether the frame up shows [of] — laid since a lay it shows. A slot on
  /// no screen answers as a test made it
  /// ([TimelineGridScreenSlot.debugSlot]).
  bool _isUp(Object of) {
    final screen = _screen;
    if (screen == null) {
      return _debugShownUp;
    }
    final since = _laidSince[of] ??= _laidBefore[of] ?? screen._laysMade + 1;
    final up = screen._layUp;
    final shows = up != null && up >= since;
    if (!shows) {
      _drawsWhatIsNotUp = true;
    }
    return shows;
  }

  /// [_laidSince] as the paint before this one left it.
  Map<Object, int> _laidBefore = const {};

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
  void paint(PaintingContext context, Offset offset) =>
      _paintRow(() => super.paint(context, offset));

  /// The row under the slot painted by [paint], laying its tiles here: what
  /// it laid before is let go.
  void _paintRow(void Function() paint) {
    _letGo();
    _clipRects = null;
    _laidBefore = _laidSince;
    _laidSince = {};
    _drawsWhatIsNotUp = false;
    final screen = _screen;
    screen?._rowChanged();
    _lays = screen?._answers(this) ?? false;
    final outer = _painting;
    _painting = this;
    try {
      paint();
    } finally {
      _painting = outer;
    }
  }

  @override
  List<TimelineGridScreenTile> paintThrough(void Function() paint) {
    final outer = TimelineGridScreenSlot._debugLaying;
    TimelineGridScreenSlot._debugLaying = this;
    try {
      _paintRow(paint);
    } finally {
      TimelineGridScreenSlot._debugLaying = outer;
    }
    return [..._laid];
  }

  @override
  void letGo() => _letGo();
}
