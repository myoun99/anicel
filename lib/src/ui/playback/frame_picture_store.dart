import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ErrorDescription, FlutterError, FlutterErrorDetails;

import '../../core/pin_counts.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/playback/let_go_wanted_latest.dart';
import '../canvas/display_resample.dart'
    show
        filterQualityForDisplayScale,
        frameGridOutward,
        wholeLevelPixelsOutward;
import '../canvas/fx_plugin_stages.dart';
import '../canvas/image_pieces.dart' show piecesOver;
import '../debug/input_inspector.dart' show InputInspector;
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
///
/// 🚨★★★A PICTURE WRITTEN INTO IS A NEW IMAGE — [image] is another after
/// every write that lands in it, over the same texture (no texel copied),
/// and its listeners are told: whatever draws it draws the one it is now.
/// ⛔But for the levels it owes while no screen reads them, a part at a time:
/// those change nothing any screen draws, and each told would be a frame of
/// the whole canvas over what the GPU is still writing
/// ([FramePictureStore._layOwed]).
/// The engine takes an image for a value. On iPhone and iPad (Impeller,
/// Metal) a screen is drawn again only where its drawing changed from the
/// frame before, an image told apart by its identity alone
/// (`DlImage::Equals`) — so a stroke written into the very image the
/// screen drew went nowhere: invisible while drawn and after, until the
/// frame was left and come back to (F-509, 유저 2026-10-30 「홍보 한참인데
/// 진짜 비상사태」; 1079 from its second stroke, every stroke from 1080).
/// Every runner and Windows draw the whole screen each frame, which hid it.
class FramePicture extends ChangeNotifier {
  FramePicture._(this._image, this.extent, this.outside);

  /// Whether a screen has read this picture's levels since its patches last
  /// paused — whether a write lays them ([readAt]).
  bool _levelsRead = false;

  /// Where the levels are behind the base.
  ui.Rect? _owed;

  /// Asks for the levels owed at once.
  late final void Function() _levelsWanted;

  /// The frame, one texel a canvas pixel, texel (0, 0) at [extent]'s
  /// top left — as it is now.
  ui.Image get image => _image;
  ui.Image _image;

  /// Where [image] lies in the world — whole pixels, at least what was laid.
  final ui.Rect extent;

  /// The frame's colour everywhere outside [extent].
  final ui.Color outside;

  /// Tells the picture that a screen draws it at [displayScale], before the
  /// screen asks for a step: a write lays the levels if a screen reads them
  /// ([FramePictureStore._written]). Answers whether [image] is as it is as
  /// far as that reads — where not, the levels are written now, and the
  /// screen has the frame as it stands to draw until they are in.
  ///
  /// 🔬A screen above 1/2 reads no level, on any backend: `FilterQuality.low`
  /// samples with `MipFilter.kBase` (engine 3.47.4, `ToSamplerDescriptor`),
  /// which is `GL_LINEAR` on GLES, `MTLSamplerMipFilterNotMipmapped` on Metal
  /// and `minLod = maxLod = 0` on Vulkan. Measured 2026-10-31: a picture with
  /// its levels behind its base, drawn at 95%–51% through both of the
  /// display's blits, is the picture laid whole, to the byte, in the Windows
  /// app (GLES) and on the tester's Vulkan. ⚠️Read, not measured, on Metal
  /// and on a device's Vulkan. ↩️A flag took those two to read them, on a
  /// note of one-picture-per-frame ②-5b-2 the engine does not bear out, and
  /// cost every step above 1/2 there two waits.
  bool readAt(double displayScale) {
    final levels =
        filterQualityForDisplayScale(displayScale) == ui.FilterQuality.medium;
    _levelsRead = _levelsRead || levels;
    if (!levels || _owed == null) {
      return true;
    }
    _levelsWanted();
    return false;
  }

  /// [image] is [now] from here on — a write is in it — and the image it
  /// was is let go of, once whoever listens has taken the new one.
  void _written(ui.Image now) {
    final was = _image;
    _image = now;
    notifyListeners();
    was.dispose();
  }
}

