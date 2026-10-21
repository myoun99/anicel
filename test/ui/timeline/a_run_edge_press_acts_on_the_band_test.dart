import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

import 'timeline_row_chrome_probe.dart';

/// 🗣️F-410 (유저 2026-10-19): 「여러 프레임 블록(여러 행이든 뭐든)
/// 선택됬을때, 여러 레이어 선택하고 버튼 동작하는 규칙 그대로, 선택된 여러
/// 프레임에 성질 바꾸는거 적용되도록. 프레임추가도.」
///
/// A run edge's two buttons — the N/H/R tag and the ＋ — answer the rows'
/// rule in runs: pressed on a run the band holds, every run it holds on
/// every row; pressed on any other, that run alone. Measured before the
/// round (10-20): both acted on the pressed run alone, band or no band.
void main() {
  const end = TimelineRunEdgeSide.end;
  const hold = TimelineRunEdgeMode.hold;

  /// [row] holding two runs: frames 0–2 (two blocks, glued) and 5–6.
  Layer laid(Layer row) {
    FrameId id(int n) => FrameId('${row.id.value}-$n');
    return row.copyWith(
      frames: [
        for (var n = 1; n <= 3; n += 1)
          Frame(id: id(n), duration: 1, strokes: const [], name: '$n'),
      ],
      timeline: {
        0: TimelineExposure.drawing(id(1), length: 2),
        2: TimelineExposure.drawing(id(2), length: 1),
        5: TimelineExposure.drawing(id(3), length: 2),
      },
    );
  }

  /// Rows A and B of [s]'s cut, each [laid].
  (LayerId, LayerId) twoRows(EditorSessionManager s) {
    final a = s.activeLayer!.id;
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final b = s.activeLayer!.id;
    for (final id in [a, b]) {
      final row = s.layers.firstWhere((layer) => layer.id == id);
      expect(row.kind, LayerKind.animation, reason: '⛔전제');
      s.repository.replaceLayer(layer: laid(row));
    }
    return (a, b);
  }

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  Layer layerOf(EditorSessionManager s, LayerId id) =>
      s.layers.firstWhere((layer) => layer.id == id);

  /// A band over [rows], frames [from] through [to].
  void band(
    EditorSessionManager s,
    List<LayerId> rows,
    int from,
    int to,
  ) => s.updateFrameRangeSelectionDrag(
    layerId: rows.first,
    anchorIndex: from,
    headIndex: to,
    headLayerId: rows.last,
    spanRows: [for (final id in rows) LayerRowAddress(id)],
  );

  /// The end mode of each run (by its start) on [row].
  Map<int, TimelineRunEdgeMode?> endModes(EditorSessionManager s, LayerId row) {
    final layer = layerOf(s, row);
    return {
      for (final start in [0, 5])
        start: runEdgeBehaviorAt(layer, start, end)?.mode,
    };
  }

  void pressHold(EditorSessionManager s, LayerId row, int run) =>
      s.rangeMove.setRunEdgeBehavior(
        layerId: row,
        blockStartIndex: run,
        side: end,
        mode: hold,
      );

  /// Where [row]'s drawings start, ghosts left out.
  List<int> drawnStarts(Layer row) => [
    for (final MapEntry(:key, :value) in row.timeline.entries)
      if (value.isDrawing && !value.ghost) key,
  ];

  group('the tag', () {
    test('🚨pressed on a run the band holds, it sets every run the band '
        'holds on every row — one undo puts all of them back', () {
      final s = session();
      final (a, b) = twoRows(s);
      band(s, [a, b], 0, 6);

      pressHold(s, a, 0);

      expect(endModes(s, a), {0: hold, 5: hold});
      expect(endModes(s, b), {0: hold, 5: hold});
      s.undo();
      expect(endModes(s, a), {0: null, 5: null});
      expect(endModes(s, b), {0: null, 5: null});
    });

    test('pressed on a run the band does not hold, it sets that run alone', () {
      final s = session();
      final (a, b) = twoRows(s);
      band(s, [a, b], 0, 2);

      pressHold(s, a, 5);

      expect(endModes(s, a), {0: null, 5: hold});
      expect(endModes(s, b), {0: null, 5: null});
    });

    test('a band holds the runs it holds a block of — on every row it '
        'spans, and no other', () {
      final s = session();
      final (a, b) = twoRows(s);
      band(s, [a, b], 2, 2);

      pressHold(s, b, 0);

      expect(endModes(s, a), {0: hold, 5: null});
      expect(endModes(s, b), {0: hold, 5: null});
    });

    test('↩️a band over two rows scopes "Repeat selection" on the row it '
        'did not begin on too', () {
      final s = session();
      final (a, b) = twoRows(s);
      band(s, [a, b], 2, 2);

      expect(
        s.canScopeRepeatToSelection(layerId: b, blockStartIndex: 0, side: end),
        isTrue,
      );
      s.rangeMove.setRunEdgeBehavior(
        layerId: b,
        blockStartIndex: 0,
        side: end,
        mode: TimelineRunEdgeMode.repeat,
      );

      for (final row in [a, b]) {
        expect(
          runEdgeBehaviorAt(layerOf(s, row), 0, end)?.patternBlockStart,
          2,
        );
      }
    });

    test('a row whose runs take no press is passed by — a synced mirror '
        'keeps its own timeline empty', () {
      final s = session();
      final (a, _) = twoRows(s);
      s.selectLayer(a);
      s.folders.addAttachedLayer(AttachedPlacement.above);
      final mirror = s.layers.firstWhere(
        (layer) => layer.attachedToLayerId == a,
      );
      Layer stored() => layerAnywhereOrNull(
        s.repository.currentProject!,
        mirror.id,
      )!;
      expect(stored().timeline, isEmpty, reason: '⛔전제: it mirrors A');
      band(s, [a, mirror.id], 0, 6);

      pressHold(s, a, 0);

      expect(endModes(s, a), {0: hold, 5: hold});
      expect(stored().timeline, isEmpty);
    });
  });

  group('the ＋', () {
    test('🚨dragged on a run the band holds, it adds to every run the band '
        'holds on every row — previewed together, one undo', () {
      final s = session();
      final (a, b) = twoRows(s);
      band(s, [a, b], 0, 2);

      expect(
        s.runFramesAdd.beginRunFramesAddDrag(
          layerId: a,
          blockStartIndex: 0,
          atEnd: true,
        ),
        isTrue,
      );
      s.runFramesAdd.updateRunFramesAddDrag(2);
      for (final row in [a, b]) {
        final shown = timelineDragPreviewLayerFor(s.dragPreview.value, row);
        expect(drawnStarts(shown!), [0, 2, 3, 4, 5]);
      }
      s.runFramesAdd.endRunFramesAddDrag();

      for (final row in [a, b]) {
        expect(drawnStarts(layerOf(s, row)), [0, 2, 3, 4, 5]);
      }
      s.undo();
      for (final row in [a, b]) {
        expect(drawnStarts(layerOf(s, row)), [0, 2, 5]);
      }
    });

    test('two runs on one row take theirs from the right, so the left one\'s '
        'push carries the right one\'s new frames along', () {
      final s = session();
      final (a, _) = twoRows(s);
      band(s, [a], 0, 6);

      s.runFramesAdd.beginRunFramesAddDrag(
        layerId: a,
        blockStartIndex: 0,
        atEnd: true,
      );
      s.runFramesAdd.updateRunFramesAddDrag(3);
      s.runFramesAdd.endRunFramesAddDrag();

      // 0–2, three new, the 5 run pushed one on (the gap took two), three new.
      final row = layerOf(s, a);
      expect(drawnStarts(row), [0, 2, 3, 4, 5, 6, 8, 9, 10]);
      expect(
        {for (final start in [3, 4, 5, 8, 9, 10]) row.timeline[start]!.frameId},
        hasLength(6),
        reason: 'each run takes drawings of its own, not the other\'s',
      );
      expect({for (final frame in row.frames) frame.id}, hasLength(3 + 6));
    });

    test('dragged on a run the band does not hold, it adds to that run '
        'alone', () {
      final s = session();
      final (a, b) = twoRows(s);
      band(s, [a, b], 0, 2);

      s.runFramesAdd.beginRunFramesAddDrag(
        layerId: b,
        blockStartIndex: 5,
        atEnd: true,
      );
      s.runFramesAdd.updateRunFramesAddDrag(1);
      s.runFramesAdd.endRunFramesAddDrag();

      expect(drawnStarts(layerOf(s, a)), [0, 2, 5]);
      expect(drawnStarts(layerOf(s, b)), [0, 2, 5, 7]);
    });

    test('a row that refuses holds and repeats is passed by — its blocks '
        'move, but the conte row shows no run edge to add at', () {
      final s = session();
      final (a, _) = twoRows(s);
      s.layerStack.addLayerOfKind(LayerKind.storyboard);
      final conte = s.activeLayer!;
      expect(
        (conte.kind.acceptsRepeatRegions, s.blockMoveEligible(conte.id)),
        (false, true),
        reason: '⛔전제: only the kind\'s refusal passes it by',
      );
      s.repository.replaceLayer(layer: laid(conte));
      band(s, [a, conte.id], 0, 2);

      s.runFramesAdd.beginRunFramesAddDrag(
        layerId: a,
        blockStartIndex: 0,
        atEnd: true,
      );
      s.runFramesAdd.updateRunFramesAddDrag(2);
      s.runFramesAdd.endRunFramesAddDrag();

      expect(drawnStarts(layerOf(s, a)), [0, 2, 3, 4, 5]);
      expect(drawnStarts(layerOf(s, conte.id)), [0, 2, 5]);
    });
  });

  testWidgets('🚨the tag pressed on the timeline keeps the band it is pressed '
      'inside, and Hold lands on every run of it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: createDefaultProject()),
      ),
    );
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final (a, b) = twoRows(s);
    await tester.pumpAndSettle();
    band(s, [a, b], 0, 6);
    await tester.pumpAndSettle();

    final press = await tester.startGesture(
      timelineRowChromeCenter(
        tester,
        a.value,
        'run-edge-tag-${a.value}-0-end',
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('run-edge-mode-hold')));
    await tester.pumpAndSettle();

    expect(endModes(s, a), {0: hold, 5: hold});
    expect(endModes(s, b), {0: hold, 5: hold});
  });
}
