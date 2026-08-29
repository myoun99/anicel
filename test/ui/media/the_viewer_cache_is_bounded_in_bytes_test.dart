import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';

import '../../helpers/fake_pdf_document.dart';

/// 🚨★★★**A COUNT IS NOT A BOUND.**
///
/// The viewer kept four pages. Four pages of a big PDF at the render cap
/// is a quarter of a gigabyte; four thumbnails is under a megabyte — one
/// number meaning both. And it was the only pixel cache in the app that
/// never heard `didHaveMemoryPressure`, so on a small tablet the canvas
/// scaled itself down while the viewer beside it did not budge.
///
/// These drive the real panel: what a test can see is which pages have to
/// be RE-RENDERED when you page back to them, which is exactly what an
/// eviction costs.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;

  /// Distinguishes one open from the next.
  ///
  /// 🚨Two things here bite, and both looked like a hang rather than a
  /// failure. [MediaViewerRequest] is const, so re-opening the same path
  /// canonicalises to the SAME object and a `ValueNotifier` set to the
  /// value it already holds notifies nobody — the panel goes on showing
  /// the previous document. And the budget is read once, when the State is
  /// built, so a second `pumpWidget` of the same widget type reuses the
  /// State and the override set in between never reaches it.
  var opens = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    opens = 0;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    ViewerRasterBudget.debugPageBytesOverride = null;
    slot.dispose();
    session.dispose();
  });

  /// Mounts a FRESH viewer on a fresh document — see [opens] for why both
  /// halves of that matter.
  Future<FakePdfDocument> openConte(
    WidgetTester tester, {
    required int pages,
  }) async {
    opens += 1;
    // Unmount whatever is there so the next pump builds a new State, and
    // with it a new budget that reads the current override.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    slot.request.value = null;
    slot.position.value = 0;

    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(pages, const ui.Size(595, 842)),
    );
    PdfRenderService.debugOpenerOverride = (path) async => fake;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: slot.position,
            builder: (context, position, _) => MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: position,
              onPositionChanged: (next) => slot.position.value = next,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    slot.request.value = MediaViewerRequest(
      path: 'C:/work/conte-$opens.pdf',
      kind: MediaAssetKind.pdf,
      name: 'conte',
    );
    await tester.pumpAndSettle();
    expect(
      fake.renderRequests,
      isNotEmpty,
      reason: 'fixture: the document opened and drew its first page',
    );
    return fake;
  }

  Future<void> turnTo(WidgetTester tester, int page) async {
    var guard = 0;
    while (slot.position.value != page) {
      expect(guard++, lessThan(64), reason: 'fixture: paging is not moving');
      final forward = slot.position.value < page;
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'media-viewer-${forward ? "next" : "previous"}-page-button',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  /// Pages that had to be rendered a SECOND time — one per eviction that
  /// the user then paged back into.
  List<int> reRendered(FakePdfDocument fake) {
    final seen = <int>{};
    final again = <int>[];
    for (final request in fake.renderRequests) {
      if (!seen.add(request.$1)) {
        again.add(request.$1);
      }
    }
    return again;
  }

  /// What ONE page costs in this harness. The render scale comes from the
  /// panel's own framing, so a number written here by hand would be a
  /// guess — and a wrong guess makes every budget assertion below vacuous
  /// rather than red.
  Future<int> measureOnePage(WidgetTester tester) async {
    final probe = await openConte(tester, pages: 2);
    final first = probe.renderRequests.first;
    final bytes = first.$2 * first.$3 * 4;
    expect(bytes, greaterThan(0));
    return bytes;
  }

  testWidgets('six small pages all stay cached — the old four-entry cap '
      'evicted by COUNT and re-rendered page 0 for no reason', (tester) async {
    final fake = await openConte(tester, pages: 6);
    for (var page = 1; page < 6; page += 1) {
      await turnTo(tester, page);
    }
    await turnTo(tester, 0);

    expect(
      fake.renderRequests.map((request) => request.$1),
      [0, 1, 2, 3, 4, 5],
      reason:
          'every page rendered once and NONE twice: six A4 rasters are a '
          'few megabytes, and the budget is the desktop 256MB',
    );
    expect(reRendered(fake), isEmpty);
  });

  testWidgets('a TIGHTER budget holds fewer pages — which a count could '
      'not express at all', (tester) async {
    // 🚨This is the assertion that separates the two designs, and the
    // first version of it did NOT: with every page the same size, "four
    // entries" and "four pages of bytes" evict identically, so the test
    // passed against the code it was written to replace.
    //
    // Half a page each, so the budget is TWO pages. A count of four
    // cannot be two, whatever the pages weigh.
    ViewerRasterBudget.debugPageBytesOverride =
        await measureOnePage(tester) ~/ 2;
    final fake = await openConte(tester, pages: 6);
    for (var page = 1; page < 6; page += 1) {
      await turnTo(tester, page);
    }
    for (var page = 4; page >= 0; page -= 1) {
      await turnTo(tester, page);
    }

    expect(
      reRendered(fake),
      [3, 2, 1, 0],
      reason:
          'the cache holds the page on screen and ONE neighbour, so '
          'walking back re-renders every page below the pair it kept — '
          'a four-entry cache would have re-rendered only 1 and 0',
    );
  });

  testWidgets('the OS says memory is tight and the viewer stands down too', (
    tester,
  ) async {
    ViewerRasterBudget.debugPageBytesOverride = await measureOnePage(tester);
    final fake = await openConte(tester, pages: 3);
    await turnTo(tester, 1);
    await turnTo(tester, 2);
    expect(
      reRendered(fake),
      isEmpty,
      reason: 'fixture: three pages fit in a four-page budget',
    );

    // 🚨THE WHOLE POINT. This is the signal the workspace forwards from
    // `didHaveMemoryPressure`, and the viewer used to be the one pixel
    // cache in the app that never heard it.
    session.respondToMemoryPressure();
    await tester.pumpAndSettle();

    await turnTo(tester, 0);
    expect(
      reRendered(fake),
      [0],
      reason:
          'the budget halved to two pages, so the page farthest from the '
          'one on screen was dropped',
    );
  });

  /// 🚨**A CACHE THIS BIG MUST APPEAR IN THE PANEL THAT SAYS WHERE MEMORY
  /// GOES** (유저 요청: 「이 앱이 쓰는 메모리의 총합 … 어떤항목이 얼만큼」).
  ///
  /// The census counts seven holders the session owns. The viewer's pages
  /// were not among them, so up to a quarter of a gigabyte PER VIEWER fell
  /// into `untrackedBytes` and read as engine overhead.
  group('the census can see the viewer', () {
    testWidgets('a loaded viewer reports its page bytes', (tester) async {
      expect(
        session.viewerRasterBytes,
        0,
        reason: 'fixture premise: nothing loaded yet',
      );

      await openConte(tester, pages: 3);
      await turnTo(tester, 1);

      final item = collectMemoryCensus(
        session,
      ).items.firstWhere((entry) => entry.id == 'viewerPages');
      expect(
        item.bytes,
        greaterThan(0),
        reason: 'two rendered pages are in the census, not in the gap',
      );
      expect(item.bytes, session.viewerRasterBytes);
    });

    testWidgets('and stops reporting when it goes away', (tester) async {
      await openConte(tester, pages: 3);
      await turnTo(tester, 1);
      expect(session.viewerRasterBytes, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        session.viewerRasterBytesByViewer,
        isEmpty,
        reason:
            '⛔the entry is REMOVED, not zeroed — a closed tab is not a '
            'viewer holding nothing, and one entry per close would grow '
            'for the life of the session',
      );
      expect(session.viewerRasterBytes, 0);
    });
  });

  testWidgets('the page being LOOKED AT survives every warning', (
    tester,
  ) async {
    ViewerRasterBudget.debugPageBytesOverride = await measureOnePage(tester);
    final fake = await openConte(tester, pages: 3);
    await turnTo(tester, 1);
    final before = fake.renderRequests.length;

    // Repeatedly, the way iOS actually sends them as things get worse.
    for (var i = 0; i < 6; i += 1) {
      session.respondToMemoryPressure();
      await tester.pumpAndSettle();
    }

    expect(
      fake.renderRequests.length,
      before,
      reason:
          'evicting the visible page would only force it straight back — '
          'the floor is one page, and it is not negotiable',
    );
  });
}
