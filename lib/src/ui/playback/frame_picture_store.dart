import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../core/pin_counts.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/playback/let_go_wanted_latest.dart';
import '../canvas/display_resample.dart' show wholeLevelPixelsOutward;
import '../quiet_turns.dart';
import 'frame_picture_gpu.dart';

/// Texels on their way into a [FramePicture]: drawn over it at [rect] with
/// `BlendMode.src` until they land, then gone from [FramePicture.landing].
typedef LandingPatch = ({ui.Rect rect, ui.Image image});

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
/// (`frameDrawingOf`).
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
/// The consumer draws [image] where [extent] lies in the world, paints the
/// world outside [extent] [outside], and draws every [landing] patch over
/// it with `BlendMode.src` — a patch holds the picture's texels where it
/// lies, alpha and all, so wherever one is landing the image and its
/// patches are drawn in a layer of their own and that layer over what lies
/// under the frame: drawn straight over it, a patch's clear texels would
/// cut through that too.
///
/// 🔁ZOOMED OUT IT IS DRAWN WITH ITS OWN MIP CHAIN — `FilterQuality.medium`
/// at or under 50%. The engine gives every picture it rasters a whole chain
/// (`mipLevelCount` 11 at 3840², measured), made once, when the picture is;
/// [FramePictureStore] writes every patch into every level of it — the base
/// at once, the levels under it once the patches pause — and the patch is
/// drawn over it until the last level has it ([landing]), so what shows is
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

  /// The patches drawn over [image] until their texels are in every level
  /// of it, in the order they were made — a later one over an earlier.
  List<LandingPatch> get landing => List.unmodifiable(_landing);
}

/// The frames' pictures, each under the identity of what it shows ([K]):
/// laid whole once ([lay]), then patched where it stands ([patch]), let go
/// of by the playback budget's one order ([enforceBudget]).
class FramePictureStore<K extends Object> {
  FramePictureStore({
    FramePictureGpu? gpu,
    QuietTurns? quietTurns,
    Duration levelsQuiet = _levelsQuiet,
    int levelsWaitAtMost = _levelsWaitAtMost,
    int levelsWaitTexelsAtMost = _levelsWaitTexelsAtMost,
  }) : _gpu = gpu ?? FlutterGpuFramePictures(),
       _quietTurns = quietTurns ?? QuietTurns.instance,
       _levelsQuietFor = levelsQuiet,
       _levelsWaitingAtMost = levelsWaitAtMost,
       _levelsWaitingTexelsAtMost = levelsWaitTexelsAtMost;

  final FramePictureGpu _gpu;

  /// Where the levels under the base take their turn to be written
  /// ([_landLevels]), and the patches waiting for them to be laid as one
  /// ([_layAsOne]).
  final QuietTurns _quietTurns;

  /// How long a write of the levels under the base has taken from its turn
  /// to its landing, at the most of late.
  final QuietSpan _levelsSpan = QuietSpan();

  /// How long laying patches as one has taken from its turn to its landing.
  final QuietSpan _asOneSpan = QuietSpan();

