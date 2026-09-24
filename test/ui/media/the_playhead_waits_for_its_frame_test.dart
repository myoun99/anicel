import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/fake_pdf_document.dart';

/// 🚨★★★**THE PLAYHEAD WAITS. IT DOES NOT WALK PAST A FRAME THAT IS NOT
/// THERE, AND IT DOES NOT DRAW THE LAST ONE INSTEAD.**
///
/// 🪦This file replaces `the_viewer_does_not_flash_white_test`, which pinned
/// the opposite: 「turning to a page that has not rendered keeps the last
/// picture on screen」. That was a real answer to a real report — 유저
/// 2026-08-31, on a video reference: 「첫 재생때 … 흰 화면이 엄청나게
/// 깜빡이면서 재생됨」 — and it was the wrong one.
///
/// 유저 2026-08-31, on seeing it: 「직전그림을 유지하게 하는건 진짜 아니라고
/// 생각하거든? … 유지하지말고 **로드할때까지 멈춰있어야지**」, and then,
/// correcting the word: 「그림을 유지한다는게 아니라 **그 곳에 멈춘다**는거야」.
///
/// The reason is not taste. **A held picture cannot be told apart from a
/// hold the animator drew** — and telling those apart is the one judgement
/// a reference viewer exists to support. Parking the playhead makes the
/// screen honest again: the picture stays because the playhead is genuinely
/// on that frame.
///
/// ⚠️The CANVAS is the opposite and is also right. It judges timing against
/// sound, so it holds real time and drops frames — `AudioPlaybackSync` says
/// so in one line: 「frames drop, time never stretches」. A player looking at
/// reference has nothing riding on the clock, so it buffers.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;
  var opens = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    opens = 0;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    slot.dispose();
    session.dispose();
  });

  Future<FakePdfDocument> open(
    WidgetTester tester, {
    required int pages,
    double? framesPerSecond,
  }) async {
    opens += 1;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    slot.request.value = null;
    slot.position.value = 0;

    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(pages, const ui.Size(595, 842)),
      framesPerSecond: framesPerSecond,
    );
    PdfRenderService.debugOpenerOverride = (_) async => fake;
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
      path: 'C:/work/clip-$opens.pdf',
      kind: MediaAssetKind.pdf,
      name: 'clip',
    );
    await tester.pumpAndSettle();
    return fake;
  }

  /// What the page painter was actually handed this frame.
  ///
  /// ⛔Read from the painter rather than from a golden: the question is
  ///「WHICH page reached the screen」, and a golden of one grey rectangle
  /// looks like a golden of another.
  ui.Image? drawnImage(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('media-viewer-page')),
    );
    return (paint.painter as dynamic).image as ui.Image?;
  }

  testWidgets('🚨a page whose raster has not landed draws NOTHING — never '
      'the page before it', (tester) async {
    final fake = await open(tester, pages: 3);
    final first = drawnImage(tester);
    expect(first, isNotNull, reason: 'fixture: page 0 landed');

    fake.holdRender(1);
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-next-page-button')),
    );
    await tester.pump();

    expect(
      drawnImage(tester),
      isNull,
      reason:
          '🚨the old law drew page 0 here, and page 0 on a playhead that '
          'says 1 is a picture claiming to be a frame it is not',
    );

    fake.releaseRender(1);
    await tester.pumpAndSettle();
    final second = drawnImage(tester);
    expect(second, isNotNull);
    expect(second, isNot(same(first)), reason: 'and page 1 lands as itself');
  });

  testWidgets('🚨playing does not advance onto a frame that has not landed, '
      'and carries on when the cushion refills', (tester) async {
    // 24fps so a tick is 41ms — short enough that the pumps below cross
    // several of them, which is the point: the playhead must STILL be where
    // it was.
    final fake = await open(tester, pages: 12, framesPerSecond: 24);
    // Everything past the first page is held, so the buffer cannot fill.
    for (var page = 1; page < 12; page += 1) {
      fake.holdRender(page);
    }
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();
    final parkedAt = slot.position.value;

    // Ten ticks' worth of clock with nothing decoded.
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump(const Duration(milliseconds: 42));
    }
    expect(
      slot.position.value,
      parkedAt,
      reason:
          '🚨the wall clock ran and the playhead did not — 「로드할때까지 '
          '멈춰있어야지」. The old law would be ten frames further on, '
          'showing the same picture the whole way.',
    );
    expect(
      drawnImage(tester),
      isNotNull,
      reason:
          'and the picture IS there: the playhead is parked on a frame it '
          'has, which is why holding it is honest now',
    );

    // Let the buffer fill and the playhead carries on by itself.
    for (var page = 1; page < 12; page += 1) {
      fake.releaseRender(page);
    }
    await tester.pumpAndSettle();
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump(const Duration(milliseconds: 42));
    }
    expect(
      slot.position.value,
      greaterThan(parkedAt),
      reason: 'a parked playhead is parked, not stopped',
    );
  });
}
