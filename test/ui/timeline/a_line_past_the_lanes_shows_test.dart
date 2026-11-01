import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/line_on_screen.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🔬서피스 검증 (2026-11-01): 맨 아래 A 의 레인을 펼치고 위의 B 를 끌어
/// 내리면 레인 위 · 밑 어디서도 가로선이 없다. 착지는 맞다.
///
/// The line stood where it should, so `a_row_draws_its_lines_past_the_lanes_
/// it_owns_test` passed the whole time. These read the pixels.
void main() {
  const a = LayerId('a');

  Project film([List<Layer>? layers]) => Project(
    id: const ProjectId('line'),
    name: 'Line',
    createdAt: DateTime.utc(2026, 11, 1),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers:
                layers ??
                [
                  Layer(id: a, name: 'a', frames: const []),
                  Layer(id: const LayerId('b'), name: 'b', frames: const []),
                ],
          ),
        ],
      ),
    ],
  );

  /// Carries row [id] by [step]s from its name until [until] stands, and
  /// hands back the pointer that holds it.
  Future<TestGesture> carry(
    WidgetTester tester,
    String id,
    Finder until,
    double step,
  ) async {
    final name = tester.getCenter(find.named('timeline-layer-name-$id'));
    // The first drag selects the row; a drag inside the selection carries it.
    await tester.dragFrom(name, const Offset(30, 0));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      name,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    var at = name;
    for (var move = 0; move < 200 && until.evaluate().isEmpty; move += 1) {
      at = at + Offset(0, step);
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(until, findsOneWidget, reason: '⛔전제');
    return gesture;
  }

  Finder lineOf(String line) =>
      find.byKey(ValueKey<String>('timeline-row-caret-$line'));

  /// What the screen shows of [line] as a carry of row [id] draws it.
  Future<double> carried(
    WidgetTester tester,
    String id,
    String line,
    double step,
  ) async {
    final gesture = await carry(tester, id, lineOf(line), step);
    final shown = await lineOnScreen(tester, lineOf(line));
    await gesture.up();
    await tester.pumpAndSettle();
    return shown;
  }

  Future<EditorSessionManager> open(WidgetTester tester) async {
    final session = await pumpTimelineHost(
      tester,
      film(),
      surface: const Size(1400, 900),
    );
    session.layerSwitches.toggleLayerLanes(a);
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('the line past the last row\'s lanes reaches the screen', (
    tester,
  ) async {
    await open(tester);

    final shown = await carried(tester, 'b', 'after-a', 8);

    expect(shown, greaterThan(0.5));
  });

  testWidgets('a row gone from the rail draws no line of its own', (
    tester,
  ) async {
    final session = await open(tester);
    session.selectLayer(a);
    session.layerVerbs.deleteActiveLayer();
    await tester.pumpAndSettle();
    expect(find.named('timeline-layer-name-a'), findsNothing, reason: '⛔전제');
    session.undo();
    await tester.pumpAndSettle();

    final shown = await carried(tester, 'b', 'after-a', 8);

    expect(shown, greaterThan(0.5));
  });

  testWidgets('⛔a row that takes the drop in draws no line past it', (
    tester,
  ) async {
    await pumpTimelineHost(
      tester,
      film([
        createFolderLayer(id: const LayerId('f'), name: 'f'),
        Layer(id: const LayerId('b'), name: 'b', frames: const []),
      ]),
      surface: const Size(1400, 900),
    );

    final swallow = find.byKey(
      const ValueKey<String>('timeline-row-swallow-f'),
    );
    final gesture = await carry(tester, 'b', swallow, 2);

    // All through the band that takes it in, the nearer gap and all.
    for (var move = 0; swallow.evaluate().isNotEmpty; move += 1) {
      expect(lineOf('after-f'), findsNothing, reason: 'move $move');
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('CONTROL: the screen shows the line before a row', (
    tester,
  ) async {
    await open(tester);

    final shown = await carried(tester, 'a', 'before-b', -8);

    expect(shown, greaterThan(0.5));
  });
}
