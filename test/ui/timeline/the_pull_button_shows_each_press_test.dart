import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

/// 🚨F-264 ② (유저 2026-10-08): 「당기기 버튼 한번더 눌러도 타임라인
/// 변화없음. 그상태에서 다른레이어로 서있는곳 이동하면 … 이동됨. 바로
/// 바껴야하는데」 — every press of the pull button shows on the rows it
/// moved, as it lands, with a band over several rows standing.
void main() {
  testWidgets('a band over two rows: each press of Pull is drawn on both '
      'rows at once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final s = tester.widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    LayerId rowWithBlocks() {
      final row = s.activeLayer!.id;
      for (final frame in [0, 4, 8]) {
        s.selectFrameIndex(frame);
        s.createDrawingAtCurrentFrame();
      }
      return row;
    }

    final lower = rowWithBlocks();
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final upper = rowWithBlocks();
    s.updateFrameRangeSelectionDrag(
      layerId: lower,
      anchorIndex: 4,
      headIndex: 4,
      headLayerId: upper,
    );
    await tester.pumpAndSettle();

    for (var press = 0; press < 2; press += 1) {
      final before = {
        for (final row in [lower, upper]) row: _startsOn(s, row),
      };
      await tester.tap(
        find.byKey(const ValueKey<String>('pull-blocks-button')),
      );
      await tester.pumpAndSettle();
      for (final row in [lower, upper]) {
        expect(
          _startsOn(s, row),
          isNot(before[row]),
          reason: '⛔전제: press ${press + 1} moved it',
        );
        expect(
          _drawnStartsOn(tester, row),
          _startsOn(s, row),
          reason: 'the row draws press ${press + 1} as it lands',
        );
      }
    }
  });
}

List<int> _startsOn(EditorSessionManager s, LayerId row) => [
  for (final entry in s.layers.firstWhere((l) => l.id == row).timeline.entries)
    if (!entry.value.ghost) entry.key,
];

/// The blocks [row]'s cells are painted with — what the timeline shows.
List<int> _drawnStartsOn(WidgetTester tester, LayerId row) {
  final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
  final painters = [
    for (final paint in paints)
      if (paint.painter case final TimelineRowCellsPainter painter
          when painter.layer.id == row)
        painter,
  ];
  expect(painters, isNotEmpty, reason: '⛔전제: the row is drawn');
  return {
    for (final painter in painters)
      [
        for (final entry in painter.layer.timeline.entries)
          if (!entry.value.ghost) entry.key,
      ].join(','),
  }.single.split(',').map(int.parse).toList();
}
