import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../core/pin_counts.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/playback/let_go_wanted_latest.dart';
import '../canvas/display_resample.dart'
    show frameGridOutward, wholeLevelPixelsOutward;
import '../debug/input_inspector.dart';
import 'frame_picture_gpu.dart';

/// A patch's texels, rendered, on their way into its picture at [rect].
typedef _Texels = ({ui.Rect rect, ui.Image image});

/// A patch rendered — its texels, none for a move — on its way into its
/// picture.
typedef _Rendered<K> = ({_Patch<K> patch, ui.Image? image});

/// The [from] rect of [image] drawn into the [to] rect of a raster.
typedef _PictureRead = ({ui.Image image, ui.Rect from, ui.Rect to});

/// A frame as its compositor gives it to [FramePictureStore.lay]: [draw]
/// draws it in world coordinates over all of [extent] as the canvas's
/// display buffer holds it — the paper and every row, and clear wherever
/// neither lays anything — and the world outside [extent] is [outside].
///
/// 🚨Not opaque past the paper (one-picture-per-frame, 2026-10-24): the
/// pasteboard's colour is laid under a frame by whoever shows it — a track
/// stack lays it under its stage track alone and lets the tracks over that
/// one show through — so a picture holding it would be one view's. The
/// compositor's [outside] is clear for the same reason
/// (`StackedFrame`).
typedef FrameDrawing = ({
  ui.Rect extent,
  ui.Color outside,
  void Function(ui.Canvas canvas) draw,
});

/// 🚨★★★A FRAME'S ONE PICTURE (one-picture-per-frame; D7-2-Q3=a, 유저
/// 2026-10-24 — 「쓸데없는 소재를 만들고 싶지 않은 것 … 극한으로 성능
/// 개선 + 법 통일까지가 목표」): the frame composited, kept where it stands
/// — an edit is written INTO it, never a new picture beside it.
///
/// The consumer draws [image] where [extent] lies in the world and paints
/// the world outside [extent] [outside] — nothing else: no patch is ever
/// drawn over it.
///
/// 🔁ZOOMED OUT IT IS DRAWN WITH ITS OWN MIP CHAIN — `FilterQuality.medium`
/// at or under 50%. The engine gives every picture it rasters a whole chain
/// (`mipLevelCount` 11 at 3840², measured), made once, when the picture is;
/// [FramePictureStore] writes every patch into every level of it, at once
/// ([FramePictureStore.patch]). Measured on the Surface Pro 11
/// (2026-10-24): a patch's levels so written are the bytes of the levels
/// they replace at 1/2, 1/4 and 1/8 and within 2 between them, at the cost
/// of any image draw — where a shader reading the original every frame
/// cost 6–24 ms a frame at 50%, and any shader paint over that area did
/// (D7-2).
class FramePicture {
  FramePicture._(this.image, this.extent, this.outside);

  /// The frame, one texel a canvas pixel, texel (0, 0) at [extent]'s
  /// top left.
  final ui.Image image;

  /// Where [image] lies in the world — whole pixels, at least what was laid.
  final ui.Rect extent;

  /// The frame's colour everywhere outside [extent].
  final ui.Color outside;
}

/// The frames' pictures, each under the identity of what it shows ([K]):
/// laid whole once ([lay]), then patched where it stands ([patch]), let go
/// of by the playback budget's one order ([enforceBudget]).
class FramePictureStore<K extends Object> {
  FramePictureStore({FramePictureGpu? gpu})
    : _gpu = gpu ?? FlutterGpuFramePictures();

  final FramePictureGpu _gpu;

  final Map<K, _Entry<K>> _entries = {};

  /// The keys patches are moving pictures to, until the first of them is in
  /// its picture — and the moment it is.
  final Map<K, ({_Entry<K> entry, _Patch<K> patch})> _becoming = {};

  final PinCounts<K> _pins = PinCounts<K>();

  Set<_Entry<K>> get _everyEntry => {
    ..._entries.values,
    for (final becoming in _becoming.values) becoming.entry,
  };

  final List<_Lay<K>> _lays = [];
  bool _laying = false;
  bool _disposed = false;
  int _clock = 0;

  /// Whether [key]'s picture is there — asked by a warmer and a ready bar
  /// over frames no screen draws now, so unlike [peek] it is no use of the
  /// picture: what the budget lets go of last among equals is what a
  /// screen drew last.
  bool holds(K key) => _entries.containsKey(key);

