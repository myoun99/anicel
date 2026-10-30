import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show VoidCallback;

import '../../services/playback/let_go_wanted_latest.dart';
import '../../services/straight_rgba_image.dart' show decodedImageStillWanted;
import 'viewer_raster_budget.dart';

/// One raster held for a key, and the look it was drawn at (stale while
/// it revalidates — a raster of another look still draws while the one
/// asked for renders).
class _Held<A> {
  _Held({required this.at, required this.image, required this.usedAt});

  final A at;
  final ui.Image image;

  /// When it was last used, on [ShownRasters]'s clock — its landing, or
  /// the last [ShownRasters.use].
  int usedAt;
}

/// What was last asked for one (key, look).
///
/// 🚨★★★**LANDED IS NOT A VALUE HERE — IT IS THE ABSENCE OF ONE**, because
/// a landed render lives in what is held and this map is about what is
/// still owed. What this type exists to separate is the other two, which
/// were both spelled 「not in the set」 before 2026-09-08. See
/// [ShownRasters._renders].
enum _RenderAsk {
  /// Out with what draws it, no answer yet.
  asking,

  /// What draws it refused this one. ⛔It is remembered until a clock
  /// forgets it ([ShownRasters.forgetRefusals]): asking again the instant it
  /// fails is a loop, and never asking again is a viewer that cannot
  /// recover when the frame becomes readable — and recovery is the law here
  /// (유저 2026-08-31, 「로드할때까지 멈춰있어야지」, which is a WAIT and not a
  /// surrender). A look that changes is another ask: a panel whose cut was
  /// edited asks again at once.
  failed,
}

/// THE PICTURES A SURFACE SHOWS, AS RASTERS — each asked of what draws it
/// at the look the surface shows it at, kept under one viewer's share of
/// the device, and let go by the one order a budget lets go by.
///
/// 🚨ONE HOLDING FOR EVERY PICTURE DRAWN AS LARGE AS IT IS SHOWN
/// (thumbnails-and-export-on-one-new-picture, 유저 10-30 「붙잡는 곳 하나,
/// 크기는 지금처럼 보이는 만큼」): a document's pages ([PageRasters] — the
/// media viewer, the import and export windows' previews), the storyboard's
/// and the conte's panel pictures (`StoryboardCutThumbnailStore`) and the
/// sheets' media images (`SheetImageCache`). ↩️Each held its own: the pages
/// here, the other two in an `Lru` with a stand-in at another width, a
/// budget and a memory warning written out twice — the second of which
/// said the third would merge them.
///
/// What stays each one's own is what it is a view OF: how a picture is
/// drawn, which look makes it stale, and how its surface is told.
class ShownRasters<K extends Object, A extends Object> {
  ShownRasters({
    required this.budget,
    required int? Function(K key) wantedAt,
    required int Function(K key) lastUsed,
    required void Function(VoidCallback fn) rebuild,
    required bool Function() mounted,
    required void Function(int bytes) report,
    VoidCallback? ended,
  }) : _wantedAt = wantedAt,
       _lastUsed = lastUsed,
       _rebuild = rebuild,
       _mounted = mounted,
       _report = report,
       _ended = ended;

  /// What this device affords what is held, and where a memory warning
  /// puts it — see [ViewerRasterBudget].
  ///
  /// ⚠️Built with the surface, so a test that wants a tight one sets
  /// [ViewerRasterBudget.debugPageBytesOverride] BEFORE the surface is
  /// built; building the same one again reuses this budget.
  final ViewerRasterBudget budget;

  /// How many steps on a held picture is next wanted, null where it is not
  /// — the surface's answer, since only it knows where a playhead stands
  /// and whether it is running.
  final int? Function(K key) _wantedAt;

  /// How recently a held picture was used, as the surface counts it — the
  /// order among pictures wanted alike ([letGoWantedLatest]).
  final int Function(K key) _lastUsed;