  final Duration _levelsQuietFor;
  final int _levelsWaitingAtMost;
  final int _levelsWaitingTexelsAtMost;

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
  /// world coordinates over all of it, as a lay's is ([FrameDrawing]): the
  /// patch's texels, clear ones too, take the place of the picture's there.
  /// The store widens [rect] to the picture's grid; the caller hands it as
  /// it is.
  ///
  /// The picture answers to [to] once the patch's texels are drawn, with
  /// them [FramePicture.landing] over it; until then [from] still shows
  /// what it was. [from] may be [to] — a stroke's next step — and a patch
  /// may move a picture an earlier patch is still moving.
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
      return false;
    }
    final widened = wholeLevelPixelsOutward(rect, entry.patchedLevels);
    if (entry.held == null || !_covers(entry.picture.extent, widened)) {
      _letGo(entry);
      return false;
    }
    final asked = _Patch<K>(from, to, widened, _recorded(widened, draw));
    _becoming[to] = (entry: entry, moved: asked.moved);
    entry.renders = entry.renders.then((_) => _renderPatch(entry, asked));
    return true;
  }

  /// Answers once every patch has landed, at every level — the levels under
  /// the base at once, not after the pause they wait for — for a caller
  /// that must read the pictures' own texels rather than draw them with
  /// their landing patches.
  Future<void> settled() async {
    for (final entry in _everyEntry) {
      await entry.renders;
      entry.levelsWanted = true;
      entry.writes = entry.writes.then((_) => _landLevels(entry));
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
    final image = await _rendered(
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
    final image = await _rendered(
      asked.recorded,
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
    entry.waiting.add(landing);
    asked.moved.complete();
    entry.writes = entry.writes.then((_) => _landWaiting(entry));
  }

  /// Lands every patch that has texels and is not in yet at the BASE level,
  /// in one write — a later patch over an earlier — and leaves the levels
  /// under it to [_landLevels]: once patches stop coming for
  /// [_levelsQuietFor], or at once when as much waits as may
  /// ([_asMuchAsMayWait]) after the ones not laid as one yet are
  /// ([_layAsOne]).
  ///
  /// 🔬A batch, not a write a patch (D7-2, 2026-10-24): on the Surface Pro
  /// 11 a 3840² picture took about 57 ms to land one patch — five waits on
  /// the GPU — so a stroke patching every vsync fell 600 patches behind,
  /// every one of them drawn over the picture each frame and held. Patches
  /// that render while a batch lands wait for the next one.
  ///
  /// 🔬THE BASE AT ONCE, THE LEVELS UNDER IT ONCE THE PATCHES PAUSE (D7-2,
  /// 2026-10-24, the Surface Pro 11, release, a 3840² frame patched every
  /// vsync): a level under the base is written only from a buffer that a
  /// copy out of the GPU fills, and on GLES that copy holds the raster
  /// thread until the GPU has done everything before it. Every level with
  /// each batch put a stroke's frames at p90 19–35 ms, 21–44% of them past
  /// 16.7 ms (p90 4 ms at rest); the base alone, a texture copy, cost
  /// nothing — p90 4.1–6.1 ms, 0–4 frames past 16.7 ms a 1.3 s stroke, the
  /// levels written in the pause. Meanwhile the patches are drawn over the
  /// picture: 64 of them drew at the cost of none (raster p90 2.0–2.6 ms).
  /// ⛔Laying the picture again on the GPU, with no copy out: about 200 ms a
  /// 3840² lay, a 1.3 s stroke took 32 s. ⛔The engine's `toByteData` for
  /// the copy out: no better (0–21 frames past 16.7 ms a stroke).
  Future<void> _landWaiting(_Entry entry) async {
    if (entry.waiting.isEmpty) {
      return;
    }
    final batch = List.of(entry.waiting);
    entry.waiting.clear();
    final picture = entry.picture;
    if (entry.gone) {
      return;
    }
    await _gpu.writeBase(entry.held!, [
      for (final landing in batch)
        (
          source: landing.image,
          x: _xOf(picture, landing),
          y: _yOf(picture, landing),
        ),
    ]);
    entry.levelsDue.addAll(batch);
    entry.quiet?.cancel();
    if (_asMuchAsMayWait(entry) && entry.levelsDue.length > 1) {
      await _layAsOne(entry);
    }
    if (_asMuchAsMayWait(entry)) {
      await _landLevels(entry);
      return;
    }
    entry.quiet = Timer(_levelsQuietFor, () {
      entry.writes = entry.writes.then((_) => _landLevels(entry));
    });
  }

  /// Whether as much is drawn over [entry]'s picture, waiting for the
  /// levels under its base, as may be: [_levelsWaitingAtMost] patches, or
  /// [_levelsWaitingTexelsAtMost] texels of them.
  bool _asMuchAsMayWait(_Entry entry) {
    final waiting = [...entry.levelsDueAsOne, ...entry.levelsDue];
    var texels = 0.0;
    for (final patch in waiting) {
      texels += patch.rect.width * patch.rect.height;
    }
    return waiting.length >= _levelsWaitingAtMost ||
        texels >= _levelsWaitingTexelsAtMost;
  }

  /// The patches of [_Entry.levelsDue] drawn over the picture as ONE, over
  /// their bounds, read from the base they are in ([_readAt]): a raster on
  /// the GPU, no copy out of it — the levels under them wait on.
  ///
  /// Background GPU work like the levels' write — what the picture shows
  /// is the same with it or without it — so it takes its turn in the quiet
  /// between held frames ([QuietTurns]).
  ///
  /// 🔬AT THE CAP, THE PATCHES AS ONE, NOT THE LEVELS (D7-2, 2026-10-24,
  /// the Surface Pro 11, release, a 3840² frame patched every vsync with no
  /// pause, the two taken in turn in one session): the levels' write at the
  /// cap held one frame every 64 patches — at a 200 px brush at 25%, 2–12
  /// frames past 16.7 ms a 1.6 s stroke, the longest 72–110 ms; laid as one,
  /// 0–6, the longest 6–27 ms. At a 24 px brush at 100%, 4–65 a 2.6 s stroke
  /// against 0–1 in the last three sessions (0–53 in the two before, the
  /// machine busy). Each laid as one in 1–10 ms.
  /// The levels are written once as much waits as may all the same
  /// ([_asMuchAsMayWait]) — a 25 s stroke round and round at 200 px wrote
  /// them 8 times, not 40: 51–66 frames past 16.7 ms, not 135. ⛔The ones
  /// laid as one at a cap of their own, the patches as asked at theirs: 39
  /// laid as one, not 101, but 88 MB drawn over the picture and held, not
  /// 76, and 84–100 frames past 16.7 ms.
  Future<void> _layAsOne(_Entry entry) async {
    final turn = await _quietTurns.inAQuiet(
      _asOneSpan,
      gone: () => entry.gone,
      due: () => entry.levelsWanted,
    );
    if (turn == null) {
      return;
    }
    final picture = entry.picture;
    final patches = List.of(entry.levelsDue);
    var bounds = patches.first.rect;
    for (final patch in patches) {
      bounds = bounds.expandToInclude(patch.rect);
    }
    final image = await _readAt(
      [
        (
          image: picture.image,
          from: bounds.shift(-picture.extent.topLeft),
          to: ui.Offset.zero & bounds.size,
        ),
      ],
      bounds.width.toInt(),
      bounds.height.toInt(),
    );
    if (entry.gone) {
      image.dispose();
      unawaited(turn.gaveUp());
      return;
    }
    final one = (rect: bounds, image: image);
    final landing = picture._landing;
    landing.insert(landing.indexOf(patches.first), one);
    for (final patch in patches) {
      landing.remove(patch);
      patch.image.dispose();
    }
    entry.levelsDue.clear();
    entry.levelsDueAsOne.add(one);
    unawaited(turn.landed());
  }

  /// Writes the levels under the base of every patch whose base is in, in
  /// ONE copy out of the GPU: each patch's own halvings down to the deepest
  /// patched level, a later patch over an earlier, then every level under
  /// that made again whole, once for them all ([_run]).
  ///
  /// Background GPU work — the patches are drawn over the picture meanwhile
  /// — so it takes its turn in the quiet between held frames ([QuietTurns]).
  ///
  /// 🚨LEVELS A CALLER WAITS FOR ARE NOT BACKGROUND WORK ([settled]): its
  /// caller reads the picture's own texels now, so the write is due and
  /// goes at once ([QuietTurns.inAQuiet]) — while a run plays, a turn
  /// barely comes (브러시/렌더링 2026-10-24: 2 of 50 asked, the jobs'
  /// lengths past the 16–32 ms between held frames).
  ///
  /// 🔬One copy out a write (D7-2, 2026-10-24): the levels go out end to end
  /// in one raster ([_run]); its 1,000–28,000 rows rastered in 4–144 ms on
  /// the Surface Pro 11 and held no frame doing it — the copy out did.
  Future<void> _landLevels(_Entry entry) async {
    entry.quiet?.cancel();
    entry.quiet = null;
    if (entry.levelsDueAsOne.isEmpty && entry.levelsDue.isEmpty) {
      entry.levelsWanted = false;
      return;
    }
    final turn = await _quietTurns.inAQuiet(
      _levelsSpan,
      gone: () => entry.gone,
      due: () => entry.levelsWanted,
    );
    if (turn == null) {
      return;
    }
    final due = [...entry.levelsDueAsOne, ...entry.levelsDue];
    entry.levelsDueAsOne.clear();
    entry.levelsDue.clear();
    entry.levelsWanted = false;
    final picture = entry.picture;
    final patched = entry.patchedLevels;
    final below = entry.levels - 1 - patched;
    final deepest = below > 0 ? await _deepestPatchedLevel(entry, due) : null;
    final run = await _run([
      for (final landing in due)
        (
          image: landing.image,
          level: 0,
          x: _xOf(picture, landing),
          y: _yOf(picture, landing),
          count: patched,
        ),
      if (deepest != null)
        (image: deepest, level: patched, x: 0, y: 0, count: below),
    ]);
    deepest?.dispose();
    var landed = false;
    final image = run.image;
    if (image != null && !entry.gone) {
      landed = await _gpu.writeLevels(entry.held!, image, run.spans);
    }
    image?.dispose();
    // Off the picture only once every level has it — a zoomed-out view
    // would otherwise show the old texels for as long as the deep levels
    // take.
    for (final landing in due) {
      picture._landing.remove(landing);
      landing.image.dispose();
    }
    unawaited(landed ? turn.landed() : turn.gaveUp());
  }

  /// The picture's deepest patched level with [batch] in it: the level as
  /// the picture holds it, each patch drawn over its place there — the
  /// reading its own write lays at that level ([_readAt]) — whole, so the
  /// levels under it are its halvings.
  Future<ui.Image> _deepestPatchedLevel(
    _Entry entry,
    List<LandingPatch> batch,
  ) {
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
      for (final landing in batch)
        (
          image: landing.image,
          from: _whole(landing.image),
          to: _scaled(landing.rect.shift(-picture.extent.topLeft), scale),
        ),
    ], width, height);
  }

  /// The halvings 1 to `count` of each of [sources], their texels end to
  /// end, row after row, wrapping at [_runWidth] — as one copy out of the
  /// GPU gives them back and as a level is written from it, row after row
  /// ([FramePictureGpu.writeLevels]) — in one raster ([_readAt]); with the
  /// [RunSpan] that lays each halving where its source lies, at `level`
  /// and (`x`, `y`), halved. No image where there is no halving at all.
  /// Exact where the sides halve evenly; under that, the GPU's own reading
  /// of a side that does not.
  Future<({ui.Image? image, List<RunSpan> spans})> _run(
    List<({ui.Image image, int level, int x, int y, int count})> sources,
  ) async {
    final reads = <({ui.Image image, ui.Rect from, ui.Rect to})>[];
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

  /// Each of [reads] — the [from] rect of an image drawn into its [to] rect,
  /// a later one in place of an earlier — in one [width] x [height] raster,
  /// under `FilterQuality.medium`: drawn at 1/2^k a side so, the GPU
  /// samples the image's own level k — the engine's halving, the one the
  /// picture's chain was made with — so a patch's levels are the very code
  /// of the levels round it, on any backend (measured on the Surface Pro
  /// 11: the levels it replaced, byte for byte, 2026-10-24).
  Future<ui.Image> _readAt(
    List<({ui.Image image, ui.Rect from, ui.Rect to})> reads,
    int width,
    int height,
  ) async {
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

ui.Rect _scaled(ui.Rect rect, double scale) => ui.Rect.fromLTRB(
  rect.left * scale,
  rect.top * scale,
  rect.right * scale,
  rect.bottom * scale,
);

/// How long patches stop coming before the levels under their base are
/// written ([FramePictureStore._landLevels]) — a stroke's pause, not the
/// time between its dabs.
///
/// 🔬200 ms and 64 measured together (D7-2, 2026-10-24, the Surface Pro 11,
/// a 3840² frame patched every vsync): the levels' one copy out of the GPU
/// held one frame 18–114 ms (11 ms most times, more while the GPU was
/// busy), so a long stroke has one such frame every [_levelsWaitAtMost]
/// patches — 0–4 a 1.3 s stroke at 64; 0–3 at 128, with up to 130 patches
/// drawn over the picture and held (about 50 MB at a 200 px brush); 1–23
/// at 32. Hatching — strokes of 30 patches, 150–800 ms apart — no vsync
/// late at 250 ms apart and more: the pause's write was done before the
/// next stroke began, even 50 ms after it. ⛔A longer pause is worse: at
/// 1 s every gap left the levels to the cap, inside a stroke (2–3 vsyncs
/// late, 66–76 ms).
///
/// Since the patches at the cap are laid as one
/// ([FramePictureStore._layAsOne], the same day), the levels are written at
/// the cap only once as much waits as may all the same — 8 times a 25 s
/// stroke at a 200 px brush, not 40.
const Duration _levelsQuiet = Duration(milliseconds: 200);

/// The most patches drawn over a picture while the levels under their base
/// wait: at that many, the ones not laid as one yet are laid as one
/// ([FramePictureStore._layAsOne]); when as many wait all the same, the
/// levels are written at once ([_levelsQuiet] has the measurement).
const int _levelsWaitAtMost = 64;

/// The most texels of the patches drawn over a picture while the levels
/// under their base wait, as [_levelsWaitAtMost] is of patches: 4 Mi, the
/// 16 MiB of 64 patches 256 a side.
///
/// 🔬(D7-2, 2026-10-24, the Surface Pro 11, release, a 3840² frame, a
/// 200 px brush at 25%): drawn over the picture, 64 patches of the brush
/// (3.4 Mi texels) and two laid as one with the ones after them (4.0 Mi)
/// cost nothing — raster p90 2.1–2.3 ms; laid as one with no bound, a 25 s
/// stroke round and round held 25 Mi drawn over it (105 MB): 128 frames
/// past 16.7 ms, raster p90 7.7 ms, and the levels' write at its end held
/// one frame 299 ms.
const int _levelsWaitTexelsAtMost = 4 << 20;

/// The run's width ([FramePictureStore._run]): the widest texture every
/// GPU the app runs on takes — OpenGL ES 3's floor.
const int _runWidth = 2048;

/// Where [landing] lies in [picture]'s base level.
int _xOf(FramePicture picture, LandingPatch landing) =>
    (landing.rect.left - picture.extent.left).toInt();

int _yOf(FramePicture picture, LandingPatch landing) =>
    (landing.rect.top - picture.extent.top).toInt();

/// The reads that lay [image] halved to [width] x [height] into a run from
/// texel [at] on: one a row, and one more each time a row wraps.
Iterable<({ui.Image image, ui.Rect from, ui.Rect to})> _rowsOf(
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

  /// Writes into the texture, one after another — the deep levels a write
  /// makes are made from the levels the writes before it wrote.
  Future<void> writes = Future<void>.value();

  /// The patches with texels that no batch has taken yet, in the order
  /// they were made ([FramePictureStore._landWaiting]).
  final List<LandingPatch> waiting = [];

  /// The patches whose base is in and whose levels under it are not yet,
  /// in the order they were made ([FramePictureStore._landLevels]) — after
  /// every one of [levelsDueAsOne].
  final List<LandingPatch> levelsDue = [];

  /// Patches of [levelsDue] laid again as one each, in the order they were
  /// laid ([FramePictureStore._layAsOne]); their levels are not in either.
  final List<LandingPatch> levelsDueAsOne = [];

  /// Runs out once patches stop coming for the pause the levels wait for.
  Timer? quiet;

  /// Whether a caller waits for [levelsDue] and [levelsDueAsOne] to be
  /// written ([FramePictureStore.settled]) — which makes the write due.
  bool levelsWanted = false;

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
  _Patch(this.from, this.to, this.rect, this.recorded);

  final K from;
  final K to;
  final ui.Rect rect;
  final ui.Picture recorded;
  final Completer<void> moved = Completer<void>();
}