  /// [holds] for every key [test] passes: whether any is there.
  bool holdsWhere(bool Function(K key) test) => _entries.keys.any(test);

  /// The bytes [key]'s picture holds ([estimatedBytes]' word), or null
  /// where there is none — what a warmer's walk weighs the window by; no
  /// use of the picture either ([holds]).
  int? bytesOf(K key) => _entries[key]?.bytes;

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
      await becoming.patch.moved;
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
  /// world coordinates over all of it, as a lay's is ([FrameDrawing]): the
  /// patch's texels, clear ones too, take the place of the picture's there.
  /// The store widens [rect] to the picture's grid; the caller hands it as
  /// it is.
  ///
  /// 🚨★★★IN PLACE, NEVER OVER — the display buffer's two lessons. The
  /// patch is drawn on nothing, a picture of [rect] alone ([recordedOver]),
  /// and its texels replace the picture's. ↩️The buffer recomposed a
  /// region OVER the pixels it carried: ink not fully opaque blended with
  /// its own previous frame unless the region was cleared first, and where
  /// the new frame drew nothing the old one stayed — F-104, 유저 2026-09-12
  /// 「페이스트 보드에 이전 프레임의 그림이 남아있음」, a carry written without
  /// the clear. And a blend that escaped the region's clip laid a second
  /// copy of itself over the carried composite on every patch — F-287, 유저
  /// 실기 2026-10-04 · 10-05 · 10-12: two multiply rows went darker wherever
  /// they lay with every stroke on a row above them. A patch of its own
  /// size has nothing under it to blend with and nowhere past it to reach.
  ///
  /// The picture answers to [to] once the patch's texels are in it, at
  /// every level ([_written]); until then [from] still shows what it was.
  /// [from] may be [to] — a stroke's next step — and a patch may move a
  /// picture an earlier patch is still moving.
  ///
  /// Answers false, and lets go of [from]'s picture, where it cannot: no
  /// picture under [from], no GPU to write with, or [rect] reaching past
  /// the picture's extent — a picture does not grow; lay [to] anew.
  ///
  /// [draw] is called before this answers, not when the patch's turn to
  /// render comes: a stroke's step draws the overlay's tile pictures, which
  /// the next step replaces and the pen's lift hands on or lets go of
  /// (brush/rendering, 2026-10-24). A lay's drawing waits for its turn —
  /// its key is the frame's signature, so what it draws does not change.
  bool patch({
    required K from,
    required K to,
    required ui.Rect rect,
    required void Function(ui.Canvas canvas) draw,
  }) {
    final entry = _entries[from] ?? _becoming[from]?.entry;
    if (entry == null) {
      _F509s.count('pNoEntry');
      return false;
    }
    final widened = wholeLevelPixelsOutward(rect, entry.patchedLevels);
    if (entry.held == null || !_covers(entry.picture.extent, widened)) {
      _F509s.count(entry.held == null ? 'pNoHeld' : 'pNoCover');
      _letGo(entry);
      return false;
    }
    _F509s.count('pOk');
    final asked = _Patch<K>(from, to, widened, recordedOver(widened, draw));
    _becoming[to] = (entry: entry, patch: asked);
    entry.renders = entry.renders.then((_) => _renderPatch(entry, asked));
    return true;
  }

  /// Moves the picture of [from] to [to] as it is, in its turn behind the
  /// patches still on their way into it — the caller vouches that its
  /// texels are [to]'s: a stroke that lands moves the frame it was drawn
  /// on, every step of it patched in already (one-picture-per-frame ②-4).
  /// Answers false where there is no picture under [from].
  bool move({required K from, required K to}) {
    final entry = _entries[from] ?? _becoming[from]?.entry;
    if (entry == null) {
      return false;
    }
    final asked = _Patch<K>(from, to, ui.Rect.zero, null);
    _becoming[to] = (entry: entry, patch: asked);
    entry.renders = entry.renders.then((_) => _renderPatch(entry, asked));
    return true;
  }

  /// Completes once the last patch or [move] asked for to [key] is in its
  /// picture, and [key] answers with it — null where none is on its way.
  Future<void>? landingOf(K key) => _becoming[key]?.patch.moved;

  /// Answers once every patch asked for is in its picture.
  Future<void> settled() async {
    for (final entry in _everyEntry) {
      await entry.renders;
      await entry.writes;
    }
  }

  /// The bytes the pictures hold, by the app's one image estimate
  /// ([estimatedImageBytes]) — the budgets it shares are compared in that
  /// word.
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

