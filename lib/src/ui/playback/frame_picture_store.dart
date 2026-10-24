import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../core/pin_counts.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/playback/let_go_wanted_latest.dart';
import '../canvas/display_resample.dart' show wholeLevelPixelsOutward;
import 'frame_picture_gpu.dart';

/// Texels on their way into a [FramePicture]: drawn over it at [rect] with
/// `BlendMode.src` until they land, then gone from [FramePicture.landing].
typedef LandingPatch = ({ui.Rect rect, ui.Image image});

/// A frame as its compositor gives it to [FramePictureStore.lay]: [draw]
/// draws it in world coordinates, opaque over all of [extent], and the
/// world outside [extent] is [outside].
typedef FrameDrawing = ({
  ui.Rect extent,
  ui.Color outside,
  void Function(ui.Canvas canvas) draw,
});

/// 🚨★★★A FRAME'S ONE PICTURE (one-picture-per-frame; D7-2-Q3=a, 유저
/// 2026-10-24 — 「쓸데없는 소재를 만들고 싶지 않은 것 … 극한으로 성능
/// 개선 + 법 통일까지가 목표」): the frame composited, opaque, kept where it
/// stands — an edit is written INTO it, never a new picture beside it.
///
/// The consumer draws [image] where [extent] lies in the world, paints the
/// world outside [extent] [outside], and draws every [landing] patch over
/// it with `BlendMode.src`.
///
/// 🔁ZOOMED OUT IT IS DRAWN WITH ITS OWN MIP CHAIN — `FilterQuality.medium`
/// at or under 50%. The engine gives every picture it rasters a whole chain
/// (`mipLevelCount` 11 at 3840², measured), made once, when the picture is;
/// [FramePictureStore] writes every patch into every level of it, so it is
/// never stale. Measured on the Surface Pro 11 (2026-10-24): drawn so, it
/// gives the bytes of the levels it replaces at 1/2, 1/4 and 1/8 and is
/// within 2 between them, at the cost of any image draw — where a shader
/// reading the original every frame cost 6–24 ms a frame at 50%, and any
/// shader paint over that area did (D7-2).
class FramePicture {
  FramePicture._(this.image, this.extent, this.outside);

  /// The frame, one texel a canvas pixel, texel (0, 0) at [extent]'s
  /// top left.
  final ui.Image image;

  /// Where [image] lies in the world — whole pixels, at least what was laid.
  final ui.Rect extent;

  /// The frame's colour everywhere outside [extent].
  final ui.Color outside;

  final List<LandingPatch> _landing = [];

  /// The patches drawn over [image] until their texels are in it, in the
  /// order they were made — a later one over an earlier.
  List<LandingPatch> get landing => List.unmodifiable(_landing);
}

/// The frames' pictures, each under the identity of what it shows ([K]):
/// laid whole once ([lay]), then patched where it stands ([patch]), let go
/// of by the playback budget's one order ([enforceBudget]).
class FramePictureStore<K extends Object> {
  FramePictureStore({FramePictureGpu? gpu})
    : _gpu = gpu ?? FlutterGpuFramePictures();

  final FramePictureGpu _gpu;

  final Map<K, _Entry> _entries = {};

  /// The keys patches are moving pictures to, until the first of them has
  /// its texels — and the moment it has.
  final Map<K, ({_Entry entry, Completer<void> moved})> _becoming = {};

  final PinCounts<K> _pins = PinCounts<K>();

  Set<_Entry> get _everyEntry => {
    ..._entries.values,
    for (final becoming in _becoming.values) becoming.entry,
  };

  final List<_Lay<K>> _lays = [];
  bool _laying = false;
  bool _disposed = false;
  int _clock = 0;

  /// The picture of [key], or null when there is none yet.
  FramePicture? peek(K key) {
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    entry.lastUsed = ++_clock;
    return entry.picture;
  }

  /// Lays [key]'s picture of [frame]: the store rasters what it draws over
  /// its extent, widened to whole texels of the deepest level its patches
  /// write ([wholeLevelPixelsOutward]).
  ///
  /// Lays wait their turn, one at a time; [shownNow] goes to the front —
  /// the frame on screen before any made ahead of it. A key a patch is
  /// moving a picture to is the patch's to make.
  Future<FramePicture?> lay(
    K key,
    FrameDrawing frame, {
    bool shownNow = false,
  }) async {
    final there = peek(key);
    if (there != null) {
      return there;
    }
    final becoming = _becoming[key];
    if (becoming != null) {
      await becoming.moved.future;
      return peek(key);
    }
    for (final queued in _lays) {
      if (queued.key == key) {
        return queued.done.future;
      }
    }
    final lay = _Lay<K>(key, frame);
    if (shownNow) {
      _lays.insert(0, lay);
    } else {
      _lays.add(lay);
    }
    unawaited(_pump());
    return lay.done.future;
  }

