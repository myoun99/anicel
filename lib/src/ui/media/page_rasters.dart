import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show VoidCallback;

import '../../services/media/viewer_document.dart';
import '../../services/straight_rgba_image.dart' show decodedImageStillWanted;
import 'viewer_raster_budget.dart';

/// One lazily rendered page: the raster and the scale it was rendered at
/// (stale-while-revalidate — a wrong-scale image still draws while the
/// right one renders).
class _RenderedPage {
  const _RenderedPage({required this.scale, required this.image});

  final double scale;
  final ui.Image image;
}

/// What was last asked of the document for one (page, scale).
///
/// 🚨★★★**LANDED IS NOT A VALUE HERE — IT IS THE ABSENCE OF ONE**, because
/// a landed render lives in the page cache and this map is about what is
/// still owed. What this type exists to separate is the other two, which
/// were both spelled 「not in the set」 before 2026-09-08. See
/// [PageRasters._renders].
enum _RenderAsk {
  /// Out with the document, no answer yet.
  asking,

  /// The document refused this one. ⛔It is remembered until the play tick
  /// forgets it: asking again the instant it fails is a loop, and never
  /// asking again is a viewer that cannot recover when the frame becomes
  /// readable — and recovery is the law here (유저 2026-08-31, 「로드할때까지
  /// 멈춰있어야지」, which is a WAIT and not a surrender).
  failed,
}

/// THE PAGES A SURFACE DRAWS, AS RASTERS — asked of the document one at a
/// time at the scale the view draws them, kept under the device's budget,
/// and a page the document refused asked for again only when a clock says
/// so ([forgetRefusals]).
///
/// 🚨One of these per surface that shows a [ViewerDocument] — the media
/// viewer's, and the import window's preview (import-preview-plays-silent,
/// 2026-09-29: 「뷰어패널이랑 통일할거하면서」). It lived inside the viewer,
/// and a second surface that plays would have been a second copy of it.
class PageRasters {
  PageRasters({
    required this.budget,
    required ViewerDocument? Function() document,
    required int Function(int page) distance,
    required void Function(VoidCallback fn) rebuild,
    required bool Function() mounted,
    required void Function(int bytes) report,
  }) : _document = document,
       _distance = distance,
       _rebuild = rebuild,
       _mounted = mounted,
       _report = report;

  /// What this device affords the page cache, and where a memory warning
  /// puts it — see [ViewerRasterBudget].
  ///
  /// ⚠️Built with the surface, so a test that wants a tight one sets
  /// [ViewerRasterBudget.debugPageBytesOverride] BEFORE the panel mounts;
  /// pumping the same widget again reuses this budget.
  final ViewerRasterBudget budget;

  /// The document shown — the surface's, asked when a page goes out.
  final ViewerDocument? Function() _document;

  /// How far a cached page is from being wanted again — the surface's
  /// measure, since only it knows where the playhead stands and whether it
  /// is running.
  final int Function(int page) _distance;
  final void Function(VoidCallback fn) _rebuild;
  final bool Function() _mounted;

  /// Where the total goes after every change — the memory census cannot
  /// reach into a surface ([RenderCaches.viewerRasterBytesByViewer]).
  final void Function(int bytes) _report;

  final Map<int, _RenderedPage> _cache = {};

  /// The pages the view shows now — every one on screen in a book, the
  /// page in a document that turns its own. Set where they are drawn;
  /// the cache never lets one of them go ([evictToBudget]).
  Set<int> shown = const {};

  /// The render scale the last build chose. The buffer measures readiness
  /// in the unit the cache is keyed by, and only build knows the zoom —
  /// the timer that asks cannot work it out.
  double? scale;

  /// What a cut's read holds while it is out (I-14): billed to [budget]
  /// beside the page cache, and reported to the census with it.
  int extraBytes = 0;

  /// What has been asked of the document, one entry per (page, scale) —
  /// landings remove their own entry, so a stale landing can never wipe a
  /// newer one.
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
  final Map<(int, double), _RenderAsk> _renders = {};

  /// Guards every landing against a document turned away since.
  int _generation = 0;

  /// The raster [page] has, at whatever scale it landed — a blurrier render
  /// of the SAME page is not a lie about which frame this is.
  ui.Image? imageOf(int page) => _cache[page]?.image;

  /// Whether a render is out with the document right now.
  ///
  /// ⛔Not `_renders.isNotEmpty`: a FAILED entry is remembered until the
  /// next tick, and counting it as in-flight would stop the read-ahead from
  /// ever issuing anything again.
  bool get rendering => _renders.values.any((ask) => ask == _RenderAsk.asking);

  /// Whether [page] is ready to draw at [scale].
  bool readyAt(int page, double scale) {
    final cached = _cache[page];
    return cached != null && cached.scale == scale;
  }

  /// How many consecutive pages from [from] are ready to draw at the scale
  /// the last build chose.
  int readyFrom(int from, int pageCount) {
    final at = scale;
    if (at == null) {
      return 0;
    }
    var ready = 0;
    while (from + ready < pageCount && readyAt(from + ready, at)) {
      ready += 1;
    }
    return ready;
  }