  /// Lets go of [key]'s picture — under every key it answers to, and the
  /// one a patch is moving it to — and answers whoever waits on it.
  void letGo(K key) {
    final entry = _entries[key] ?? _becoming[key]?.entry;
    if (entry != null) {
      _letGo(entry);
    }
  }

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
    final image = await _rendered(
      recordedOver(extent, lay.frame.draw),
      extent.width.toInt(),
      extent.height.toInt(),
    );
    if (_disposed) {
      image.dispose();
      return null;
    }
    final held = _gpu.hold(image);
    _F509s.count(held == null ? 'layNoHeld' : 'lay');
    final entry = _Entry<K>(
      FramePicture._(image, extent, lay.frame.outside),
      held: held,
      levels: held == null ? 1 : _gpu.levelsOf(held),
      patchedLevels: patchedLevels,
    )..lastUsed = ++_clock;
    _entries[lay.key] = entry;
    return entry.picture;
  }

  Future<void> _renderPatch(_Entry<K> entry, _Patch<K> asked) async {
    final recorded = asked.recorded;
    final image = recorded == null
        ? null
        : await _rendered(
            recorded,
            asked.rect.width.toInt(),
            asked.rect.height.toInt(),
          );
    entry.waiting.add((patch: asked, image: image));
    entry.writes = entry.writes.then((_) => _writeWaiting(entry));
  }

  /// Writes every patch that has texels and is not in yet into its picture
  /// in one write ([_written]), then moves the picture to each one's key in
  /// the order they were asked for — a [move] waiting among them too.
  ///
  /// 🔬A batch, not a write a patch (D7-2, 2026-10-24): on the Surface Pro
  /// 11 a 3840² picture took about 57 ms to land one patch — five waits on
  /// the GPU — so a stroke patching every vsync fell 600 patches behind.
  /// Patches that render while a batch is written wait for the next one.
  Future<void> _writeWaiting(_Entry<K> entry) async {
    if (entry.waiting.isEmpty) {
      return;
    }
    final batch = List.of(entry.waiting);
    entry.waiting.clear();
    final texels = <_Texels>[
      for (final (:patch, :image) in batch)
        if (image != null) (rect: patch.rect, image: image),
    ];
    var written = true;
    try {
      if (texels.isNotEmpty && !entry.gone) {
        written = await _written(entry, texels);
      }
    } finally {
      for (final patch in texels) {
        patch.image.dispose();
      }
    }
    _F509s.count(
      texels.isEmpty
          ? 'wbMove'
          : entry.gone
          ? 'wbGone'
          : written
          ? 'wbOk'
          : 'wbFail',
    );
    if (!written) {
      // Not in the picture: no key may answer with it.
      _letGo(entry);
    }
    for (final (:patch, image: _) in batch) {
      _arrived(entry, patch);
    }
  }

  /// Writes [batch] into [entry]'s picture — a later patch over an earlier
  /// — at every level of it: the base, each patch's own halvings down to
  /// the deepest patched level, and every level under that made again
  /// whole, once for them all ([_run]). Answers whether the GPU did.
  ///
  /// 🚨★★★EVERY LEVEL WITH EVERY BATCH, AND THE PICTURE ANSWERS ONLY THEN —
  /// the screen draws the picture and nothing over it (F-465, 유저 채팅
  /// 2026-10-26 「그럼 그냥 바로 바로쓰기로 바꾸고, 잔재들 없애고, 최대한
  /// 개선해보자」).
  ///
  /// ↩️The base went in with each batch and the levels under it waited —
  /// for the patches to pause 200 ms, or for 64 of them or 4 Mi texels,
  /// laid again as one at that cap, each write taking its turn in the
  /// quiet between held frames — the patches drawn over the picture
  /// meanwhile (D7-2, 2026-10-24). On the Surface Pro 11 (release, GLES, a
  /// 3840² frame patched every vsync) every level with each batch had put
  /// a stroke's frames at p90 19–35 ms, 21–44% of them past 16.7 ms: a
  /// level under the base is written only from a buffer that a copy out of
  /// the GPU fills, and on GLES that copy holds the raster thread until
  /// the GPU has done everything before it — one frame 18–114 ms. The base
  /// alone cost nothing (p90 4.1–6.1 ms). ⛔Laying the picture again on the
  /// GPU, with no copy out: about 200 ms a 3840² lay. ⛔The engine's
  /// `toByteData` for the copy out: no better.
  /// But a patch drawn over its picture made two images of one frame, and
  /// their edges drew apart — zoomed out, turned, at the page's own edge
  /// (F-465, 유저 실기 2026-10-25) — and every fix widened the picture or
  /// cut the patch to a grid. Written so on the main PC (2026-10-26,
  /// Windows, GLES, profile, 1080p and 4K, 120 steps at 100% and fitted,
  /// the two in turn in one run): raster p50 0.5–0.7 ms and p90 0.7–1.2 ms
  /// against 0.7–1.5 and 1.2–2.3, no frame late against 0–8, every level
  /// in at p50 5–7 ms against about 250 ms — a step showing 0–4 frames
  /// later than drawn over (p50 1.6–7.3 ms, at most 29 ms).
  ///
  /// 🔬One copy out a write (D7-2, 2026-10-24): the levels go out end to end
  /// in one raster ([_run]); its 1,000–28,000 rows rastered in 4–144 ms on
  /// the Surface Pro 11 and held no frame doing it — the copy out did.
  ///
  /// 🔬ONE SUBMISSION, THE RASTERS FIRST (F-465, 2026-10-26): ↩️the base
  /// went to the GPU on its own and was waited on before the levels under
  /// it were rastered — five waits a batch. Both in one, measured in turn
  /// in one run (120 steps, 1080p and 4K, 100% and fitted, 12 runs each;
  /// a step's p50 / p90 into its picture, late frames summed): the Surface
  /// Pro 11 (120 Hz) 13.1 / 20.9 ms and 136 late → 10.6 / 16.9 ms and 85,
  /// the main PC (144 Hz) 4.0 / 6.2 ms and 1 → 3.9 / 6.2 ms and 1. ⛔Not
  /// answered at the submission rather than its completion: fastest on the
  /// main PC (3.0 ms), but 190 late on the Surface. ⛔Not the deepest level
  /// or the patch rastered at once (`toImageSync`): later on both.
  ///
  /// ⛔⛔TWO WAITS A BATCH, TRIED AGAIN AND REVERTED (2026-10-28, card
  /// s5-stroke-trails-on-the-heavy-cut ②b, 유저 답 「쓰기 왕복을 줄인다
  /// (구조는 그대로)」): each patch laid whole at the top of one run with
  /// the halvings under it, the patch and the deepest level rastered at
  /// once, the base copied texture to texture and the levels through one
  /// buffer, in one submission (`0fee89202`..`2defd8c03`). The main PC
  /// under load: a step p50 73–87 → 42–54 ms. The Surface Pro 11 (release,
  /// mouse, six runs in turn, S5_BA cut 352 and a new project alike): a
  /// step showed 16 ms later — p50 33 → 50 ms, p90 49 → 67 ms — and vsync
  /// to raster end p50 2.9–4.7 → 11.3–14.2 ms, the UI and the raster
  /// themselves unchanged. 🚨The main PC does not speak for the Surface
  /// here: measure a change to these waits there before it lands.
  Future<bool> _written(_Entry<K> entry, List<_Texels> batch) async {
    final picture = entry.picture;
    final patched = entry.patchedLevels;
    final below = entry.levels - 1 - patched;
    final deepest = below > 0 ? await _deepestPatchedLevel(entry, batch) : null;
    final run = await _run([
      for (final patch in batch)
        (
          image: patch.image,
          level: 0,
          x: _xOf(picture, patch.rect),
          y: _yOf(picture, patch.rect),
          count: patched,
        ),
      if (deepest != null)
        (image: deepest, level: patched, x: 0, y: 0, count: below),
    ]);
    deepest?.dispose();
    final image = run.image;
    try {
      return entry.gone ||
          await _gpu.write(
            entry.held!,
            [
              for (final patch in batch)
                (
                  source: patch.image,
                  x: _xOf(picture, patch.rect),
                  y: _yOf(picture, patch.rect),
                ),
            ],
            image == null ? null : (run: image, spans: run.spans),
          );
    } finally {
      image?.dispose();
    }
  }

  /// [asked] has its texels in [entry]'s picture, or never will: its key
  /// answers with the picture, if it is still held, and whoever waits for
  /// it is answered.
  void _arrived(_Entry<K> entry, _Patch<K> asked) {
    if (identical(_becoming[asked.to]?.patch, asked)) {
      _becoming.remove(asked.to);
    }
    if (!entry.gone) {
      if (_entries[asked.from] == entry) {
        _entries.remove(asked.from);
      }
      _entries[asked.to] = entry;
    }
    asked.answer();
  }

  /// The picture's deepest patched level with [batch] in it: the level as
  /// the picture holds it, each patch drawn over its place there — the
  /// reading its own write lays at that level ([_readAt]) — whole, so the
  /// levels under it are its halvings.
  Future<ui.Image> _deepestPatchedLevel(_Entry<K> entry, List<_Texels> batch) {
    final picture = entry.picture;
    final level = entry.patchedLevels;
    final width = math.max(1, picture.image.width >> level);
    final height = math.max(1, picture.image.height >> level);
    final scale = 1.0 / (1 << level);
    return _readAt([
      (
        image: picture.image,
        from: _whole(picture.image),
        to: ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ),
      for (final patch in batch)
        (
          image: patch.image,
          from: _whole(patch.image),
          to: _scaled(patch.rect.shift(-picture.extent.topLeft), scale),
        ),
    ], width, height);
  }

  /// The halvings 1 to `count` of each of [sources], their texels end to
  /// end, row after row, wrapping at [_runWidth] — as one copy out of the
  /// GPU gives them back and as a level is written from it, row after row
  /// ([FramePictureGpu.write]) — in one raster ([_readAt]); with the
  /// [RunSpan] that lays each halving where its source lies, at `level`
  /// and (`x`, `y`), halved. No image where there is no halving at all.
  /// Exact where the sides halve evenly; under that, the GPU's own reading
  /// of a side that does not.
  Future<({ui.Image? image, List<RunSpan> spans})> _run(
    List<({ui.Image image, int level, int x, int y, int count})> sources,
  ) async {
    final reads = <_PictureRead>[];
    final spans = <RunSpan>[];
    var at = 0;
    for (final (:image, :level, :x, :y, :count) in sources) {
      for (var j = 1; j <= count; j += 1) {
        final width = math.max(1, image.width >> j);
        final height = math.max(1, image.height >> j);
        spans.add((
          start: at,
          width: width,
          height: height,
          x: x >> j,
          y: y >> j,
          level: level + j,
        ));
        reads.addAll(_rowsOf(image, width, height, at));
        at += width * height;
      }
    }
    if (at == 0) {
      return (image: null, spans: spans);
    }
    final rows = (at + _runWidth - 1) ~/ _runWidth;
    return (image: await _readAt(reads, _runWidth, rows), spans: spans);
  }

  /// Each of [reads] — a later one in place of an earlier — in one [width]
  /// x [height] raster, under `FilterQuality.medium`: drawn at 1/2^k a side
  /// so, the GPU samples the image's own level k — the engine's halving,
  /// the one the picture's chain was made with — so a patch's levels are
  /// the very code of the levels round it, on any backend (measured on the
  /// Surface Pro 11: the levels it replaced, byte for byte, 2026-10-24).
  /// Drawn 1:1 on whole pixels, it is a copy.
  Future<ui.Image> _readAt(List<_PictureRead> reads, int width, int height) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.medium
      ..blendMode = ui.BlendMode.src;
    for (final (:image, :from, :to) in reads) {
      canvas.drawImageRect(image, from, to, paint);
    }
    return _rendered(recorder.endRecording(), width, height);
  }

  /// [recorded] rastered, and let go of — rendered or not.
  Future<ui.Image> _rendered(ui.Picture recorded, int width, int height) async {
    try {
      return await _gpu.render(recorded, width, height);
    } finally {
      recorded.dispose();
    }
  }

  void _letGo(_Entry<K> entry) {
    _F509s.count('letGo');
    entry.gone = true;
    _entries.removeWhere((_, value) => value == entry);
    _becoming.removeWhere((_, value) {
      if (value.entry != entry) {
        return false;
      }
      value.patch.answer();
      return true;
    });
    // The GPU may still be writing it: let go once its writes are done.
    unawaited(entry.writes.whenComplete(entry.picture.image.dispose));
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

/// Where the picture a store lays of a frame drawn over [extent] lies
/// ([FramePicture.extent]) — what it weighs before it is made.
ui.Rect pictureExtentOf(ui.Rect extent) => _shapeOf(extent).extent;

/// [extent] on the grid a frame's picture lies on ([frameGridOutward]) —
/// whole texels of the deepest patched level too, the grid a patch is
/// widened to, so a widened patch inside it stays inside. A page under the
/// texture cap patches fewer levels than a canvas reads, and the second
/// grid adds nothing.
({ui.Rect extent, int patchedLevels}) _shapeOf(ui.Rect extent) {
  if (extent.isEmpty) {
    return (extent: ui.Rect.zero, patchedLevels: 0);
  }
  final levels = _patchedLevelsFor(
    extent.width.ceil(),
    extent.height.ceil(),
  );
  return (
    extent: wholeLevelPixelsOutward(frameGridOutward(extent), levels),
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

ui.Rect _scaled(ui.Rect rect, double scale) => ui.Rect.fromLTRB(
  rect.left * scale,
  rect.top * scale,
  rect.right * scale,
  rect.bottom * scale,
);

/// The run's width ([FramePictureStore._run]): the widest texture every
/// GPU the app runs on takes — OpenGL ES 3's floor.
const int _runWidth = 2048;

/// Where [rect] lies in [picture]'s base level.
int _xOf(FramePicture picture, ui.Rect rect) =>
    (rect.left - picture.extent.left).toInt();

int _yOf(FramePicture picture, ui.Rect rect) =>
    (rect.top - picture.extent.top).toInt();

/// The reads that lay [image] halved to [width] x [height] into a run from
/// texel [at] on: one a row, and one more each time a row wraps.
Iterable<_PictureRead> _rowsOf(
  ui.Image image,
  int width,
  int height,
  int at,
) sync* {
  final across = image.width / width;
  final down = image.height / height;
  for (var row = 0; row < height; row += 1) {
    var done = 0;
    while (done < width) {
      final start = at + row * width + done;
      final x = start % _runWidth;
      final piece = math.min(width - done, _runWidth - x);
      yield (
        image: image,
        from: ui.Rect.fromLTWH(done * across, row * down, piece * across, down),
        to: ui.Rect.fromLTWH(
          x.toDouble(),
          (start ~/ _runWidth).toDouble(),
          piece.toDouble(),
          1,
        ),
      );
      done += piece;
    }
  }
}

/// A picture of what [draw] draws over [rect] in world coordinates, with
/// [rect]'s top left at its origin.
ui.Picture recordedOver(ui.Rect rect, void Function(ui.Canvas canvas) draw) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..translate(-rect.left, -rect.top)
    ..clipRect(rect);
  draw(canvas);
  return recorder.endRecording();
}

class _Entry<K> {
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

  /// Writes into the texture, one after another — the deep levels a write
  /// makes are made from the levels the writes before it wrote.
  Future<void> writes = Future<void>.value();

  /// The patches rendered that no write has taken yet, in the order they
  /// were asked for, with their texels — none for a move
  /// ([FramePictureStore._writeWaiting]).
  final List<_Rendered<K>> waiting = [];

  int get bytes =>
      estimatedImageBytes(picture.image.width, picture.image.height);
}

class _Lay<K> {
  _Lay(this.key, this.frame);

  final K key;
  final FrameDrawing frame;
  final Completer<FramePicture?> done = Completer<FramePicture?>();
}

/// One [FramePictureStore.patch], widened, until its picture has moved.
class _Patch<K> {
  _Patch(this.from, this.to, this.rect, this.recorded);

  final K from;
  final K to;
  final ui.Rect rect;

  /// What the patch draws — none for a [FramePictureStore.move].
  final ui.Picture? recorded;

  /// Answered once [to] answers with the patch's texels — or once its
  /// picture is let go before that ([FramePictureStore._letGo]), whichever
  /// comes first ([answer]).
  Future<void> get moved => _moved.future;
  final Completer<void> _moved = Completer<void>();

  /// 🚨ONCE, whoever answers first. The picture let go answered whoever
  /// waited, and the patch behind it in the queue answered again on its
  /// turn: the second answer threw out of the store into whatever let the
  /// picture go — a box's undo, a pixel verb, a paste (2026-10-25).
  void answer() {
    if (!_moved.isCompleted) {
      _moved.complete();
    }
  }
}

/// 🔬F-509 TRACE — a device build only, never landed: what the store did
/// with the patches and lays asked of it, counted on the input inspector's
/// card.
abstract final class _F509s {
  static final Map<String, int> _counts = {};

  static void count(String what) {
    _counts[what] = (_counts[what] ?? 0) + 1;
    InputInspector.pin(
      'f509s',
      'f509s ${[for (final MapEntry(:key, :value) in _counts.entries) '$key=$value'].join(' ')}',
    );
  }
}