  /// How a landing reaches what the surface draws — a `setState`, or the
  /// change alone where the surface hears [_ended].
  final void Function(VoidCallback fn) _rebuild;
  final bool Function() _mounted;

  /// Where the total goes after every change — the memory census cannot
  /// reach into a surface ([RenderCaches.viewerRasterBytesByViewer]).
  final void Function(int bytes) _report;

  /// Told when an ask is over — landed or refused — and what was [want]ed
  /// is gone: a surface that asks while it paints repaints, and asks again
  /// for what it shows NOW. Null for a surface that asks while it builds:
  /// its landing rebuilds, and a refusal waits for its clock
  /// ([forgetRefusals]).
  final VoidCallback? _ended;

  final Map<K, _Held<A>> _held = {};

  /// The pictures the surface shows now — every page on screen in a book,
  /// the page a document that turns its own stands on. Set where they are
  /// drawn; nothing held lets one of them go ([evictToBudget]).
  Set<K> shown = const {};

  /// What a cut's read holds while it is out (I-14): billed to [budget]
  /// beside what is held, and reported to the census with it.
  int extraBytes = 0;

  /// What has been asked, one entry per (key, look) — landings remove their
  /// own entry, so a stale landing can never wipe a newer one.
  ///
  /// 🚨★★★**A RENDER HAS THREE OUTCOMES AND THIS USED TO HAVE ROOM FOR
  /// TWO.** It was a `Set`, so ABSENT answered both 「nobody has asked」 and
  /// 「the last ask failed, so asking again right now is fine」 — and the
  /// failure arm below cleared the marker inside a `setState`. That rebuild
  /// re-entered `build`, which asks for the same page again, which fails
  /// again, which rebuilds: measured at eleven asks for one unreadable frame
  /// across three ticks, throttled by nothing but how fast the decoder can
  /// say no. On the tablets this app is written for
  /// ([[old-device-support-policy]]) that is a spinning CPU under a picture
  /// that is not moving.
  final Map<(K, A), _RenderAsk> _renders = {};

  /// What a surface asked for while it painted since the last ask ended, in
  /// the order it asked — each at the look it was asked at.
  final Map<K, (A, Future<ui.Image> Function())> _wanted = {};
  bool _nextScheduled = false;

  /// Guards every landing against what was turned away since.
  int _generation = 0;

  /// [_Held.usedAt]'s clock.
  int _clock = 0;

  /// The raster [key] has, at whatever look it landed — a blurrier render
  /// of the SAME page is not a lie about which frame this is.
  ui.Image? imageOf(K key) => _held[key]?.image;

  /// [key]'s picture was just used: the last to go among those wanted alike
  /// where the surface counts by use ([usedAt]).
  void use(K key) => _held[key]?.usedAt = _clock += 1;

  /// When [key]'s picture was last used — its landing or its last [use].
  int usedAt(K key) => _held[key]?.usedAt ?? 0;

  /// The sharpest held of the pictures [samePicture] names — the one to
  /// show while another width of it renders. ⛔Not a [use]: a stand-in
  /// stays as old as it was, so it is the first to go once the width asked
  /// for is in.
  ui.Image? sharpestOf(bool Function(K key) samePicture) {
    ui.Image? sharpest;
    for (final MapEntry(:key, value: held) in _held.entries) {
      if (samePicture(key) &&
          (sharpest == null || held.image.width > sharpest.width)) {
        sharpest = held.image;
      }
    }
    return sharpest;
  }

  /// Whether a render is out right now.
  ///
  /// ⛔Not `_renders.isNotEmpty`: a FAILED entry is remembered until the
  /// next tick, and counting it as in-flight would stop the read-ahead from
  /// ever issuing anything again.
  bool get rendering => _renders.values.any((ask) => ask == _RenderAsk.asking);

  /// Whether a picture a surface asked for is still to come: a render is
  /// out or waits to go ([want]).
  bool get pending => rendering || _wanted.isNotEmpty;