  /// Forgets every refusal, so the next ask goes out — the play tick's
  /// retry clock, and a turn of the page by hand.
  void forgetRefusals() =>
      _renders.removeWhere((_, ask) => ask == _RenderAsk.failed);

  /// Asks the document for [pageIndex] at [at], unless it is cached at
  /// that scale or already asked.
  void ensureRendered(int pageIndex, double at) {
    final document = _document();
    if (document == null || readyAt(pageIndex, at)) {
      return;
    }
    // One entry PER (page, scale): a shared single slot got wiped by
    // whichever render landed first, and the wipe re-issued duplicates
    // of work already queued on PDFium's serial worker.
    //
    // 🚨An entry of EITHER kind stops the ask — in flight means 「already
    // out」 and failed means 「not until the clock says so」. See [_renders].
    if (_renders.containsKey((pageIndex, at))) {
      return;
    }
    _renders[(pageIndex, at)] = _RenderAsk.asking;
    final generation = _generation;
    final pageSize = document.pageSize(pageIndex);
    unawaited(() async {
      final image = await decodedImageStillWanted(
        document.renderPage(
          pageIndex,
          width: (pageSize.width * at).round().clamp(1, 1 << 13).toInt(),
          height: (pageSize.height * at).round().clamp(1, 1 << 13).toInt(),
        ),
        wanted: () => _mounted() && generation == _generation,
        // ⛔NO `setState` on this road. Nothing the eye can see changed — the
        // page that was not there is still not there — and the rebuild is
        // exactly what made a refused frame ask again immediately, and
        // again, for as long as it kept being refused. The retry belongs to
        // the play tick, which is the clock that actually needs the frame.
        onFailed: () {
          if (_mounted() && generation == _generation) {
            _renders[(pageIndex, at)] = _RenderAsk.failed;
          }
        },
      );
      if (image == null) {
        return;
      }
      _rebuild(() {
        _renders.remove((pageIndex, at));
        _heldOver?.dispose();
        _heldOver = null;
        _cache[pageIndex]?.image.dispose();
        _cache[pageIndex] = _RenderedPage(scale: at, image: image);
        evictToBudget(keeping: pageIndex);
      });
    }());
  }

  /// Drops cached pages, farthest from the one on screen first, until the
  /// cache fits [ViewerRasterBudget.byteBudget] — and answers what it holds.
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
  int evictToBudget({required int keeping}) {
    var total = 0;
    for (final page in _cache.values) {
      total += ViewerRasterBudget.costOf(page.image);
    }
    // ⛔Never a page on screen: in a book several are (F-201), and one let
    // go would only be rendered again for the next frame. So the loop
    // ends when only those are left — over the budget by what the
    // screen shows, which no eviction could give back.
    final kept = {keeping, ...shown};
    // A cut's read is billed beside the pages (I-14), so they make room.
    while (total + extraBytes > budget.byteBudget) {
      final candidates = _cache.keys.where((page) => !kept.contains(page));
      if (candidates.isEmpty) {
        break;
      }
      final farthest = candidates.reduce(
        (a, b) => _distance(a) >= _distance(b) ? a : b,
      );
      final dropped = _cache.remove(farthest)!;
      total -= ViewerRasterBudget.costOf(dropped.image);
      dropped.image.dispose();
    }
    // Every path that changes the cache ends here or in [clear].
    _report(total + extraBytes);
    return total;
  }

  /// The OS said memory is tight: the budget halves
  /// ([ViewerRasterBudget.respondToMemoryPressure]) and the cache sheds down
  /// to it — never [keeping], the page being looked at.
  void heardMemoryPressure({required int keeping}) {
    if (!budget.respondToMemoryPressure()) {
      return;
    }
    _rebuild(() => evictToBudget(keeping: keeping));
  }

  /// A new document takes the place of the one these pages came from, for
  /// the same bytes: what is drawn stays, and a render still out on the old
  /// one lands nowhere and is asked of the new.
  void turnAway() {
    _generation += 1;
    _renders.clear();
  }

  /// The picture held over from before the document changed its look
  /// ([changedLook]) — what a surface draws until a page of the new look
  /// lands, which lets it go.
  ui.Image? get heldOver => _heldOver;
  ui.Image? _heldOver;

  /// The document draws its pages another way now: every page is owed a
  /// new render, and the picture that is up — page [showing]'s — is HELD
  /// OVER until the first of them lands.
  ///
  /// The export window's preview (F-289): a setting that changes what a
  /// frame looks like is not to blank the frame it is changing. ⚠️One
  /// picture, out of the cache: the cache only ever holds pages of the look
  /// that stands, so a page turned to is never an older look's.
  void changedLook({required int? showing}) {
    final up = (showing == null ? null : _cache.remove(showing))?.image;
    final held = up ?? _heldOver;
    if (up != null) {
      _heldOver?.dispose();
    }
    _heldOver = null;
    clear();
    _heldOver = held;
    if (held != null) {
      _report(ViewerRasterBudget.costOf(held));
    }
  }

  /// Nothing kept — the document is gone.
  void clear() {
    _generation += 1;
    _heldOver?.dispose();
    _heldOver = null;
    for (final page in _cache.values) {
      page.image.dispose();
    }
    _cache.clear();
    _renders.clear();
    scale = null;
    shown = const {};
    _report(0);
  }
}