  /// Moves the picture of [from] to [to], [rect] drawn anew by [draw] — in
  /// world coordinates, opaque over all of it, as a lay's is. The store
  /// widens [rect] to the picture's grid; the caller hands it as it is.
  ///
  /// The picture answers to [to] once the patch's texels are drawn, with
  /// them [FramePicture.landing] over it; until then [from] still shows
  /// what it was. [from] may be [to] — a stroke's next step — and a patch
  /// may move a picture an earlier patch is still moving.
  ///
  /// Answers false, and lets go of [from]'s picture, where it cannot: no
  /// picture under [from], no GPU to write with, or [rect] reaching past
  /// the picture's extent — a picture does not grow; lay [to] anew.
  bool patch({
    required K from,
    required K to,
    required ui.Rect rect,
    required void Function(ui.Canvas canvas) draw,
  }) {
    final entry = _entries[from] ?? _becoming[from]?.entry;
    if (entry == null) {
      return false;
    }
    final widened = wholeLevelPixelsOutward(rect, entry.patchedLevels);
    if (entry.held == null || !_covers(entry.picture.extent, widened)) {
      _letGo(entry);
      return false;
    }
    final asked = _Patch<K>(from, to, widened, draw);
    _becoming[to] = (entry: entry, moved: asked.moved);
    entry.renders = entry.renders.then((_) => _renderPatch(entry, asked));
    return true;
  }

  /// Answers once every patch has landed — for a caller that must read the
  /// pictures' own texels rather than draw them with their landing patches.
  Future<void> settled() async {
    for (final entry in _everyEntry) {
      await entry.renders;
      await entry.writes;
    }
  }

  /// The bytes the pictures and their landing patches hold, by the app's
  /// one image estimate ([estimatedImageBytes]) — the budgets it shares are
  /// compared in that word.
  ///
  /// ⚠️The engine allocates a whole mip chain beside each, a third more
  /// than this says (measured, D7-2 2026-10-24) — as for every picture any
  /// cache holds; the estimate is the app's to change, in one place.
  int get estimatedBytes {
    var total = 0;
    for (final entry in _entries.values) {
      total += entry.bytes;
    }
    return total;
  }

  /// Lets go of pictures until at or under [maxBytes], by the playback
  /// budget's one order ([letGoWantedLatest]): the ones wanted LATEST first
  /// ([wantedAt]), never one pinned.
  bool enforceBudget({
    required int maxBytes,
    int? Function(K key)? wantedAt,
    int? laterThan,
  }) => letGoWantedLatest(
    entries: [
      for (final entry in _entries.entries)
        // ⛔A pinned picture is ON SCREEN: letting it go frees nothing (the
        // holder's clone shares the pixels) and puts the very picture the
        // canvas draws back on the cold path (LayerFrameImageCache, A6).
        if (!_pins.isPinned(entry.key)) entry,
    ],
    heldBytes: estimatedBytes,
    maxBytes: maxBytes,
    wantedAt: (entry) => wantedAt?.call(entry.key),
    lastUsed: (entry) => entry.value.lastUsed,
    bytesOf: (entry) => entry.value.bytes,
    letGo: (entry) => _letGo(entry.value),
    laterThan: laterThan,
  );

  /// Declares a holder of [key]'s picture — one the screen draws. Balanced
  /// by [releasePin]; counts nest.
  void retainPin(K key) => _pins.retain(key);

  void releasePin(K key) => _pins.release(key);

  /// The bytes of every pinned key's picture — what the screen holds.
  int get pinnedBytes {
    var total = 0;
    for (final key in _pins.keys) {
      total += _entries[key]?.bytes ?? 0;
    }
    return total;
  }

  void dispose() {
    _disposed = true;
    for (final lay in _lays) {
      lay.done.complete(null);
    }
    _lays.clear();
    for (final entry in _everyEntry) {
      _letGo(entry);
    }
  }

  Future<void> _pump() async {
    if (_laying) {
      return;
    }
    _laying = true;
    try {
      while (_lays.isNotEmpty) {
        final lay = _lays.removeAt(0);
        try {
          lay.done.complete(await _layNow(lay));
        } on Object catch (error, stack) {
          lay.done.completeError(error, stack);
        }
      }
    } finally {
      _laying = false;
    }
  }

