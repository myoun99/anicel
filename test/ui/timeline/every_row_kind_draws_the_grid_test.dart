import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show
        TimelineGridSheetPainter,
        timelineFrameBoundaryLineInk,
        timelineRowPaperExtent;
import 'package:anicel/src/ui/timeline/timeline_grid_sheet.dart';

import 'timeline_cell_probe.dart';

/// F-3, second half — **the frame grid is the sheet's ruling, and every row
/// stands on the same frames.**
///
/// 유저: 「프레임 그리드가 아예 안 그려지는 레이어가 있다(확인된 것 = 이미지
/// 레이어). 전 종류 전수조사」.
///
/// ⚠️A survey, not a spot check. The camera row was excluded from this same
/// line once (D43-2 재개 b) and the exclusion survived because every test that
/// looked at the grid built a DRAWING row. So this walks
/// [LayerKind.values] — a kind added later joins the survey by existing.
void main() {
  const trackId = TrackId('grid-track');
  const cutId = CutId('grid-cut');

  /// One row per kind, each carrying a block over frames [1,5) so the
  /// INTERIOR boundaries (2, 3, 4) exist to be ruled.
  Layer layerOfKind(LayerKind kind) => Layer(
    id: LayerId('grid-${kind.name}'),
    name: kind.name,
    kind: kind,
    frames: [
      Frame(
        id: FrameId('grid-frame-${kind.name}'),
        duration: 4,
        strokes: const [],
      ),
    ],
    timeline: {
      1: TimelineExposure.drawing(
        FrameId('grid-frame-${kind.name}'),
        length: 4,
      ),
    },
  );

  Project project() => Project(
    id: const ProjectId('grid-project'),
    name: 'Grid',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: trackId,
        name: 'V',
        cuts: [
          Cut(
            id: cutId,
            name: '1',
            duration: 12,
            canvasSize: const CanvasSize(width: 64, height: 64),
            layers: [
              for (final kind in LayerKind.values)
                if (kind != LayerKind.se) layerOfKind(kind),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> pumpWorkspace(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every row kind stands on the one sheet, ruled with the rest', (
    tester,
  ) async {
    await pumpWorkspace(tester);

    // I-44: the frame lines and the row seams are the grid sheet's — drawn
    // once, across every row it is handed. So the survey asks the sheet
    // whether each kind's row is among them.
    final sheet = tester.widget<TimelineRowsGridSheet>(
      find.byKey(const ValueKey<String>('timeline-grid-sheet')),
    );
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byWidget(sheet),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TimelineGridSheetPainter;
    final ids = {for (final row in sheet.rows) row.layer.id.value};
    final missing = [
      for (final kind in LayerKind.values)
        if (kind != LayerKind.se && !ids.contains('grid-${kind.name}'))
          kind.name,
    ];

    expect(
      missing,
      isEmpty,
      reason: 'the grid is the sheet ruling — a row opting out of it is a '
          'row claiming its columns sit somewhere else',
    );
    expect(
      painter.rows.rows,
      hasLength(sheet.rows.length),
      reason: 'every row the sheet is handed gets its band and its seam',
    );
  });

  // 「블록에 존재하는 그리드선만 싹 삭제」(I-44) is the switch's OFF now
  // (유저 2026-09-24: 「블록 세로선 역시 있는것도 좋아서 환경설정에 옵션으로
  // 두고싶어. 기본값은 있음으로」) — and the survey holds in both positions:
  // off, every kind lays paper and nothing else; on, every kind that lays
  // paper over its block carries the sheet's own lines at the block's inner
  // boundaries. A kind that opted out of either is the F-3 shape again.
  testWidgets('no row kind draws a line of its own: off, only its paper; on, '
      'the sheet\'s own lines on it — every kind alike, flipped live', (
    tester,
  ) async {
    addTearDown(
      () => AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
    );
    AppFrameGridSettings.settings.value = const AppFrameGridSettings(
      blockFrameLines: false,
    );
    await pumpWorkspace(tester);

    for (final shown in [false, true]) {
      if (shown) {
        // Flipped under a running grid: the host's law carries the switch
        // to every row without a rebuild of the workspace.
        AppFrameGridSettings.settings.value = const AppFrameGridSettings();
        await tester.pumpAndSettle();
      }
      final strays = <String>[];
      final unruled = <String>[];
      var papered = 0;
      for (final kind in LayerKind.values) {
        if (kind == LayerKind.se) {
          continue;
        }
        final id = 'grid-${kind.name}';
        if (find
            .byKey(ValueKey<String>('timeline-row-cells-$id'))
            .evaluate()
            .isEmpty) {
          continue;
        }
        final painter = timelineRowCellsPainterFor(tester, id);
        expect(
          painter.blockFrameLines,
          shown,
          reason: '${kind.name}: the law reaches every row',
        );
        final window = painter.visibleFrameWindow();
        final substrate = painter.substrateIn(
          window.startIndex,
          window.endIndexExclusive,
        );
        final spy = _BoxSpy();
        painter.paint(spy, const Size(2000, 28));
        // The row paints span by span (its tiles, or their classic stand-in
        // while they land), so its paper arrives cut at the span edges — the
        // lines are what must come out exactly: the substrate's, and none
        // of the kind's own. A box thinner than a cell is a line.
        final lines = {
          for (final box in spy.boxes)
            if (box.width < painter.frameCellExtent) box,
        };
        if (lines.difference({
          for (final line in substrate.lines) line.rect,
        }).isNotEmpty) {
          strays.add(kind.name);
        }
        // And not one box reaches the row's last pixel: that is the sheet's
        // seam, under the row.
        final paperExtent = timelineRowPaperExtent(painter.crossAxisExtent);
        if (spy.boxes.any((box) => box.bottom > paperExtent)) {
          strays.add('${kind.name} (seam)');
        }
        if (painter.resolvedCellStyleFor(2).background.a == 0) {
          continue;
        }
        papered += 1;
        // Wherever the kind lays its paper on without a corner between two
        // cells — its block's inside, however long the kind makes it (the
        // conte row fills the cut) — the sheet's line at that boundary.
        final ruled = [
          for (
            var frame = window.startIndex + 1;
            frame <= window.endIndexExclusive;
            frame += 1
          )
            if (painter.resolvedCellStyleFor(frame - 1).background.a > 0 &&
                painter.resolvedCellStyleFor(frame).background.a > 0 &&
                (painter.resolvedCellStyleFor(frame).radius?.topLeft ??
                        Radius.zero) ==
                    Radius.zero &&
                timelineFrameBoundaryLineInk(
                      frameIndex: frame,
                      frameCellExtent: painter.frameCellExtent,
                      framesPerSecond: painter.framesPerSecond,
                      colorScheme: painter.colorScheme,
                    ) !=
                    null)
              frame,
        ];
        if (substrate.lines.length != (shown ? ruled.length : 0) ||
            lines.length != substrate.lines.length) {
          unruled.add(kind.name);
        }
      }
      expect(strays, isEmpty, reason: 'switch $shown');
      expect(unruled, isEmpty, reason: 'switch $shown');
      expect(papered, greaterThan(1), reason: 'fixture premise: blocks');
    }
  });
}

/// Every filled box a painter asks for — rects and rounded rects alike.
class _BoxSpy implements Canvas {
  final boxes = <Rect>[];

  @override
  void drawRect(Rect rect, Paint paint) => boxes.add(rect);

  @override
  void drawRRect(RRect rrect, Paint paint) => boxes.add(rrect.outerRect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
