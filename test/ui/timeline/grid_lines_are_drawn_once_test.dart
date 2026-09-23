import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'timeline_cell_probe.dart';

/// F-3, F-7 and I-44 — **one boundary, one line, one colour.**
///
/// F-7 (유저 2026-08-24): 「fx열면 프레임영역의 선이 두꺼운데 선이
/// 이중적용되고있는건가?」 — two drawers on one boundary. F-3 (08-25):
/// 「가로선만 레이어영역 흰색계열로 통일」 — the row seam is the layer area's
/// divider, flat, not a frame line taking the ground. I-44 (09-23/24):
/// 「가로선이랑 세로선이 2개 중복해서있고 … 하나로 못합치나?」 → one sheet.
///
/// These ask the RUNNING grid, not a painter built by hand: "the law file is
/// green and the panel is broken" was D43-2's whole shape.
void main() {
  const drawingId = LayerId('grid-once-draw');

  Project project() => Project(
    id: const ProjectId('grid-once'),
    name: 'Grid once',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: const TrackId('grid-once-track'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: '1',
            duration: 12,
            canvasSize: const CanvasSize(width: 64, height: 64),
            layers: [
              Layer(
                id: drawingId,
                name: 'A',
                frames: [
                  Frame(
                    id: const FrameId('cel'),
                    duration: 4,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  1: TimelineExposure.drawing(FrameId('cel'), length: 4),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
  }

  Finder sheetsIn(Finder area) => find.descendant(
    of: area,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is TimelineGridSheetPainter,
    ),
  );

  testWidgets('the timeline draws its grid ONCE — one sheet, under the rows', (
    tester,
  ) async {
    await pump(tester);
    expect(
      sheetsIn(
        find.byKey(const ValueKey<String>('timeline-frame-grid-area')),
      ),
      findsOneWidget,
      reason: 'the overlay, every row\'s redraw, every block\'s seams and '
          'every fx band\'s own grid are ONE sheet now',
    );
  });

  testWidgets('F-3: the row seam runs flat across block and empty space '
      'alike — one rect, the rail\'s ink', (tester) async {
    await pump(tester);

    final sheet =
        tester
                .widget<CustomPaint>(
                  sheetsIn(
                    find.byKey(
                      const ValueKey<String>('timeline-frame-grid-area'),
                    ),
                  ),
                )
                .painter!
            as TimelineGridSheetPainter;
    final spy = _FillSpy();
    const size = Size(600, 200);
    sheet.paint(spy, size);

    // The drawing row's paper spans frames 1..4 and 5.. is empty: one seam
    // rect runs the whole width under both, in the rail's flat ink.
    final seamInk = timelineGridRowSeamInk(sheet.colorScheme).color;
    final seams = spy.fills
        .where((fill) => fill.color.toARGB32() == seamInk.toARGB32())
        .toList();
    expect(seams, isNotEmpty);
    for (final seam in seams) {
      expect(seam.rect.left, 0);
      expect(seam.rect.right, size.width);
    }

    // And the row itself rules nothing: its painter fills paper boxes only.
    final row = timelineRowCellsPainterFor(tester, drawingId.value);
    final rowSpy = _FillSpy();
    row.paint(rowSpy, const Size(600, 28));
    final window = row.visibleFrameWindow();
    final papers = {
      for (
        var frame = window.startIndex;
        frame < window.endIndexExclusive;
        frame += 1
      )
        row.paperRectFor(frame),
    };
    expect(rowSpy.fills, isNotEmpty, reason: 'fixture premise: a block');
    expect(
      rowSpy.fills.every((fill) => papers.contains(fill.rect)),
      isTrue,
      reason: 'a seam or a frame line would be a box of its own',
    );
  });
}

/// Every filled box a painter asks for, with its colour.
class _FillSpy implements Canvas {
  final fills = <({Rect rect, Color color})>[];

  @override
  void drawRect(Rect rect, Paint paint) =>
      fills.add((rect: rect, color: paint.color));

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      fills.add((rect: rrect.outerRect, color: paint.color));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