  Future<FramePicture?> _layNow(_Lay<K> lay) async {
    final (:extent, :patchedLevels) = _shapeOf(lay.frame.extent);
    if (extent.isEmpty) {
      return null;
    }
    final image = await _gpu.render(
      _recorded(extent, lay.frame.draw),
      extent.width.toInt(),
      extent.height.toInt(),
    );
    if (_disposed) {
      image.dispose();
      return null;
    }
    final held = _gpu.hold(image);
    final entry = _Entry(
      FramePicture._(image, extent, lay.frame.outside),
      held: held,
      levels: held == null ? 1 : _gpu.levelsOf(held),
      patchedLevels: patchedLevels,
    )..lastUsed = ++_clock;
    _entries[lay.key] = entry;
    return entry.picture;
  }

  Future<void> _renderPatch(_Entry entry, _Patch<K> asked) async {
    final image = await _gpu.render(
      _recorded(asked.rect, asked.draw),
      asked.rect.width.toInt(),
      asked.rect.height.toInt(),
    );
    if (_becoming[asked.to]?.moved == asked.moved) {
      _becoming.remove(asked.to);
    }
    if (entry.gone) {
      image.dispose();
      asked.moved.complete();
      return;
    }
    // The frame `to` IS the picture with this patch over it, from the
    // moment the patch has texels — and not a moment before.
    if (_entries[asked.from] == entry) {
      _entries.remove(asked.from);
    }
    _entries[asked.to] = entry;
    final landing = (rect: asked.rect, image: image);
    entry.picture._landing.add(landing);
    asked.moved.complete();
    entry.writes = entry.writes.then((_) => _land(entry, landing));
  }

  Future<void> _land(_Entry entry, LandingPatch landing) async {
    final picture = entry.picture;
    final at = landing.rect.topLeft - picture.extent.topLeft;
    final x = at.dx.toInt();
    final y = at.dy.toInt();
    final halvings = await _halvings(landing.image, entry.patchedLevels);
    if (!entry.gone) {
      await _gpu.write(entry.held!, [
        (
          source: landing.image,
          from: _whole(landing.image),
          x: x,
          y: y,
          level: 0,
        ),
        for (final (index, spot) in halvings.spots.indexed)
          (
            source: halvings.atlas!,
            from: spot,
            x: x >> (index + 1),
            y: y >> (index + 1),
            level: index + 1,
          ),
      ]);
      await _remakeBelowPatchedLevels(entry);
    }
    halvings.atlas?.dispose();
    // Off the picture only once every level has it — a zoomed-out view
    // would otherwise show the old texels for as long as the deep levels
    // take.
    picture._landing.remove(landing);
    landing.image.dispose();
  }

  /// The levels under [_Entry.patchedLevels], made again whole from that
  /// level — which the picture itself gives exactly ([_readAt]).
  Future<void> _remakeBelowPatchedLevels(_Entry entry) async {
    final from = entry.patchedLevels;
    final below = entry.levels - 1 - from;
    if (below <= 0 || entry.gone) {
      return;
    }
    final image = entry.picture.image;
    final width = math.max(1, image.width >> from);
    final height = math.max(1, image.height >> from);
    final level = await _readAt(image, [
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ], width, height);
    final halvings = await _halvings(level, below);
    if (!entry.gone) {
      await _gpu.write(entry.held!, [
        for (final (index, spot) in halvings.spots.indexed)
          (
            source: halvings.atlas!,
            from: spot,
            x: 0,
            y: 0,
            level: from + index + 1,
          ),
      ]);
    }
    level.dispose();
    halvings.atlas?.dispose();
  }

  /// The first [count] halvings of [image], side by side in one raster
  /// ([_readAt]). Exact where the sides halve evenly; under that, the GPU's
  /// own reading of a side that does not.
  Future<({ui.Image? atlas, List<ui.Rect> spots})> _halvings(
    ui.Image image,
    int count,
  ) async {
    if (count <= 0) {
      return (atlas: null, spots: const <ui.Rect>[]);
    }
    final spots = <ui.Rect>[];
    var across = 0;
    var tallest = 0;
    for (var j = 1; j <= count; j += 1) {
      final width = math.max(1, image.width >> j);
      final height = math.max(1, image.height >> j);
      spots.add(
        ui.Rect.fromLTWH(
          across.toDouble(),
          0,
          width.toDouble(),
          height.toDouble(),
        ),
      );
      across += width;
      tallest = math.max(tallest, height);
    }
    return (
      atlas: await _readAt(image, spots, across, tallest),
      spots: spots,
    );
  }

