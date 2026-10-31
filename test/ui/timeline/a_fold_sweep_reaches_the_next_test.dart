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
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🔬서피스 검증 (2026-11-01): 어태치 묶음 둘에서 A 의 접기 버튼을 위로 끌어
/// B 까지 가도 A 만 접혔고, B 에서 아래로 끌어도 B 만 접혔다.
///
/// A press on a fold moves the rows under it, so these drive the real rail:
/// a fake one whose rows stay put passed the whole time.
void main() {
  tearDown(debugClearValueControlPointers);

  const a = LayerId('a');
  const b = LayerId('b');
  const folder = LayerId('f');

  Layer plain(String id, {LayerId? attachedTo, LayerId? folderId}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    attachedToLayerId: attachedTo,
    folderId: folderId,
  );

  Project film(List<Layer> layers) => Project(
    id: const ProjectId('fold-sweep'),
    name: 'Fold sweep',
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
            layers: layers,
          ),
        ],
      ),
    ],
  );

  /// Two groups, rail top to bottom: b1, b, a1, a.
  Project twoGroups() => film([
    plain('a'),
    plain('a1', attachedTo: a),
    plain('b'),
    plain('b1', attachedTo: b),
  ]);

  /// A group over a folder, rail top to bottom: b1, b, f, m — so folding b
  /// slides a row that folds under the cursor.
  Project aGroupOverAFolder() => film([
    plain('m', folderId: folder),
    createFolderLayer(id: folder, name: 'f'),
    plain('b'),
    plain('b1', attachedTo: b),
  ]);

  Future<EditorSessionManager> pump(
    WidgetTester tester,
    Project project, {
    TimelineOrientation orientation = TimelineOrientation.horizontal,
  }) => pumpTimelineHost(
    tester,
    project,
    surface: const Size(1400, 700),
    orientation: orientation,
  );

  Future<TestGesture> press(WidgetTester tester, String name) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.named(name)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    return gesture;
  }

  Future<void> moveTo(
    WidgetTester tester,
    TestGesture gesture,
    Offset from,
    Offset to,
  ) async {
    for (var step = 1; step <= 8; step += 1) {
      await gesture.moveTo(Offset.lerp(from, to, step / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Presses [from] and drags to [to] where the eye finds it after the press
  /// moved it.
  Future<void> sweep(WidgetTester tester, String from, String to) async {
    final start = tester.getCenter(find.named(from));
    final gesture = await press(tester, from);
    await moveTo(tester, gesture, start, tester.getCenter(find.named(to)));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Set<LayerId> folded(EditorSessionManager session) =>
      session.railView.collapsedAttachBaseIds.value;

  bool folderShut(EditorSessionManager session) =>
      session.requireActiveCut.layers
          .firstWhere((layer) => layer.id == folder)
          .collapsed;

  for (final (orientation, prefix) in const [
    (TimelineOrientation.horizontal, 'timeline'),
    (TimelineOrientation.vertical, 'xsheet'),
  ]) {
    for (final (from, to) in const [('a', 'b'), ('b', 'a')]) {
      testWidgets('$prefix: a sweep from $from folds $to too', (tester) async {
        final session = await pump(
          tester,
          twoGroups(),
          orientation: orientation,
        );
        expect(folded(session), isEmpty, reason: '⛔전제');

        await sweep(
          tester,
          '$prefix-attach-twirl-$from',
          '$prefix-attach-twirl-$to',
        );

        expect(folded(session), {a, b});
      });
    }
  }

  testWidgets('a sweep opens as it folds', (tester) async {
    final session = await pump(tester, twoGroups());
    await sweep(
      tester,
      'timeline-attach-twirl-a',
      'timeline-attach-twirl-b',
    );
    expect(folded(session), {a, b}, reason: '⛔전제');

    await sweep(
      tester,
      'timeline-attach-twirl-b',
      'timeline-attach-twirl-a',
    );

    expect(folded(session), isEmpty);
  });

  testWidgets('a sweep crosses folders as it does groups', (tester) async {
    final session = await pump(
      tester,
      film([
        plain('m1', folderId: const LayerId('f1')),
        createFolderLayer(id: const LayerId('f1'), name: 'f1'),
        plain('m2', folderId: const LayerId('f2')),
        createFolderLayer(id: const LayerId('f2'), name: 'f2'),
      ]),
    );
    bool shut(String id) => session.requireActiveCut.layers
        .firstWhere((layer) => layer.id == LayerId(id))
        .collapsed;

    await sweep(
      tester,
      'timeline-folder-twirl-f1',
      'timeline-folder-twirl-f2',
    );
    expect((shut('f1'), shut('f2')), (true, true));

    await sweep(
      tester,
      'timeline-folder-twirl-f2',
      'timeline-folder-twirl-f1',
    );
    expect((shut('f1'), shut('f2')), (false, false));
  });

  testWidgets('🚨a row a fold lifted away from the cursor stays folded while '
      'the cursor stays', (tester) async {
    final session = await pump(tester, twoGroups());
    final start = tester.getCenter(find.named('timeline-attach-twirl-a'));
    final end = tester.getCenter(find.named('timeline-attach-twirl-b'));
    final gesture = await press(tester, 'timeline-attach-twirl-a');
    await moveTo(tester, gesture, start, end);
    expect(folded(session), {a, b}, reason: '⛔전제');

    // b's fold lifted a under the cursor: it stands on a now, and a row
    // asked where it stands would be let go and folded again each move.
    for (var nudge = 0; nudge < 6; nudge += 1) {
      await gesture.moveBy(Offset(0, nudge.isEven ? -1 : 1));
      await tester.pump(const Duration(milliseconds: 16));
      expect(folded(session), {a, b}, reason: 'nudge $nudge');
    }

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('back on the press, the row the sweep folded opens, and the '
      'press stays', (tester) async {
    final session = await pump(tester, twoGroups());
    final start = tester.getCenter(find.named('timeline-attach-twirl-a'));
    final end = tester.getCenter(find.named('timeline-attach-twirl-b'));
    final gesture = await press(tester, 'timeline-attach-twirl-a');
    await moveTo(tester, gesture, start, end);
    expect(folded(session), {a, b}, reason: '⛔전제');

    await moveTo(tester, gesture, end, start);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(folded(session), {a});
  });

  testWidgets('a fold sweep is one undo', (tester) async {
    final session = await pump(tester, twoGroups());
    await sweep(
      tester,
      'timeline-attach-twirl-a',
      'timeline-attach-twirl-b',
    );
    expect(folded(session), {a, b}, reason: '⛔전제');

    session.undo();
    await tester.pumpAndSettle();

    expect(folded(session), isEmpty);
  });

  testWidgets('⛔a tremble on the twirl leaves the row the fold slid under the '
      'cursor alone', (tester) async {
    final session = await pump(tester, aGroupOverAFolder());
    final gesture = await press(tester, 'timeline-attach-twirl-b');
    expect(folded(session), {b}, reason: '⛔전제');

    await gesture.moveBy(const Offset(0, 1));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -2));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(folderShut(session), isFalse);
  });

  testWidgets('⛔a sweep up the rail leaves the row a fold slid in below the '
      'press alone', (tester) async {
    final session = await pump(tester, aGroupOverAFolder());
    final height = tester.getRect(find.named('timeline-layer-row-b')).height;
    final gesture = await press(tester, 'timeline-attach-twirl-b');
    expect(folded(session), {b}, reason: '⛔전제');

    // One row up is where b stands now; the folder stands at the press.
    await gesture.moveBy(Offset(0, -height));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(folderShut(session), isFalse);
  });

  testWidgets('back on the press, the row a fold slid under it opens again', (
    tester,
  ) async {
    final session = await pump(tester, aGroupOverAFolder());
    final height = tester.getRect(find.named('timeline-layer-row-b')).height;
    final gesture = await press(tester, 'timeline-attach-twirl-b');

    await gesture.moveBy(Offset(0, height));
    await tester.pump(const Duration(milliseconds: 16));
    expect(folderShut(session), isTrue, reason: '⛔전제');

    await gesture.moveBy(Offset(0, -height));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(folderShut(session), isFalse);
  });

  testWidgets('⛔a fold above the press moves it, and the sweep up goes on '
      'from where it stands', (tester) async {
    final session = await pump(
      tester,
      film([
        plain('m', folderId: folder),
        createFolderLayer(id: folder, name: 'f'),
        plain('a'),
        plain('a1', attachedTo: a),
        plain('b'),
        plain('b1', attachedTo: b),
      ]),
    );
    final start = tester.getCenter(find.named('timeline-attach-twirl-a'));
    final gesture = await press(tester, 'timeline-attach-twirl-a');
    final end = tester.getCenter(find.named('timeline-attach-twirl-b'));
    await moveTo(tester, gesture, start, end);
    expect(folded(session), {a, b}, reason: '⛔전제');

    // Both folds lifted a, and f with it, up towards the cursor: a stretch
    // begun where a stood reaches past a now, down onto f.
    await gesture.moveBy(const Offset(0, -2));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(folderShut(session), isFalse);
  });

  testWidgets('a sweep down the rail reaches the row a fold slid under the '
      'press', (tester) async {
    final session = await pump(tester, aGroupOverAFolder());
    final height = tester.getRect(find.named('timeline-layer-row-b')).height;
    final gesture = await press(tester, 'timeline-attach-twirl-b');

    await gesture.moveBy(Offset(0, height));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(folded(session), {b});
    expect(folderShut(session), isTrue);
  });
}