  /// Whether [key] is ready to draw at [at].
  bool readyAt(K key, A at) => _held[key]?.at == at;

  /// Forgets every refusal, so the next ask goes out — the play tick's
  /// retry clock, and a turn of the page by hand.
  void forgetRefusals() =>
      _renders.removeWhere((_, ask) => ask == _RenderAsk.failed);

  /// Asks [render] for [key] at [at] now, unless it is held at that look
  /// or already asked.
  void ask(K key, A at, Future<ui.Image> Function() render) {
    // One entry PER (key, look): a shared single slot got wiped by
    // whichever render landed first, and the wipe re-issued duplicates
    // of work already queued on PDFium's serial worker.
    //
    // 🚨An entry of EITHER kind stops the ask — in flight means 「already
    // out」 and failed means 「not until the clock says so」. See [_renders].
    if (readyAt(key, at) || _renders.containsKey((key, at))) {
      return;
    }
    _renders[(key, at)] = _RenderAsk.asking;
    final generation = _generation;
    bool stillWanted() => _mounted() && generation == _generation;
    unawaited(() async {
      final image = await decodedImageStillWanted(
        Future.sync(render),
        wanted: stillWanted,
        // ⛔NO `setState` on this road. Nothing the eye can see changed — the
        // page that was not there is still not there — and the rebuild is
        // exactly what made a refused frame ask again immediately, and
        // again, for as long as it kept being refused. The retry belongs to
        // the play tick, which is the clock that actually needs the frame.
        onFailed: () {
          if (stillWanted()) {
            _renders[(key, at)] = _RenderAsk.failed;
            _askIsOver();
          }
        },
      );
      if (image == null) {
        return;
      }
      _rebuild(() {
        _renders.remove((key, at));
        _held[key]?.image.dispose();
        _held[key] = _Held(at: at, image: image, usedAt: _clock += 1);
        evictToBudget(keeping: key);
      });
      _askIsOver();
    }());
  }

  /// Asks for [key] at [at] off the paint that wants it — 🚨★★★ONE RENDER
  /// AT A TIME, AND ONLY WHAT IS SHOWN NOW (2026-09-28 — 유저: 「fu파일로,
  /// 콘티패널 v행 크기 늘리던 도중에 튕겻어」). Every ask of the panels used
  /// to start its own render on the spot; growing the V rows asked every
  /// panel on screen afresh at each step, and one second of it had 104
  /// renders running at once — the crash on a tablet. A want only goes on a
  /// list; one render runs, the first asked, and when it ends the list goes
  /// ([_ended]): the surface asks again for exactly what it shows NOW, so a
  /// width the hand has already passed or a panel scrolled away is never
  /// rendered at all.
  ///
  /// The render starts in a microtask, so a picture can land within a
  /// frame or two of the paint that asked.
  void want(K key, A at, Future<ui.Image> Function() render) {
    if (readyAt(key, at) || _renders.containsKey((key, at))) {
      return;
    }
    _wanted[key] = (at, render);
    if (rendering || _nextScheduled) {
      return;
    }
    _nextScheduled = true;
    scheduleMicrotask(_askNext);
  }

  /// The first wanted that still has to be asked for, asked.
  void _askNext() {
    _nextScheduled = false;
    while (_mounted() && !rendering && _wanted.isNotEmpty) {
      final key = _wanted.keys.first;
      final (at, render) = _wanted.remove(key)!;
      ask(key, at, render);
    }
  }

  void _askIsOver() {
    _wanted.clear();
    _ended?.call();
  }

