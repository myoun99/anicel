import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

import '../../helpers/device_viewport.dart';
import '../../helpers/fake_pdf_document.dart';

/// 🗣️I-14 (유저 2026-09-11): 「뷰어패널은 기본적으로 드로잉모드 존재안하니
/// 한손가락 핑거시 팬 … 그리고 뷰어패널의 잘라내기툴 사용 가능하도록.
/// 원본크기로 잘라냄. 그걸 캔버스에 배치하는용도」 — and, to be sure of the
/// size: 「34%의 크기가 스탬프 크기값이 100%이 되는게 아니라, 제대로 100%
/// 해상도만큼」.
///
/// The document is a fake whose region reads name their own pixels
/// ([FakePdfDocument.regionPixel]), so a piece says WHICH source pixels it
/// holds, and at what size.
void main() {
  const path = 'C:/work/reference.pdf';
  const pageSize = ui.Size(1200, 900);

  late EditorSessionManager session;
  late MediaViewerSlot slot;
  late CutPieceSlot held;
  late ValueNotifier<BrushToolState> tool;
  late FakePdfDocument document;

  BrushToolState cutTool() => BrushToolState.defaults.copyWith(
    tool: CanvasTool.cut,
    cutShape: CanvasShapeKind.rect,
  );

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    held = CutPieceSlot();
    tool = ValueNotifier<BrushToolState>(cutTool());
    document = FakePdfDocument(pageSizes: const [pageSize]);
    PdfRenderService.debugOpenerOverride = (_) async => document;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    ViewerRasterBudget.debugPageBytesOverride = null;
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    cursorNotices.clear();
    tool.dispose();
    slot.dispose();
    session.dispose();
  });

  /// The viewer at a DISPLAY zoom of 34% — the user's own example — and
  /// already framed, so the view stays where it was put.
  Future<void> pumpViewer(WidgetTester tester) async {
    slot.framedFor.value = path;
    slot.viewport.value = CanvasViewport(zoom: 0.34, panX: 40, panY: 40);
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
              viewportController: slot.viewport,
              framedFor: slot.framedFor,
              brushTool: tool,
              cutPieceSlot: held,
            ),
          ),
        ),
      ),
    );
    slot.open(const MediaViewerRequest(path: path, kind: MediaAssetKind.pdf));
    await tester.pumpAndSettle();
  }

  /// Where page point ([x], [y]) is on screen right now.
  Offset onScreen(WidgetTester tester, double x, double y) {
    final panel = tester.widget<BrushCanvasPanel>(
      find.byType(BrushCanvasPanel),
    );
    final view = renderOf(tester, panel.publishedViewport);
    final local = view.canvasToViewport(CanvasPoint(x: x, y: y));
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
    );
    return origin + Offset(local.x, local.y);
  }

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    Offset to, {
    required PointerDeviceKind kind,
  }) async {
    final gesture = await tester.startGesture(from, kind: kind);
    await tester.pump();
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    // The read and the hold land on the microtasks after the release.
    await tester.pump();
    await tester.pump();
  }

  Future<void> cutDrag(WidgetTester tester) => drag(
    tester,
    onScreen(tester, 300, 200),
    onScreen(tester, 600, 500),
    kind: PointerDeviceKind.mouse,
  );

  testWidgets('🎯a cut at 34% holds the SOURCE\'s pixels at their own size '
      '— not the size on screen', (tester) async {
    await pumpViewer(tester);
    expect(held.isEmpty, isTrue);

    await cutDrag(tester);

    final piece = held.piece;
    expect(piece, isNotNull, reason: 'the cut reached the held piece');
    // Read at ONE pixel per page unit: the box the viewer asked the page
    // for IS the piece, pixel for pixel.
    final (page, left, top, width, height) = document.regionReads.single;
    expect(page, 0);
    expect((piece!.originLeft, piece.originTop), (left, top));
    expect((piece.image.width, piece.image.height), (width, height));
    // ~300 page pixels a side. The drag crossed ~34 logical pixels on
    // screen — a piece taken at the view's size would be a third of this
    // in device pixels, a ninth in logical ones.
    expect(width, inInclusiveRange(296, 306));
    expect(height, inInclusiveRange(296, 306));
    expect(left, inInclusiveRange(296, 304));
    expect(top, inInclusiveRange(196, 204));
    // And its pixels ARE the page's own.
    const inside = 10;
    final offset = (inside * width + inside) * 4;
    expect(
      piece.image.rgba.sublist(offset, offset + 4),
      FakePdfDocument.regionPixel(0, left + inside, top + inside),
    );
    // The stamp's 100% is that size.
    expect(piece.scalePercent, 100);
    expect((piece.stampWidth, piece.stampHeight), (width, height));
  });

  testWidgets('a finger PANS the viewer and cuts nothing — even with the '
      'one-finger slot on draw', (tester) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    await pumpViewer(tester);
    final before = slot.viewport.value!;

    await drag(
      tester,
      onScreen(tester, 300, 200),
      onScreen(tester, 900, 700),
      kind: PointerDeviceKind.touch,
    );

    expect(
      slot.viewport.value!.panX,
      greaterThan(before.panX + 50),
      reason: 'one finger took the page along with it',
    );
    expect(held.isEmpty, isTrue, reason: 'and cut nothing');
    expect(document.regionReads, isEmpty);
  });

  testWidgets('with the cut tool not armed the viewer stays a viewer — and '
      'arming it later reaches the open viewer', (tester) async {
    tool.value = BrushToolState.defaults;
    await pumpViewer(tester);

    await cutDrag(tester);
    expect(held.isEmpty, isTrue, reason: 'a brush in hand cuts nothing here');
    expect(document.regionReads, isEmpty);

    tool.value = cutTool();
    await tester.pump();
    await cutDrag(tester);
    expect(held.isNotEmpty, isTrue, reason: 'the armed cut reached it');
  });

  testWidgets('📨a read the viewer\'s budget cannot hold is REFUSED — never '
      'read smaller — and the refusal says so', (tester) async {
    // A "page" costs 16 bytes here, so the budget is a few dozen bytes: the
    // 1200×900 page at its own size cannot fit in it.
    ViewerRasterBudget.debugPageBytesOverride = 16;
    await pumpViewer(tester);

    await cutDrag(tester);

    expect(held.isEmpty, isTrue);
    expect(document.regionReads, isEmpty, reason: 'nothing was read at all');
    expect(cursorNotices.message, AppText.strings.mediaViewerCutTooLarge);
    // The notice's own timer, stopped before the fake clock checks it.
    cursorNotices.clear();
  });

  testWidgets('a read that lands after the document changed holds nothing '
      '— what is on screen is not what was cut', (tester) async {
    await pumpViewer(tester);
    final cutFrom = document..holdRegionReads();
    await cutDrag(tester);
    expect(cutFrom.regionReads, hasLength(1), reason: 'the read is out');

    document = FakePdfDocument(pageSizes: const [pageSize]);
    slot.open(
      const MediaViewerRequest(
        path: 'C:/work/other.pdf',
        kind: MediaAssetKind.pdf,
      ),
    );
    await tester.pumpAndSettle();
    cutFrom.releaseRegionReads();
    await tester.pump();
    await tester.pump();

    expect(held.isEmpty, isTrue);
  });

  testWidgets('the cached pages make room for the read — and the one on '
      'screen stays', (tester) async {
    document = FakePdfDocument(
      pageSizes: const [pageSize, pageSize, pageSize],
    );
    // What ONE cached page costs in this harness, measured rather than
    // worked out: the tier follows the effective ratio.
    await pumpViewer(tester);
    final page = session.renderCaches.viewerRasterBytes;
    expect(page, greaterThan(0), reason: 'fixture: a page is cached');
    await tester.pumpWidget(const SizedBox());
    // A budget that holds two cached pages, and the read beside ONE page
    // but not beside two: a page must go for the cut to happen at all.
    const read = 1200 * 900 * 4;
    final budget =
        math.max(2 * page, page + read) + math.min(page, read) ~/ 2;
    ViewerRasterBudget.debugPageBytesOverride = budget ~/ 4;
    slot.position.value = 0;
    await pumpViewer(tester);
    for (final next in [1, 2]) {
      slot.position.value = next;
      await tester.pumpAndSettle();
    }
    expect(
      session.renderCaches.viewerRasterBytes,
      2 * page,
      reason: 'fixture: two pages are cached',
    );

    await cutDrag(tester);

    expect(held.isNotEmpty, isTrue, reason: 'room was made, so the cut went');
    expect(document.regionReads.single.$1, 2, reason: 'the page on screen');
    expect(
      session.renderCaches.viewerRasterBytes,
      page,
      reason: 'the page on screen is all that is left',
    );
  });

  testWidgets('the read is billed to the viewer while it is out — the page '
      'at its own size — and the bill ends with it', (tester) async {
    await pumpViewer(tester);
    final resting = session.renderCaches.viewerRasterBytes;
    document.holdRegionReads();

    await cutDrag(tester);
    expect(document.regionReads, hasLength(1), reason: 'the read is out');
    expect(
      session.renderCaches.viewerRasterBytes,
      resting + 1200 * 900 * 4,
      reason: 'billed as the page at its own size',
    );

    document.releaseRegionReads();
    await tester.pump();
    await tester.pump();
    expect(held.isNotEmpty, isTrue);
    expect(session.renderCaches.viewerRasterBytes, resting);
  });

  testWidgets('🐛F-112: a cut after the viewer remounts is a NEW piece to its '
      'readers — the id does not start again', (tester) async {
    await pumpViewer(tester);
    await cutDrag(tester);
    final first = held.piece!.image.id;

    // The panel is taken down and put back: a new State, as closing the
    // viewer and opening it again makes one.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpViewer(tester);
    await cutDrag(tester);

    expect(
      held.piece!.image.id,
      isNot(first),
      reason: 'the stamp and the settings preview read a new id as new pixels',
    );
  });
}
