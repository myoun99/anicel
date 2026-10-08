import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_painter.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// 🚨EACH SHEET PANEL STANDS ON ITS PAPER (F-294, 유저 2026-10-05:
/// 「타임시트 용지패널 용지크기 너무 작음. … 1754x2480을 기본으로 할것.
/// 콘티패널이랑 컷봉투패널의 용지는 300dpi인 2480x3508으로함」 · 「컷봉투
/// 가로a4 수용할게」).
///
/// Read off the canvas panel each host mounts — the pixels the panel shows,
/// zooms by and stops its view at. The layouts' own arithmetic is pinned
/// beside them; what only a mounted host can get wrong is handing the panel
/// the sheet's units for pixels, which is what every one of them did.
void main() {
  BrushCanvasPanel shellOf(WidgetTester tester) =>
      tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel));

  Future<EditorSessionManager> pump(
    WidgetTester tester,
    Project project,
    Widget Function(EditorSessionManager session) host,
  ) async {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: host(session))),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Widget timesheet(EditorSessionManager session) => TimesheetTabHost(
    session: session,
  );

  /// The default project, its one cut [frames] long and its canvas [canvas].
  Project projectOf({int? frames, CanvasSize? canvas}) {
    final project = createDefaultProject();
    final track = project.tracks.first;
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            track.cuts.first.copyWith(
              duration: frames,
              canvasSize: canvas,
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('the timesheet: every sheet of its book is 1754×2480 pixels, '
      'and the view stops at that paper', (tester) async {
    // 150 frames at 24fps on 6-second pages: two sheets.
    await pump(tester, projectOf(frames: 150), timesheet);

    final shell = shellOf(tester);
    final book = shell.book!.pages;
    expect(book.length, 2, reason: 'fixture: two sheets');
    for (var page = 0; page < 2; page += 1) {
      expect(book.pageRect(page).width, closeTo(1754, 1e-6), reason: '$page');
      expect(book.pageRect(page).height, closeTo(2480, 1e-6), reason: '$page');
    }
    final paper = shell.viewLimit!;
    expect(paper.width, closeTo(1754, 1e-6));
    expect(paper.top, closeTo(book.pageRect(0).top, 1e-6));
    expect(paper.bottom, closeTo(book.pageRect(1).bottom, 1e-6));
    // The canvas holds the paper and the desk round it.
    expect(shell.canvasSize.width, (paper.right + paper.left).ceil());
    expect(shell.canvasSize.height, (paper.bottom + paper.top).ceil());
  });

  testWidgets('the timesheet with no cut under the playhead: the stage is '
      'its paper, bare', (tester) async {
    final session = await pump(tester, projectOf(), timesheet);
    session.cutVerbs.createCut();
    final track = session.repository.requireProject().tracks.first;
    session.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    session.selectCut(track.cuts[0].id);
    session.selectGlobalFrame(track.cuts[0].duration + 1);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('timesheet-empty-no-cut')),
      findsOneWidget,
      reason: 'fixture: the gap panel is up',
    );

    expect(
      shellOf(tester).canvasSize,
      const CanvasSize(width: 1754, height: 2480),
    );
  });

  testWidgets('the conte: every page of its book is 2480 pixels across and '
      '3508 down, and the view stops at that paper', (tester) async {
    await pump(
      tester,
      projectOf(),
      (session) => ConteTabHost(session: session, thumbnails: null),
    );

    final shell = shellOf(tester);
    final book = shell.book!.pages;
    expect(book.length, greaterThan(0), reason: 'fixture: a book');
    for (var page = 0; page < book.length; page += 1) {
      expect(book.pageRect(page).width, closeTo(2480, 1e-6), reason: '$page');
      // A4 in points is 841.89 tall: its own rounding, under a pixel.
      expect(book.pageRect(page).height, closeTo(3508, 1), reason: '$page');
    }
    expect(shell.viewLimit!.width, closeTo(2480, 1e-6));
    expect(shell.unframedFit!.width, closeTo(2480, 1e-6));
  });

  test('the conte keeps a cell\'s handwriting at its paper\'s pixels: the '
      'page body, 2231×3058 of them', () {
    const metrics = ConteSheetMetrics();
    expect(metrics.paperScale, 2480 / 595.28);
    final ink = ConteInkController();
    addTearDown(ink.dispose);

    ink.syncGeometry(metrics);

    expect(
      ink.rowSurfaceSize,
      CanvasSize(
        width: (metrics.bodyWidth * metrics.paperScale).ceil(),
        height: (metrics.bodyHeight * metrics.paperScale).ceil(),
      ),
    );
    expect(ink.rowSurfaceSize, const CanvasSize(width: 2231, height: 3058));
  });

  for (final canvas in const [
    CanvasSize(width: 1920, height: 1080),
    CanvasSize(width: 900, height: 1600),
  ]) {
    testWidgets('the envelope: A4 on its side at 300dpi — 3508×2480 — '
        'whatever canvas its cut has (${canvas.width}×${canvas.height})', (
      tester,
    ) async {
      await pump(
        tester,
        projectOf(canvas: canvas),
        (session) => CutEnvelopeTabHost(session: session),
      );

      final shell = shellOf(tester);
      expect(shell.canvasSize, const CanvasSize(width: 3508, height: 2480));
      expect(shell.viewLimit, const Rect.fromLTWH(0, 0, 3508, 2480));
      expect(shell.fitFocusRect, const Rect.fromLTWH(0, 0, 3508, 2480));

      // The form is ruled onto that paper — the analog form fills its
      // height and stands centred across it.
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<CutEnvelopePainter>()
          .first;
      final layout = painter.layout;
      expect(layout.form.id, CutEnvelopePresets.analogId, reason: 'fixture');
      expect(layout.paperWidth, 3508);
      expect(layout.paperHeight, 2480);
      expect(layout.formHeight, 2480);
      expect(layout.formWidth, closeTo(3293.4, 0.1));
      expect(layout.formX, closeTo(107.3, 0.1));
    });
  }
}
