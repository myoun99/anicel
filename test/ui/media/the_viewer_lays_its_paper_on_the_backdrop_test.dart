// F-179 (유저 2026-09-25): 「타임시트패널,콘티프리뷰패널 등등 캔버스 베이스
// 패널의 페이스트보드 없애고 배경관련 통일」 · 「타임시트패널등 캔버스 베이스
// 패널엔 페이스트보드가 없다는 뜻임」.
//
// The viewer is one of those panels — F-201 names it one, beside the conte
// preview — and was the one left with a pasteboard when the sheets lost
// theirs.
//
// F-272 (유저 2026-10-03): 「캔버스 베이스 패널들은 배경색 캔버스의 배경색
// 따라가는데, 그냥 검정색 고정/통일. … 뷰어나 서브뷰어나 …」 — the main viewer
// and the sub viewer are this one host.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart'
    show CanvasStageColors;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/device_viewport.dart';
import '../../helpers/fake_pdf_document.dart';

void main() {
  testWidgets('the viewer lays its paper on black — nothing of the room, '
      'pasteboard or backdrop, is painted anywhere on its stage', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final slot = MediaViewerSlot();
    addTearDown(() {
      PdfRenderService.debugResetForTests();
      slot.dispose();
      session.dispose();
    });
    // Two colours nothing else on the stage uses, so one pixel of either
    // anywhere is an answer.
    const backdrop = 0xFFFF0000;
    const pasteboard = 0xFF0000FF;
    const boundaryKey = ValueKey<String>('stage');
    const path = 'C:/work/page.pdf';
    final fake = FakePdfDocument(pageSizes: const [ui.Size(600, 800)]);
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    // Zoomed out: the paper small in the middle, the stage round it.
    slot.framedFor.value = path;
    slot.viewport.value = seedFromRender(tester, CanvasViewport(zoom: 0.25));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: CanvasStageColors(
              backdropArgb: backdrop,
              pasteboardArgb: pasteboard,
              child: MediaViewerTabHost(
                viewerId: 'media-viewer',
                session: session,
                request: slot.request,
                position: slot.position,
                viewportController: slot.viewport,
                framedFor: slot.framedFor,
              ),
            ),
          ),
        ),
      ),
    );
    slot.open(const MediaViewerRequest(path: path, kind: MediaAssetKind.pdf));
    await tester.pumpAndSettle();
    expect(fake.renderRequests, isNotEmpty, reason: 'fixture: the page is up');

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final rgba = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();
      return data!.buffer.asUint8List();
    });
    var blackPixels = 0;
    var backdropPixels = 0;
    var pasteboardPixels = 0;
    for (var i = 0; i + 3 < rgba!.length; i += 4) {
      final argb =
          rgba[i + 3] << 24 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
      if (argb == 0xFF000000) {
        blackPixels += 1;
      } else if (argb == backdrop) {
        backdropPixels += 1;
      } else if (argb == pasteboard) {
        pasteboardPixels += 1;
      }
    }
    expect(blackPixels, greaterThan(0), reason: 'the stage shows, black');
    expect(backdropPixels, 0, reason: 'not the room\'s backdrop');
    expect(pasteboardPixels, 0, reason: 'no pasteboard plane under a page');
  });
}