  /// Drops held pictures, the one wanted latest first, until what is held
  /// fits [ViewerRasterBudget.byteBudget] — and answers what it holds.
  ///
  /// 🚨THE ORDER PLAYBACK'S CACHES LET GO BY, IN THEIR CODE
  /// ([letGoWantedLatest]; viewer-plays-by-the-one-playback-law, ②).
  /// ↩️This drain spelled it again: the farthest page from the one on
  /// screen, by a measure of its own.
  ///
  /// 🚨[keeping] is never evicted. A raster that has just LANDED for a
  /// page already paged away from is itself the farthest entry, and an
  /// eviction that could drop it would throw away the render it was
  /// called to install — the old count-based drain excluded it for the
  /// same reason.
  ///
  /// ⚠️Bytes, not entries. Four pages meant a quarter of a gigabyte for a
  /// big PDF and under a megabyte for thumbnails; the bound has to be in
  /// the unit that runs out.
  int evictToBudget({required K keeping}) {
    // ⛔Never a page on screen: in a book several are (F-201), and one let
    // go would only be rendered again for the next frame. So the drain
    // ends when only those are left — over the budget by what the
    // screen shows, which no eviction could give back.
    _letGo(maxBytes: budget.byteBudget, kept: {keeping, ...shown});
    return heldBytes;
  }

  /// Makes room for a picture of [bytes] by letting go of the pictures
  /// wanted LATER than [step] — the canvas's room, the same law
  /// ([letGoWantedLatest] with `laterThan`): a picture is asked for only by
  /// letting go of pictures wanted after it — and answers whether it fits.
  bool makeRoom(int bytes, {required int step}) => _letGo(
    maxBytes: budget.byteBudget - bytes,
    kept: shown,
    laterThan: step,
  );

  /// What the held pictures cost resident, 4 bytes a pixel.
  int get heldBytes {
    var total = 0;
    for (final held in _held.values) {
      total += ViewerRasterBudget.costOf(held.image);
    }
    return total;
  }

  /// Lets pictures go, the one wanted latest first, until what is held is
  /// at or under [maxBytes] — never one of [kept], nor one wanted at or
  /// before [laterThan] — and answers whether it got there.
  ///
  /// A picture let go is disposed at once: the surfaces that draw these ask
  /// for them as they build or paint, and a picture already painted holds
  /// its own.
  bool _letGo({required int maxBytes, required Set<K> kept, int? laterThan}) {
    var total = heldBytes;
    final fits = letGoWantedLatest(
      entries: [
        for (final entry in _held.entries)
          if (!kept.contains(entry.key)) entry,
      ],
      // A cut's read is billed beside the pages (I-14), so they make room.
      heldBytes: total + extraBytes,
      maxBytes: maxBytes,
      wantedAt: (entry) => _wantedAt(entry.key),
      lastUsed: (entry) => _lastUsed(entry.key),
      bytesOf: (entry) => ViewerRasterBudget.costOf(entry.value.image),
      letGo: (entry) {
        _held.remove(entry.key);
        total -= ViewerRasterBudget.costOf(entry.value.image);
        entry.value.image.dispose();
      },
      laterThan: laterThan,
    );
    // Every path that changes what is held ends here or in [clear].
    _report(total + extraBytes);
    return fits;
  }

  /// The OS said memory is tight: the budget halves
  /// ([ViewerRasterBudget.respondToMemoryPressure]) and what is held sheds
  /// down to it — never [keeping], the picture being looked at.
  void heardMemoryPressure({K? keeping}) {
    if (!budget.respondToMemoryPressure()) {
      return;
    }
    _rebuild(
      () => _letGo(
        maxBytes: budget.byteBudget,
        kept: {?keeping, ...shown},
      ),
    );
  }

  /// Something new takes the place of what these pictures came from, for
  /// the same bytes: what is drawn stays, and a render still out on the old
  /// one lands nowhere and is asked of the new.
  void turnAway() {
    _generation += 1;
    _renders.clear();
  }

  /// Nothing kept — what these are pictures of is gone, or draws another
  /// way.
  void clear() {
    _generation += 1;
    for (final held in _held.values) {
      held.image.dispose();
    }
    _held.clear();
    _renders.clear();
    _wanted.clear();
    shown = const {};
    _report(0);
  }
}
