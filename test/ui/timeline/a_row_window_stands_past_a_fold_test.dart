import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_placement.dart';
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

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️F-526 (유저 11-01): 아래쪽에서 어태치를 펼치고 스크롤을 내리고, 다시
/// 접고, 다시 펼쳐 내리면 그 밑의 행이 없다 — 자리는 있고 행만 없다.
///
/// A fold lays the rows again where the scroll stands, without the scroll's
/// crossing hearing of it. So the second time down, the window the scroll
/// reached had the number the crossing last published, for a window it no
/// longer drew, and it was never cut.
void main() {
  const conte = LayerId('conte');
  const bg = LayerId('bg');

  Layer row(String id) => Layer(id: LayerId(id), name: id, frames: const []);

  Project film() => Project(
    id: const ProjectId('fold'),
    name: 'Fold',
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
              row('conte'),
              row('d'),
              Layer(
                id: const LayerId('bg-1'),
                name: 'bg-1',
                frames: const [],
                attachedToLayerId: bg,
                attachedPlacement: AttachedPlacement.below,
              ),
              row('bg'),
              for (var index = 0; index < 12; index += 1) row('above-$index'),
            ],
          ),
        ],
      ),
    ],
  );

  ScrollPosition rows(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-vertical-scroll-viewport'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  Future<void> toTheEnd(WidgetTester tester) async {
    final position = rows(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
  }

  Future<EditorSessionManager> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = await pumpTimelineHost(
      tester,
      film(),
      surface: const Size(1400, 420),
    );
    await tester.pumpAndSettle();
    return session;
  }

  final lastRow = find.named('timeline-layer-name-${conte.value}');

  for (final (name, fold) in <(String, Future<void> Function(WidgetTester))>[
    (
      'an attach group',
      (tester) async {
        await tester.tap(find.named('timeline-attach-twirl-${bg.value}'));
        await tester.pumpAndSettle();
      },
    ),
    (
      'a row of lanes',
      (tester) async {
        timelineSessionOf(tester).layerSwitches.toggleLayerLanes(bg);
        await tester.pumpAndSettle();
      },
    ),
  ]) {
    testWidgets('$name opened, down, shut, opened, down: the last row is '
        'there', (tester) async {
      await open(tester);
      await toTheEnd(tester);
      expect(lastRow, findsOneWidget, reason: '⛔전제');

      await fold(tester);
      await toTheEnd(tester);
      expect(lastRow, findsOneWidget, reason: 'once down');

      await fold(tester);
      await fold(tester);
      await toTheEnd(tester);
      expect(lastRow, findsOneWidget, reason: 'down again');
    });
  }
}