  /// [image] drawn whole into each of [spots] of one [width] x [height]
  /// raster, under `FilterQuality.medium`: drawn at 1/2^k a side so, the
  /// GPU samples [image]'s own level k — the engine's halving, the one the
  /// picture's chain was made with — so a patch's levels are the very code
  /// of the levels round it, on any backend (measured on the Surface Pro
  /// 11: the levels it replaced, byte for byte, 2026-10-24).
  Future<ui.Image> _readAt(
    ui.Image image,
    List<ui.Rect> spots,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    for (final spot in spots) {
      canvas.drawImageRect(image, _whole(image), spot, paint);
    }
    final recorded = recorder.endRecording();
    try {
      return await _gpu.render(recorded, width, height);
    } finally {
      recorded.dispose();
    }
  }

  void _letGo(_Entry entry) {
    entry.gone = true;
    _entries.removeWhere((_, value) => value == entry);
    _becoming.removeWhere((_, value) {
      if (value.entry != entry) {
        return false;
      }
      if (!value.moved.isCompleted) {
        value.moved.complete();
      }
      return true;
    });
    // The GPU may still be writing it: let go once its writes are done.
    unawaited(
      entry.writes.whenComplete(() {
        entry.picture.image.dispose();
        for (final patch in entry.picture._landing) {
          patch.image.dispose();
        }
        entry.picture._landing.clear();
      }),
    );
  }
}

/// The levels a patch writes from its own texels: as many halvings as it
/// takes for the picture's longer side to come to about [_wholeLevelSide].
/// Below them the levels are made again whole, which at that size costs
/// next to nothing; above them a patch is widened to whole texels of the
/// deepest, so each of its halvings is exact.
int _patchedLevelsFor(int width, int height) {
  var levels = 0;
  while ((math.max(width, height) >> levels) > _wholeLevelSide) {
    levels += 1;
  }
  return levels;
}

const int _wholeLevelSide = 256;

/// [extent] widened to whole texels of the deepest patched level — the
/// grid a patch is widened to, so a widened patch inside it stays inside.
({ui.Rect extent, int patchedLevels}) _shapeOf(ui.Rect extent) {
  if (extent.isEmpty) {
    return (extent: ui.Rect.zero, patchedLevels: 0);
  }
  final levels = _patchedLevelsFor(
    extent.width.ceil(),
    extent.height.ceil(),
  );
  return (
    extent: wholeLevelPixelsOutward(extent, levels),
    patchedLevels: levels,
  );
}

bool _covers(ui.Rect extent, ui.Rect rect) =>
    !rect.isEmpty &&
    rect.left >= extent.left &&
    rect.top >= extent.top &&
    rect.right <= extent.right &&
    rect.bottom <= extent.bottom;

ui.Rect _whole(ui.Image image) =>
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

/// A picture of what [draw] draws over [rect] in world coordinates, with
/// [rect]'s top left at its origin.
ui.Picture _recorded(ui.Rect rect, void Function(ui.Canvas canvas) draw) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..translate(-rect.left, -rect.top)
    ..clipRect(rect);
  draw(canvas);
  return recorder.endRecording();
}

class _Entry {
  _Entry(
    this.picture, {
    required this.held,
    required this.levels,
    required this.patchedLevels,
  });

  final FramePicture picture;

  /// The texture behind [picture]'s image — null where there is no GPU to
  /// write with, and then the picture cannot be patched.
  final Object? held;

  final int levels;
  final int patchedLevels;

  int lastUsed = 0;
  bool gone = false;

  /// Patch rasters, one after another: a patch's picture answers to its key
  /// in the order the patches were asked for.
  Future<void> renders = Future<void>.value();

  /// Writes into the texture, one patch's after another's — a patch's deep
  /// levels are made from the levels the patches before it wrote.
  Future<void> writes = Future<void>.value();

  int get bytes {
    final image = picture.image;
    var total = estimatedImageBytes(image.width, image.height);
    for (final patch in picture._landing) {
      total += estimatedImageBytes(patch.image.width, patch.image.height);
    }
    return total;
  }
}

class _Lay<K> {
  _Lay(this.key, this.frame);

  final K key;
  final FrameDrawing frame;
  final Completer<FramePicture?> done = Completer<FramePicture?>();
}

/// One [FramePictureStore.patch], widened, until its picture has moved.
class _Patch<K> {
  _Patch(this.from, this.to, this.rect, this.draw);

  final K from;
  final K to;
  final ui.Rect rect;
  final void Function(ui.Canvas canvas) draw;
  final Completer<void> moved = Completer<void>();
}
