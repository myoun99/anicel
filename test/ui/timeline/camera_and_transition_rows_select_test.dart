import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/timeline_host.dart';
import 'timeline_cell_probe.dart';

/// F-16 — **the camera and transition rows select like every other row.**
///
/// 유저: 「카메라·트랜지션 레이어도 선택범위는 작동해야 한다 — 막으라고 한
/// 것은 드래그 이동뿐이었다」. Selecting is READING. The read-only rule bites
/// on the verbs that CHANGE a row, and those rows already mount no move half;
/// stopping the band from being drawn on them is a second rule nobody asked
/// for, over the top of the one that was asked for.
///
/// ⚠️Driven through REAL input on the real rail, not through the session's
/// entry point. The session-level path was never the thing in doubt — the
/// question is whether a drag on these two rows reaches it at all.
void main() {
  // The timeline tab alone ([pumpTimelineHost]), as the app's window of
  // 1400 × 900 laid it — the rail is the panel's.
  Future<EditorSessionManager> pumpWorkspace(WidgetTester tester) =>
      pumpTimelineHost(
        tester,
        createDefaultProject(),
        surface: const Size(870, 396),
      );

  Layer layerOfKind(EditorSessionManager session, LayerKind kind) =>
      session.layers.firstWhere((layer) => layer.kind == kind);

  Future<void> dragAcrossCells(
    WidgetTester tester,
    String layerId, {
    int from = 1,
    int to = 3,
    String prefix = 'timeline',
  }) async {
    final start = timelineCellCenter(tester, layerId, from, prefix: prefix);
    final end = timelineCellCenter(tester, layerId, to, prefix: prefix);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(end);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  // F-556's law over a row that holds no cels: a band names a drawing it
  // holds, read off the rows a copy takes. ↩️It read every row the band
  // named, and the transition row is none the cut's timeline holds — the
  // sweep threw (2026-11-04).
  for (final kind in [LayerKind.camera, LayerKind.transition]) {
    testWidgets('a band swept from a drawing\'s row onto the ${kind.name} '
        'row names the drawing, stood on either', (tester) async {
      final session = await pumpWorkspace(tester);
      final drawing = session.activeLayer!;
      session.createDrawingAtCurrentFrame();
      await tester.pumpAndSettle();
      final other = layerOfKind(session, kind);

      final gesture = await tester.startGesture(
        timelineCellCenter(tester, drawing.id.value, 3),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(timelineCellCenter(tester, other.id.value, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final band = session.frameRangeSelection.value!;
      expect(
        [band.coversLayer(drawing.id), band.coversLayer(other.id)],
        [true, true],
        reason: '⛔전제',
      );
      expect(session.clipboard.canCopyFrameAtCurrentFrame, isTrue);

      session.selectLayer(other.id);
      expect(
        session.clipboard.canCopyFrameAtCurrentFrame,
        isFalse,
        reason: 'a row that holds no cels is no place (F-281)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a band over an empty run of a drawing\'s row and the '
        '${kind.name} row names nothing, and sweeps', (tester) async {
      final session = await pumpWorkspace(tester);
      final drawing = session.activeLayer!;
      expect(drawing.timeline, isEmpty, reason: '⛔전제: nothing to name');
      final other = layerOfKind(session, kind);

      final gesture = await tester.startGesture(
        timelineCellCenter(tester, drawing.id.value, 3),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(timelineCellCenter(tester, other.id.value, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        session.frameRangeSelection.value!.coversLayer(other.id),
        isTrue,
        reason: '⛔전제',
      );
      expect(session.activeLayerId, drawing.id, reason: '⛔전제');
      expect(session.clipboard.canCopyFrameAtCurrentFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final kind in [LayerKind.camera, LayerKind.transition]) {
    testWidgets('a drag across the ${kind.name} row draws a band', (
      tester,
    ) async {
      final session = await pumpWorkspace(tester);
      final layer = layerOfKind(session, kind);

      await dragAcrossCells(tester, layer.id.value);

      final selection = session.frameRangeSelection.value;
      expect(
        selection,
        isNotNull,
        reason: 'selecting is reading — the ${kind.name} row is a row',
      );
      expect(selection!.coversLayer(layer.id), isTrue);
      expect(selection.contains(2), isTrue);
    });

    testWidgets('and the X-sheet says the same about the ${kind.name} row', (
      tester,
    ) async {
      final session = await pumpWorkspace(tester);
      final layer = layerOfKind(session, kind);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-orientation-toggle-button'),
        ),
      );
      await tester.pumpAndSettle();

      await dragAcrossCells(tester, layer.id.value, prefix: 'xsheet');

      final selection = session.frameRangeSelection.value;
      expect(selection, isNotNull);
      expect(selection!.coversLayer(layer.id), isTrue);
      expect(selection.contains(2), isTrue);
    });
  }
}