/// The frames' pictures, each under the identity of what it shows ([K]):
/// laid whole once ([lay]), then patched where it stands ([patch]), let go
/// of by the playback budget's one order ([enforceBudget]).
class FramePictureStore<K extends Object> {
  /// [onceSide] and [pieceSide] are for tests, to lay a small picture a
  /// piece at a time ([_layNow]); the app lays every picture by
  /// [framePictureSide] and [framePieceSide].
  FramePictureStore({
    FramePictureGpu? gpu,
    int onceSide = framePictureSide,
    int pieceSide = framePieceSide,
  }) : _gpu = gpu ?? FlutterGpuFramePictures(),
       _onceSide = onceSide,
       _pieceSide = pieceSide;

  final FramePictureGpu _gpu;

  /// The longest side a picture is laid at once ([_layNow]).
  final int _onceSide;

  /// The side of the pieces of a picture past [_onceSide].
  final int _pieceSide;

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
  /// write ([wholeLevelPixelsOutward]) — a piece at a time ([_layNow]).
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
  /// every level a screen reads ([_written]); until then [from] still shows
  /// what it was.
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
  ///
  /// 🗣️I-132-Q34 a: a plugin's step in it is waited for as a lay's is
  /// ([_recordedThrough]) — [draw] called again once the step has run,
  /// unless [gone] says what it draws is gone by then: the patch does not
  /// go in, and its picture is let go.
  bool patch({
    required K from,
    required K to,
    required ui.Rect rect,
    required void Function(ui.Canvas canvas) draw,
    bool Function()? gone,
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
    entry.quiet?.cancel();
    final asked = _Patch<K>(
      from,
      to,
      widened,
      _recordedThrough(widened, draw, gone: gone)..ignore(),
    );
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
  /// Answers whether it went in: false where its picture was let go first.
  Future<bool>? landingOf(K key) => _becoming[key]?.patch.moved;

  /// Answers once every patch asked for is in its picture, at every level.
  Future<void> settled() async {
    for (final entry in _everyEntry) {
      await entry.renders;
      await entry.writes;
      while (entry.picture._owed != null && !entry.gone) {
        _writeOwed(entry);
        await entry.writes;
      }
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

  /// ⚠️A lay stays in [_lays] until it is done — a piece at a time it takes
  /// many frames, and the same key asked for meanwhile waits on it, not
  /// laid a second time over it.
  Future<void> _pump() async {
    if (_laying) {
      return;
    }
    _laying = true;
    try {
      while (_lays.isNotEmpty) {
        final lay = _lays.first;
        try {
          final laid = await _layNow(lay);
          if (!lay.done.isCompleted) {
            lay.done.complete(laid);
          }
        } on Object catch (error, stack) {
          if (!lay.done.isCompleted) {
            lay.done.completeError(error, stack);
          }
        } finally {
          _lays.remove(lay);
        }
      }
    } finally {
      _laying = false;
    }
  }

  /// 🚨★★★A PICTURE LONGER THAN [framePictureSide] IS LAID A PIECE AT A TIME
  /// (card a-picture-lay-holds-the-raster-thread, D7-2): each [_pieceSide]
  /// square of it on the patches' grid is recorded and rastered alone, and
  /// the pieces are written into a texture made whole beforehand
  /// ([_written], a patch's very write) — every level of it. The picture
  /// answers to its key once every piece is in; until then the frame is
  /// drawn as it stands, as while any lay is on its way.
  ///
  /// 🔬Rastered at once, the picture was one raster job, and the frame on
  /// screen waited it out (Surface Pro 11, release, GLES, 2026-10-31): a
  /// 3840² cut's ink to the pasteboard's end, its picture 11520 x 3968, held
  /// the raster thread 376–766 ms a lay, 1032–2207 ms with its onion's
  /// ghosts in place; S5_BA cut 352, 2944 x 1792, up to 409 ms. Even
  /// nothing drawn over 11520 x 3968 held one frame's raster 298–317 ms.
  /// Written in pieces of 512 by this write: no frame's raster past 2 ms,
  /// the whole in 1.3–1.5 s; of 1024, 9–14 ms and 1.1–1.4 s.
  ///
  /// ⛔Not at a lower resolution: 유저 「해상도로 속도를 사지 않는다」.
  ///
  /// A picture inside [_onceSide] is rastered at once, its chain the
  /// engine's; so is one where no texture can be made
  /// ([FramePictureGpu.allocate]), as it was. ⛔Not every picture in pieces:
  /// where one fits, at once is cheaper ([framePictureSide]).
  Future<FramePicture?> _layNow(_Lay<K> lay) async {
    final (:extent, :patchedLevels) = _shapeOf(lay.frame.extent);
    if (extent.isEmpty) {
      return null;
    }
    assert(_pieceSide % (1 << patchedLevels) == 0, 'a piece off the grid');
    final pieces = extent.longestSide <= _onceSide
        ? [extent]
        : piecesOver(extent, side: _pieceSide);
    final allocated = pieces.length == 1
        ? null
        : _gpu.allocate(extent.width.toInt(), extent.height.toInt());
    if (allocated == null) {
      // The frame's key is its signature, so what it draws is the same
      // however often — and however much of it at a time — it is drawn.
      final image = await _drawnOver(extent, lay.frame.draw);
      if (image == null) {
        return null;
      }
      if (_disposed) {
        image.dispose();
        return null;
      }
      final held = _gpu.hold(image);
      return _laid(
        lay.key,
        _Entry<K>(
          FramePicture._(image, extent, lay.frame.outside),
          held: held,
          levels: held == null ? 1 : _gpu.levelsOf(held),
          patchedLevels: patchedLevels,
        ),
      );
    }
    final entry = _Entry<K>(
      FramePicture._(_gpu.imageOf(allocated), extent, lay.frame.outside),
      held: allocated,
      levels: _gpu.levelsOf(allocated),
      patchedLevels: patchedLevels,
    );
    final bool written;
    try {
      written = await _writtenInPieces(entry, pieces, lay.frame.draw);
    } on Object {
      // Thrown to whoever waits on the lay, as by a lay rastered at once.
      _letGo(entry);
      rethrow;
    }
    if (!written || _disposed) {
      _letGo(entry);
      return null;
    }
    return _laid(lay.key, entry);
  }

  /// [entry]'s picture is [key]'s from here on.
  FramePicture _laid(K key, _Entry<K> entry) {
    entry.lastUsed = ++_clock;
    entry.picture._levelsWanted = () => _writeOwed(entry);
    _entries[key] = entry;
    return entry.picture;
  }

  /// Writes [pieces] into [entry]'s picture, each recorded and rastered in
  /// its turn, at most [_batchTexels] of them a write ([_written]).
  /// Answers whether every one went in; the rasters are let go of either
  /// way.
  Future<bool> _writtenInPieces(
    _Entry<K> entry,
    List<ui.Rect> pieces,
    void Function(ui.Canvas canvas) draw,
  ) async {
    final batch = <_Texels>[];
    var texels = 0;
    try {
      for (final (at, piece) in pieces.indexed) {
        final image = await _drawnOver(piece, draw);
        if (image == null || _disposed) {
          image?.dispose();
          return false;
        }
        batch.add((rect: piece, image: image));
        texels += image.width * image.height;
        if (texels >= _batchTexels || at == pieces.length - 1) {
          if (!await _written(entry, batch, entry.deepest)) {
            return false;
          }
          for (final written in batch) {
            written.image.dispose();
          }
          batch.clear();
          texels = 0;
        }
      }
      return true;
    } finally {
      for (final unwritten in batch) {
        unwritten.image.dispose();
      }
    }
  }

  /// What [draw] draws over [rect], its plugins run, rastered — null where
  /// what it draws was gone first ([_recordedThrough]).
  Future<ui.Image?> _drawnOver(
    ui.Rect rect,
    void Function(ui.Canvas canvas) draw,
  ) async {
    final recorded = await _recordedThrough(rect, draw);
    if (recorded == null) {
      return null;
    }
    return _rendered(recorded, rect.width.toInt(), rect.height.toInt());
  }

  /// A patch whose render throws cannot go in: its picture is let go and
  /// it is answered, and the renders behind it go on — as a write that
  /// throws ([_writeWaiting]).
  Future<void> _renderPatch(_Entry<K> entry, _Patch<K> asked) async {
    final recording = asked.recorded;
    final ui.Image? image;
    try {
      final recorded = await recording;
      if (recording != null && recorded == null) {
        // What it drew was gone before its plugins had run ([patch]).
        _letGo(entry);
        asked.answer(landed: false);
        return;
      }
      image = recorded == null
          ? null
          : await _rendered(
              recorded,
              asked.rect.width.toInt(),
              asked.rect.height.toInt(),
            );
    } on Object catch (error, stack) {
      _report(error, stack, 'rendering a patch into a frame picture');
      _letGo(entry);
      asked.answer(landed: false);
      return;
    }
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
  ///
  /// 🚨★★★A WRITE THAT THROWS DID NOT WRITE: its picture is let go and
  /// every patch of the batch answered, as where the GPU answers it did
  /// not (F-509). Let out, the throw left [_Entry.writes] failed for good —
  /// every write chained behind it skipped, no patch into the picture ever
  /// answered, the screen showing the picture as it was before the stroke.
  /// On an iPhone and iPad that was every stroke into a picture: no write
  /// into one came back in build 1083's trace, their pictures in a format
  /// `flutter_gpu` cannot size ([FlutterGpuFramePictures.hold]) — 유저 실기
  /// 2026-10-30 「빈블록에서 그릴땐 획 몇번하든 안보임 … 그려져있는 상태에서
  /// 첫획은 보임. 두번째획부턴 안보임」.
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
    final picture = entry.picture;
    final downTo = picture._levelsRead ? entry.deepest : 0;
    if (await _wentIn(entry, texels, downTo)) {
      _owe(entry, texels, downTo);
      picture._written(_gpu.imageOf(entry.held!));
    }
    for (final (:patch, image: _) in batch) {
      _arrived(entry, patch);
    }
  }

  /// Writes [texels] into [entry]'s picture down to level [downTo] and lets
  /// them go. Answers whether there is a picture with them in it: its
  /// image is another now, for the caller to hand on.
  Future<bool> _wentIn(
    _Entry<K> entry,
    List<_Texels> texels,
    int downTo,
  ) async {
    var written = true;
    try {
      if (texels.isNotEmpty && !entry.gone) {
        written = await _written(entry, texels, downTo);
      }
    } on Object catch (error, stack) {
      _report(error, stack, 'writing patches into a frame picture');
      written = false;
    } finally {
      for (final patch in texels) {
        patch.image.dispose();
      }
    }
    if (!written) {
      // Not in the picture: no key may answer with it.
      _letGo(entry);
    }
    return written && texels.isNotEmpty && !entry.gone;
  }

  /// [texels] went into [entry]'s picture down to level [downTo]: the
  /// levels under that owe them, until the patches pause ([_levelsQuiet]).
  void _owe(_Entry<K> entry, List<_Texels> texels, int downTo) {
    final picture = entry.picture;
    if (downTo < entry.deepest) {
      var rect = picture._owed ?? texels.first.rect;
      for (final patch in texels) {
        rect = rect.expandToInclude(patch.rect);
      }
      picture._owed = rect;
    }
    entry.quiet?.cancel();
    entry.quiet = Timer(_levelsQuiet, () {
      picture._levelsRead = false;
      _writeOwed(entry);
    });
  }

  /// Writes the levels [entry]'s picture owes, in their turn among its
  /// writes.
  void _writeOwed(_Entry<K> entry) {
    entry.quiet?.cancel();
    _layOwedNext(entry);
  }

  void _layOwedNext(_Entry<K> entry) {
    entry.writes = entry.writes.then((_) => _layOwed(entry));
  }

  /// The levels [entry]'s picture owes, a part at a time ([_owedAtOnce]):
  /// what a part owes, read from the base it is in ([_readAt]), written as
  /// one patch at every level, and the next part after it — unless a step
  /// has come since and no screen waits for them: the pause after that step
  /// takes what is left.
  Future<void> _layOwed(_Entry<K> entry) async {
    final picture = entry.picture;
    final owed = picture._owed;
    final stepping = (entry.quiet?.isActive ?? false) && !picture._levelsRead;
    if (owed == null || entry.gone || stepping) {
      return;
    }
    final rect = _firstPartOf(owed, entry.patchedLevels);
    final ui.Image image;
    try {
      image = await _readAt(
        [
          (
            image: picture.image,
            from: rect.shift(-picture.extent.topLeft),
            to: ui.Offset.zero & rect.size,
          ),
        ],
        rect.width.toInt(),
        rect.height.toInt(),
      );
    } on Object catch (error, stack) {
      _report(error, stack, 'reading what a frame picture owes its levels');
      _letGo(entry);
      return;
    }
    final texels = [(rect: rect, image: image)];
    if (await _wentIn(entry, texels, entry.deepest)) {
      picture._owed = _restOf(owed, rect);
      // The last is told whoever reads: a screen that came to read them
      // since the pause began has them from it.
      if (picture._levelsRead || picture._owed == null) {
        picture._written(_gpu.imageOf(entry.held!));
      }
      if (picture._owed != null) {
        _layOwedNext(entry);
      }
    }
  }

  /// Writes [batch] into [entry]'s picture — a later patch over an earlier,
  /// or the pieces of a lay ([_layNow]) — down to level [downTo], which is
  /// none or the deepest: the base, each patch's own halvings down to the
  /// deepest patched level, and every level under that as far as [downTo]
  /// made again whole, once for them all ([_run]). Answers whether the GPU
  /// did.
  ///
  /// 🚨★★★EVERY LEVEL WITH EVERY BATCH WHERE A SCREEN READS LEVELS, AND THE
  /// PICTURE ANSWERS ONLY THEN — the screen draws the picture and nothing
  /// over it (F-465, 유저 채팅 2026-10-26 「그럼 그냥 바로 바로쓰기로 바꾸고,
  /// 잔재들 없애고, 최대한 개선해보자」; F-512-Q2, 유저 2026-10-31 「그림 한
  /// 장만 유지한다」). Where no screen reads them they wait for the patches
  /// to pause ([_levelsQuiet]), and a screen that comes to read them has them
  /// written then ([FramePicture.readAt]): 🔬a step's cost is its waits,
  /// each about 2.5 ms on a quiet main PC and about 10 under load whatever
  /// its size, and the levels take three more of them than the base alone.
  /// Main PC, 144 Hz, a new project, release, at 100%, the line's tip behind
  /// the pen on the desktop's own image, p50 at 300 px/s (F-512, 2026-10-31):
  /// under another session's tests 66–77 → 38–42 ms, a frame every 55 → 21
  /// ms; quiet 17 → 16 ms. The Surface Pro 11, at 100%, input to raster
  /// done: p50 12.8 → 12.5 ms, p90 20.4 → 15.2 ms.
  /// 🚨THERE THE WAIT MOVES, AND THE OVERLAY'S RASTER SEES ONLY ONE SIDE OF
  /// IT: the levels' copy out held the raster thread before a frame, in the
  /// queue nothing shows, and without it the GPU's tail falls inside the
  /// frame after — the overlay's longest 5–10 → 17–34 ms, which held this
  /// back four rounds. In a stroke, at 100%, one run of each, 13 long
  /// strokes and 20 hatched: queue + raster p90 8.5 → 5.7 and 4.7 → 2.4 ms,
  /// gaps past 16.7 ms 52 → 29 and 78 → 44, past 50 ms 8 → 8 and 17 → 15.
  /// ↩️Every level with every batch, 2026-10-26 to 10-31, 「because the
  /// screen may read it」: only a zoom change does, and it can wait for one.
  /// ⛔Not D7-2 again: nothing is drawn over the picture, so F-465's two
  /// images of one frame cannot come back, and nothing is held meanwhile
  /// but a rect.
  /// ⛔Not only the levels a screen reads, at or under 1/2 (F-512): the main
  /// PC under load went 75–84 → 61–65 ms fitted, but on the Surface Pro 11
  /// (two levels in place of eleven, 44%) a step was no sooner in and showed
  /// later — mean 4 ms, p50 34 → 41 ms at 930 px/s: there the copy out waits
  /// on the GPU however little it copies.
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
  /// ⚠️A bench's numbers, nothing on a screen: in the app itself the main
  /// PC takes about 33 ms from a step to the picture, 8 ms of it the patch's
  /// render, a third of it each raster below (F-512, 2026-10-30).
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
  Future<bool> _written(
    _Entry<K> entry,
    List<_Texels> batch,
    int downTo,
  ) async {
    final picture = entry.picture;
    final patched = math.min(entry.patchedLevels, downTo);
    final below = downTo - patched;
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
          await _PictureWrites.answered(
            _gpu.write(
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
            ),
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
    asked.answer(landed: !entry.gone);
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
    // Once: its image goes with it. A patch rendering behind one that threw
    // lets go of a picture let go already.
    if (entry.gone) {
      return;
    }
    entry.gone = true;
    _entries.removeWhere((_, value) => value == entry);
    _becoming.removeWhere((_, value) {
      if (value.entry != entry) {
        return false;
      }
      value.patch.answer(landed: false);
      return true;
    });
    entry.quiet?.cancel();
    // The GPU may still be writing it: let go once its writes are done.
    unawaited(entry.writes.whenComplete(entry.picture.image.dispose));
  }
}

/// Reports [error], thrown while [doing] — what a [FramePictureStore] goes
/// on from as not done.
void _report(Object error, StackTrace stack, String doing) {
  _PictureWrites.threw();
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'frame picture store',
      context: ErrorDescription(doing),
    ),
  );
}

/// 🔬HOW A DEVICE SAYS WHETHER ITS STROKES GO IN — the input inspector's
/// `picture writes` line (관제 2026-10-30, F-509): a write that does not go
/// in leaves its frame drawn as it stands, right and slow, and nothing else
/// on screen tells that from a stroke written into its picture.
///
/// ⚠️Counted whether or not the card is shown ([InputInspector.arrivals]
/// says why): opened after the strokes, its first line is the session's.
abstract final class _PictureWrites {
  static int _ok = 0;
  static int _failed = 0;
  static int _threw = 0;

  /// [write], its answer counted. One the engine refuses throws before it
  /// has one to give: [threw].
  static Future<bool> answered(Future<bool> write) async {
    final done = await write;
    if (done) {
      _ok += 1;
    } else {
      _failed += 1;
    }
    _show();
    return done;
  }

  static void threw() {
    _threw += 1;
    _show();
  }

  static void _show() => InputInspector.pin(
    'picture writes',
    'picture writes ok $_ok · failed $_failed · threw $_threw',
  );
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

/// The longest side a picture is laid at once ([FramePictureStore._layNow]).
///
/// 🔬A piece's levels under the base are written through `flutter_gpu`
/// ([FramePictureStore._written] — halvings rastered, then copied out of
/// the GPU), where a picture laid at once has its chain made on the GPU by
/// the engine; on a heavy frame that costs more than the one raster.
/// Surface Pro 11, release, the frames' order in turn, 2026-10-31 — the
/// first jump of the ruler after the onion is switched on, to the screen:
/// S5_BA cut 352 with every row visible (2944 x 1792), at once 74–151 ms,
/// in pieces of 512 300–348 ms (2048: 123–271). 🔬A frame laid again, to its
/// raster's end: S5_BA at once 9–96 ms, in pieces of 1024 306–408; the paper
/// alone of a 3840² cut (3840 x 3840) at once 8–114, in pieces of 1024
/// 453–901.
const int framePictureSide = 4096;

/// The side of the pieces of a picture past [framePictureSide]
/// ([FramePictureStore._layNow]): a multiple of the deepest patched level's
/// texel at any picture a GPU takes, so every piece is a patch's shape.
///
/// 🔬As for [framePictureSide], a 3840² cut's ink to the pasteboard's end
/// (11520 x 3968): at once never within 2.5 s, in pieces of 4096
/// 125–454 ms, of 1024 51–75, of 512 75–100. A frame laid again, the pieces
/// written: 11520 x 3840 in pieces of 2048 1301–1539 ms, of 1024 1115–1169,
/// of 512 1246–1376; 3840 x 3840 in 425–612, 306–472, 394–554; S5_BA in
/// 329–432, 208–363, 247–378.
const int framePieceSide = 1024;

/// The texels of the pieces one write takes ([FramePictureStore._written]).
const int _batchTexels = 1 << 20;

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

/// How long patches stop coming before a picture's levels catch up with its
/// base ([FramePictureStore._owe]) — a stroke's pause, not the time between
/// its dabs.
///
/// 🔬Measured for those levels' one write when it first waited (D7-2,
/// 2026-10-24, the Surface Pro 11, a 3840² frame patched every vsync): the
/// copy out of the GPU held one frame 18–114 ms (11 ms most times, more
/// while the GPU was busy). Hatching — strokes of 30 patches, 150–800 ms
/// apart — no vsync late at 250 ms apart and more: the pause's write was
/// done before the next stroke began, even 50 ms after it. ⛔A longer pause
/// is worse: at 1 s every gap left the levels to a cap, inside a stroke
/// (2–3 vsyncs late, 66–76 ms). There is no cap now: what waits is a rect.
const Duration _levelsQuiet = Duration(milliseconds: 200);

/// The most texels of what a picture's levels owe that one write takes,
/// about: a stroke's whole rect in one write is the frame D7-2 measured, the
/// copy out holding the raster thread while the GPU does all of it.
///
/// 🔬One write for the rect (F-512, the Surface Pro 11, release, new project,
/// 2026-10-31): the raster's longest frame 17–31 ms in 6 of 14 hatched
/// strokes and 10.7–39.7 ms in all of 14 long ones at 100%, against 10.1 and
/// 4.3–9.3 ms (once 26.7) with every level written at every step. A part at
/// a time, each told to the screens: 3 of 12 hatched strokes 15.5–30.2 ms and
/// 11 of 12 long ones 14.2–28.1 ms, against 5.8 and 4.7–12.7 ms. 128 K told to
/// none: 8 of 12 hatched 17.1–29.4 ms and 8 of 12 long 11.6–20.9 ms, against
/// 2.9–9.0 (once 14.4) and 3.1–9.6 (once 20.3). The write of such a part took
/// 13–30 ms where a step's takes 3.4 and asks nothing of the raster's frames,
/// and a step's patch is about this big. 16 K: 9 of 12 long ones 14.8–28.2 ms
/// and 6 of 12 hatched 12.8–29.2, against 3.5–8.0.
/// ⚠️No size moved those frames, and owing the levels for good did not either:
/// they are the GPU behind a step ([FramePictureStore._written]). The size
/// stands on D7-2's frame and on the write's own 13–30 ms.
const int _owedAtOnce = 16 * 1024;

/// The first of [owed]'s parts, along its long side so that a long thin
/// stroke's is no row as wide as the stroke: about [_owedAtOnce] texels, in
/// whole cells of the grid patches lie on, [patchedLevels] deep, so the part
/// halves as a patch does.
ui.Rect _firstPartOf(ui.Rect owed, int patchedLevels) {
  final cell = (1 << patchedLevels).toDouble();
  if (owed.width > owed.height) {
    final wide = (_owedAtOnce / owed.height / cell).ceilToDouble() * cell;
    return wide < owed.width
        ? ui.Rect.fromLTWH(owed.left, owed.top, wide, owed.height)
        : owed;
  }
  final tall = (_owedAtOnce / owed.width / cell).ceilToDouble() * cell;
  return tall < owed.height
      ? ui.Rect.fromLTWH(owed.left, owed.top, owed.width, tall)
      : owed;
}

/// What [owed] owes with its [first] part in ([_firstPartOf]).
ui.Rect? _restOf(ui.Rect owed, ui.Rect first) {
  if (first.right < owed.right) {
    return ui.Rect.fromLTRB(first.right, owed.top, owed.right, owed.bottom);
  }
  return first.bottom < owed.bottom
      ? ui.Rect.fromLTRB(owed.left, first.bottom, owed.right, owed.bottom)
      : null;
}

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

/// [recordedOver] with every plugin's step met in it run — 🗣️I-132-Q34 a
/// (유저 2026-10-30): 「결과가 올 때까지 그 프레임의 직전 완성 그림에
/// 머문다」, so a frame's picture, laid or patched, WAITS for its plugins
/// ([FxPluginStages]). The first recording is made before this answers;
/// [gone], asked before each after it, says what [draw] draws is gone — and
/// then there is no picture.
Future<ui.Picture?> _recordedThrough(
  ui.Rect rect,
  void Function(ui.Canvas canvas) draw, {
  bool Function()? gone,
}) => FxPluginStages.recordedThrough(
  () => gone?.call() ?? false ? null : recordedOver(rect, draw),
  discard: (picture) => picture?.dispose(),
);

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

  /// The deepest level [picture] has.
  int get deepest => levels - 1;

  /// Runs out once patches stop coming for [_levelsQuiet].
  Timer? quiet;

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

  /// What the patch draws, its plugins run — none for a
  /// [FramePictureStore.move], and null once it comes where what it drew
  /// was gone ([FramePictureStore.patch]).
  final Future<ui.Picture?>? recorded;

  /// Answered true once [to] answers with the patch's texels — or false
  /// once its picture is let go before that ([FramePictureStore._letGo]),
  /// whichever comes first ([answer]).
  Future<bool> get moved => _moved.future;
  final Completer<bool> _moved = Completer<bool>();

  /// 🚨ONCE, whoever answers first. The picture let go answered whoever
  /// waited, and the patch behind it in the queue answered again on its
  /// turn: the second answer threw out of the store into whatever let the
  /// picture go — a box's undo, a pixel verb, a paste (2026-10-25).
  void answer({required bool landed}) {
    if (!_moved.isCompleted) {
      _moved.complete(landed);
    }
  }
}
