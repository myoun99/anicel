@Tags(['benchmark'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show debugOnProfilePaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// MEASUREMENT for the solo stutter (I-19 ③, 유저 2026-09-13: 「활성레이어
/// 솔로 단축키 누르면 버벅임있는데 … 쓸데없이 비효율적인 요소가 있는게
/// 아닌가?」).
///
/// ONE frame of the whole app after an ordinary notify (picking a row), a
/// solo coming on and a solo going off, every row holding ink — and for each
/// frame, what it did: elements rebuilt and render objects painted, by type.
///
/// 🧪What it said on 2026-09-23 (24 rows, test VM): pick 260ms · solo on
/// 132ms · solo off 331ms; solo rebuilt 3,051 elements to the pick's 633.
/// The two solo frames rebuild and paint EXACTLY as much, and the one that
/// shows 23 rows again costs 200ms more — so the body of the stutter is the
/// canvas taking the rows back, not the widgets (brush-render-roadmap). The
/// rebuild is the smaller, second half (an-eye-rebuilds-its-whole-row).
///
/// Prints; asserts only that the work happened. Benchmarks run alone and
/// only the A/B ratio is trusted.
void main() {
  Future<EditorSessionManager> inkedApp(WidgetTester tester, int rows) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    while (session.layers.length < rows) {
      session.layerStack.addLayer();
    }
    await tester.pumpAndSettle();
    for (final layer in session.layers.toList()) {
      session.selectLayer(layer.id);
      if (session.frameVerbs.canCreateDrawingAtCurrentFrame) {
        session.createDrawingAtCurrentFrame();
      }
      await tester.pumpAndSettle();
      final rect = tester.getRect(mainCanvasView());
      final gesture = await tester.startGesture(
        rect.center,
        kind: PointerDeviceKind.stylus,
      );
      for (var move = 0; move < 6; move += 1) {
        await gesture.moveBy(const Offset(9, 5));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }
    return session;
  }

  /// One frame after [act]: its wall time, and what it rebuilt and painted.
  Future<({double ms, Map<String, int> built, Map<String, int> painted})>
  frameOf(WidgetTester tester, void Function() act) async {
    final built = <String, int>{};
    final painted = <String, int>{};
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final name = element.widget.runtimeType.toString();
      built[name] = (built[name] ?? 0) + 1;
    };
    debugOnProfilePaint = (renderObject) {
      final name = renderObject.runtimeType.toString();
      painted[name] = (painted[name] ?? 0) + 1;
    };
    act();
    final watch = Stopwatch()..start();
    await tester.pump();
    watch.stop();
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
    await tester.pumpAndSettle();
    return (
      ms: watch.elapsedMicroseconds / 1000,
      built: built,
      painted: painted,
    );
  }

  int total(Map<String, int> counts) => counts.values.fold(0, (a, b) => a + b);

  String top(Map<String, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(8)) '${e.key}=${e.value}'].join(' ');
  }

  for (final rows in [8, 24]) {
    testWidgets('a solo frame against a pick, $rows inked rows', (
      tester,
    ) async {
      final session = await inkedApp(tester, rows);
      final ids = session.layers.map((layer) => layer.id).toList();
      session.selectLayer(ids[1]);
      await tester.pumpAndSettle();

      final pick = await frameOf(tester, () => session.selectLayer(ids[2]));
      final soloOn = await frameOf(
        tester,
        session.visibilitySolo.toggleLayerVisibilitySolo,
      );
      final soloOff = await frameOf(
        tester,
        session.visibilitySolo.toggleLayerVisibilitySolo,
      );

      for (final (name, frame) in [
        ('pick', pick),
        ('solo on', soloOn),
        ('solo off', soloOff),
      ]) {
        // ignore: avoid_print
        print(
          '[solo-frame] rows=$rows $name ${frame.ms.toStringAsFixed(1)}ms '
          'built=${total(frame.built)} painted=${total(frame.painted)}\n'
          '  built: ${top(frame.built)}',
        );
      }
      expect(total(soloOn.built), greaterThan(0), reason: 'the solo rebuilt');
      expect(session.layers.length, rows, reason: 'fixture');
    });
  }
}
