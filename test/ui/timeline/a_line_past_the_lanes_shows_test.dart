import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
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

  Project film() => Project(
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
            layers: [
              Layer(id: a, name: 'a', frames: const []),
              Layer(id: const LayerId('b'), name: 'b', frames: const []),
              Layer(id: const LayerId('c'), name: 'c', frames: const []),
            ],
          ),
        ],
      ),
    ],
  );

  /// Carries row [id] by [step]s from its name until [line] stands, and hands
  /// back what the screen shows of it.
  Future<double> carried(
    WidgetTester tester,
    String id,
    String line,
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
    final caret = find.byKey(ValueKey<String>('timeline-row-caret-$line'));
    var at = name;
    for (var move = 0; move < 200 && caret.evaluate().isEmpty; move += 1) {
      at = at + Offset(0, step);
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(caret, findsOneWidget, reason: '⛔전제: the row draws its line');
    final shown = await lineOnScreen(tester, caret);
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

  testWidgets('a row gone from the rail is not asked for a line', (
    tester,
  ) async {
    final session = await open(tester);
    session.selectLayer(const LayerId('c'));
    session.layerVerbs.deleteActiveLayer();
    await tester.pumpAndSettle();
    expect(find.named('timeline-layer-name-c'), findsNothing, reason: '⛔전제');

    final shown = await carried(tester, 'b', 'after-a', 8);

    expect(shown, greaterThan(0.5));
  });

  testWidgets('CONTROL: the screen shows the line before a row', (
    tester,
  ) async {
    await open(tester);

    final shown = await carried(tester, 'a', 'before-b', -8);

    expect(shown, greaterThan(0.5));
  });
}
