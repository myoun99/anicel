import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';

/// F-92 → I-44 — the storyboard's rows stand on the timeline's one sheet.
///
/// 유저 2026-09-12 (F-92): 「스토리보드패널의 프레임셀 그리드, 타임라인패널이랑
/// 다름 … 줌 축소해도 1f마다 블록에 세로선이있음. 타임라인이랑 다른 법 절대로
/// 두지말고 관련 로직 싹 다 통일」. F-92 made the paper spans draw the
/// timeline's law across themselves; I-44 (「블록에 존재하는 그리드선만 싹 삭제」
/// → 「합친다 — 그리드 한 장」) took every line off every block. ⇒ The frames
/// are ruled by the SAME sheet the timeline mounts, under the rows, with the
/// same cadence — one law by construction. 유저 2026-09-24 made the lines on
/// a block a switch (on by default): where it is on, the paper carries that
/// same sheet's lines, asked of the one function every block asks.
///
/// Measured on the real storyboard: an S row's sound block, painted into a
/// recording canvas, and the sheet under it.
void main() {
  const soundStart = 3;
  const soundLength = 12;

  /// The default project with one sound on the first S row, from global frame
  /// [soundStart], and the storyboard at [pixelsPerFrame]. Returns the key of
  /// that sound's paper.
  Future<(EditorSessionManager, String)> storyboardWithASound(
    WidgetTester tester, {
    required double pixelsPerFrame,
  }) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final seId = session.activeTrack.seLayers.first.id;
    session.selectLayer(seId);
    session.selectFrameIndex(soundStart);
    session.seEntries.createSeEntryAtCurrentFrame(
      name: 'a',
      lengthFrames: soundLength,
    );
    expect(
      session.activeTrack.seLayers.first.timeline[soundStart]?.length,
      soundLength,
      reason: 'fixture: the sound stands where the test reads it',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: pixelsPerFrame,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (session, 'storyboard-se-paper-${seId.value}-$soundStart');
  }

  TimelineGridSheetPainter sheetOf(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byKey(
                    const ValueKey<String>('storyboard-grid-sheet'),
                  ),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter!
          as TimelineGridSheetPainter;

  // 🗣️유저 2026-09-24: the lines on a block are a switch, on by default — so
  // the sound block carries the SAME lines the sheet rules beside it (F-92's
  // 「타임라인이랑 다른 법 절대로 두지말고」) where it is on, and I-44's bare
  // paper where it is off. Counted from where the sound stands: a span that
  // did not know its start frame would thin and weight a grid of its own.
  for (final pixelsPerFrame in [2.4, 8.0, 24.0]) {
    testWidgets('at ${pixelsPerFrame}px a frame, the sound block carries '
        'exactly the sheet\'s lines where the switch shows them, and none '
        'where it does not', (tester) async {
      addTearDown(
        () =>
            AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
      );
      for (final shown in [false, true]) {
        AppFrameGridSettings.settings.value = AppFrameGridSettings(
          blockFrameLines: shown,
        );
        final (_, key) = await storyboardWithASound(
          tester,
          pixelsPerFrame: pixelsPerFrame,
        );
        final span = find.byKey(ValueKey<String>(key));
        expect(span, findsOneWidget);
        final spy = _LineSpy();
        tester
            .widget<CustomPaint>(
              find
                  .descendant(of: span, matching: find.byType(CustomPaint))
                  .first,
            )
            .painter!
            .paint(spy, tester.getSize(span));
        final sheet = sheetOf(tester);
        final ruled = [
          for (var offset = 1; offset < soundLength; offset += 1)
            if (timelineFrameBoundaryLineInk(
                  frameIndex: soundStart + offset,
                  frameCellExtent: pixelsPerFrame,
                  framesPerSecond: sheet.framesPerSecond,
                  colorScheme: sheet.colorScheme,
                ) !=
                null)
              timelineFrameBoundaryLinePosition(offset, pixelsPerFrame),
        ];
        final centres = [for (final bar in spy.bars) bar.center.dx];
        expect(
          centres,
          hasLength(shown ? ruled.length : 0),
          reason: 'switch $shown',
        );
        for (var i = 0; i < centres.length; i += 1) {
          expect(centres[i], closeTo(ruled[i], 1e-9));
        }
        expect(spy.lines, isEmpty, reason: 'no stroke of a grid of its own');
      }
    });
  }

  testWidgets('zoomed out, the sheet keeps exactly the lines the timeline '
      'keeps, where the timeline puts them', (tester) async {
    await storyboardWithASound(tester, pixelsPerFrame: 2.4);
    final sheet = sheetOf(tester);
    expect(sheet.frameCellExtent, 2.4);

    final spy = _LineSpy();
    const size = Size(2.4 * 30, 100);
    sheet.paint(spy, size);
    final kept = [
      for (var frame = 1; frame * 2.4 <= size.width; frame += 1)
        if (timelineFrameBoundaryLineInk(
              frameIndex: frame,
              frameCellExtent: 2.4,
              framesPerSecond: sheet.framesPerSecond,
              colorScheme: sheet.colorScheme,
            ) !=
            null)
          timelineFrameBoundaryLinePosition(frame, 2.4),
    ];
    expect(kept.length, lessThan(30), reason: 'fixture: at 10% it thins');
    // The host pass runs the whole height: its lines are the ones that
    // reach the bottom of the canvas.
    final hostPass = spy.lines.where((line) => line.to == size.height);
    expect(hostPass.map((line) => line.along).toList()..sort(), kept);
  });

  testWidgets('the sheet rules the rows the rail lays out — row for row, '
      'height for height', (tester) async {
    await storyboardWithASound(tester, pixelsPerFrame: 8);
    final rows = sheetOf(tester).rows.rows;
    expect(rows, isNotEmpty);
    expect(
      rows.fold<double>(0, (extent, row) => extent + row.extent),
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('storyboard-timeline-scroll-content'),
            ),
          )
          .height,
      reason: 'the sheet reads the rail\'s own row table, so a seam cannot '
          'land between rows the strip column does not have',
    );
  });
}

class _LineSpy implements Canvas {
  final lines = <({double along, double to})>[];

  /// Filled rects — a block's frame lines are laid as boxes on its paper
  /// (the paper itself is a rounded rect).
  final bars = <Rect>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((along: p1.dx, to: p2.dy));

  @override
  void drawRect(Rect rect, Paint paint) {
    if (paint.style == PaintingStyle.fill) {
      bars.add(rect);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
