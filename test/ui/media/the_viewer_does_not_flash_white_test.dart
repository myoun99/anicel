import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/fake_pdf_document.dart';

/// 🚨★★★**A PAGE THAT HAS NOT LANDED SHOWS THE LAST ONE, NOT WHITE.**
///
/// 유저 2026-08-31, on a video reference: 「첫 재생때 아마 파일이 제대로
/// 로드안되서 **흰 화면이 엄청나게 깜빡이면서** 재생됨. 두번째 재생부터 점점
/// 나아짐. 세번째부터는 흰 화면 없이 정상재생 확인됨」.
///
/// The flashes were the cold cache. Playback advances the playhead on a
/// wall clock and draws whatever raster has landed — and a page with none
/// drew NOTHING, one white frame per miss, disappearing as the cache filled
/// on later plays. `_RenderedPage` already said a wrong-SCALE image draws
/// while the right one renders; the page axis simply had no such rule.
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
  }) async {
    opens += 1;
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
  ///「did anything reach the screen」, and a golden of a white rect and a
  /// golden of no rect at all are the same picture in a headless test.
  ui.Image? drawnImage(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('media-viewer-page')),
    );
    return (paint.painter as dynamic).image as ui.Image?;
  }

  testWidgets('🚨turning to a page that has not rendered keeps the last '
      'picture on screen', (tester) async {
    final fake = await open(tester, pages: 3);
    final first = drawnImage(tester);
    expect(first, isNotNull, reason: 'fixture: page 0 landed');

    // Page 1 is held mid-render — the state a movie spends its whole first
    // play in.
    fake.holdRender(1);
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-next-page-button')),
    );
    await tester.pump();

    expect(
      drawnImage(tester),
      same(first),
      reason:
          '⛔white here is the flash the user reported — one per miss, on '
          'every frame of a first play',
    );

    fake.releaseRender(1);
    await tester.pumpAndSettle();

    final second = drawnImage(tester);
    expect(second, isNotNull);
    expect(
      second,
      isNot(same(first)),
      reason: 'and the real page replaces it the moment it lands',
    );
  });

  testWidgets('a fresh document does not show the previous one', (
    tester,
  ) async {
    await open(tester, pages: 2);
    expect(drawnImage(tester), isNotNull);

    // ⛔The fallback is per-DOCUMENT. An index carried across an open would
    // name an image that was disposed with the old cache.
    final next = await open(tester, pages: 2);
    expect(next.renderRequests, isNotEmpty);
    expect(drawnImage(tester), isNotNull);
  });
}
