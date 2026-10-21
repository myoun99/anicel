import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/range_move_asking_first.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/dart_sources.dart';

/// 🚨F-413 (유저 2026-10-19): 「A의 1,2라는 프레임이있고, B의 3,1이라는
/// 프레임있을때, A1,A2를 B행으로 옮기면 1이라는 이름의 그림이 두개존재함.
/// 그래서 B행에 이동하고 손 뗄 때 링크프레임 창 작동시키도록? 그게 젤
/// 적당할거같은데. 겸용컷일때도 이런식으로 해서 블록 다른행이동 가능하도록
/// 법통일」.
///
/// A drawing carried onto a row that already holds its name asks the
/// rename's question before it lands: Link — the carried block shows the
/// row's own drawing of that name, and the carried drawing is discarded —
/// or Cancel, and nothing moves.
void main() {
  Layer rowIn(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  FrameId drawNamed(
    EditorSessionManager s,
    LayerId row,
    int frame,
    String name,
  ) {
    s.selectLayer(row);
    s.selectFrameIndex(frame);
    s.createDrawingAtCurrentFrame();
    expect(s.frameVerbs.renameSelectedFrame(name), isNull, reason: '⛔전제');
    return rowIn(s, row).timeline[frame]!.frameId!;
  }

  /// 유저's rows: A holding 「1」「2」 at 0 and 1, B holding 「3」「1」 — and
  /// a band over A's two blocks, picked up and held over B.
  ///
  /// B's 「1」 stands past where A's land: a block they land on goes back
  /// to A (F-384-Q1 「덮인 블록이 떠난 자리로」), and B would hold no 「1」
  /// left to ask about — B's 「3」, landed on, is the one that does.
  ({
    LayerId a,
    LayerId b,
    FrameId a1,
    FrameId a2,
    FrameId b3,
    FrameId b1,
  })
  heldOverB(EditorSessionManager s) {
    final a = s.activeLayer!.id;
    s.layerStack.addLayer();
    final b = s.activeLayer!.id;
    final a1 = drawNamed(s, a, 0, '1');
    final a2 = drawNamed(s, a, 1, '2');
    final b3 = drawNamed(s, b, 0, '3');
    final b1 = drawNamed(s, b, 3, '1');
    s.selectLayer(a);
    s.updateFrameRangeSelectionDrag(layerId: a, anchorIndex: 0, headIndex: 1);
    expect(s.rangeMove.beginFrameRangeMoveDrag(a), isTrue, reason: '⛔전제');
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: b);
    return (a: a, b: b, a1: a1, a2: a2, b3: b3, b1: b1);
  }

  group('the session', () {
    late EditorSessionManager s;

    setUp(() {
      s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
    });

    test('letting go writes nothing, keeps the drag, and names what it '
        'would join', () {
      final (:a, :b, :a1, a2: _, b3: _, :b1) = heldOverB(s);
      final steps = s.historyManager.undoCount;

      final joins = s.rangeMove.endFrameRangeMoveDrag();

      expect(joins, hasLength(1));
      expect((joins!.single.from, joins.single.onto), (a, b));
      expect(joins.single.held, {a1: b1}, reason: '「2」 is a free name');
      expect(rowIn(s, a).timeline.keys, [0, 1], reason: 'nothing written');
      expect(s.historyManager.undoCount, steps);
      expect(s.dragPreview.value, isNotNull, reason: 'held for the answer');
    });

    test('Link lands it: B keeps ONE drawing of 「1」, shown where A\'s '
        'landed, and 「2」 comes along — one undo puts all of it back', () {
      final (:a, :b, :a1, :a2, :b3, :b1) = heldOverB(s);
      final steps = s.historyManager.undoCount;
      s.rangeMove.endFrameRangeMoveDrag();

      s.rangeMove.endFrameRangeMoveDrag(joinTakenNames: true);

      final landed = rowIn(s, b);
      expect(landed.timeline[0]?.frameId, b1, reason: 'A\'s 「1」 shows B\'s');
      expect(landed.timeline[1]?.frameId, a2);
      expect(
        [
          for (final frame in landed.frames)
            if (frame.name == '1') frame.id,
        ],
        [b1],
        reason: '⛔「1이라는 이름의 그림이 두개존재함」',
      );
      expect(
        {
          for (final MapEntry(:key, :value) in rowIn(s, a).timeline.entries)
            key: value.frameId,
        },
        {0: b3},
        reason: 'the move happened — and B\'s 「3」 it landed on went back',
      );
      expect(s.historyManager.undoCount, steps + 1, reason: 'one step');

      for (var press = 0; press < 2; press += 1) {
        if (rowIn(s, a).timeline[0]?.frameId == a1) {
          break;
        }
        s.undo();
      }
      expect(rowIn(s, a).timeline[0]?.frameId, a1);
      expect(rowIn(s, a).timeline[1]?.frameId, a2);
      expect(rowIn(s, b).timeline[0]?.frameId, b3);
      expect(rowIn(s, b).timeline[3]?.frameId, b1);
    });

    test('Cancel puts the blocks back and writes nothing', () {
      final (:a, :b, :a1, :a2, b3: _, b1: _) = heldOverB(s);
      final steps = s.historyManager.undoCount;
      s.rangeMove.endFrameRangeMoveDrag();

      s.rangeMove.cancelFrameRangeMoveDrag();

      expect(rowIn(s, a).timeline[0]?.frameId, a1);
      expect(rowIn(s, a).timeline[1]?.frameId, a2);
      expect(rowIn(s, b).frames, hasLength(2));
      expect(s.historyManager.undoCount, steps);
      expect(s.dragPreview.value, isNull);
    });

    // 「겸용컷일때도 이런식으로」: a 겸용 row's names are its bank's, and the
    // bank holds the drawings every cut's row shows.
    test('in a 겸용 cut, a name only the other cut shows asks too', () {
      final cut1 = s.requireActiveCut.id;
      final aIn1 = s.activeLayer!.id;
      s.layerStack.addLayer();
      final bIn1 = s.activeLayer!.id;
      final held = drawNamed(s, bIn1, 0, '1');
      s.cutVerbs.createLinkedCutFromActiveCut();
      LayerId memberOf(LayerId row) => s.repository
          .requireProject()
          .linkRegistry
          .groupOf(cutId: cut1, layerId: row)!
          .members
          .firstWhere((member) => member.cutId != cut1)
          .layerId;
      final a = memberOf(aIn1);
      final b = memberOf(bIn1);
      expect(s.requireActiveCut.id, isNot(cut1), reason: '⛔전제');
      expect(rowIn(s, b).timeline, isEmpty, reason: '⛔전제: not shown here');
      final carried = drawNamed(s, a, 0, '1');
      s.updateFrameRangeSelectionDrag(layerId: a, anchorIndex: 0, headIndex: 0);
      expect(s.rangeMove.beginFrameRangeMoveDrag(a), isTrue);
      s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: b);

      final joins = s.rangeMove.endFrameRangeMoveDrag();

      expect(joins?.single.held, {carried: held});
    });

    // The move's own commit tells listeners before the names are joined.
    test('whoever listens is told once the names are joined, not only '
        'before', () {
      final b = heldOverB(s).b;
      s.rangeMove.endFrameRangeMoveDrag();
      var lastHeard = const <String?>[];
      void hear() => lastHeard = [for (final f in rowIn(s, b).frames) f.name];
      s.addListener(hear);
      addTearDown(() => s.removeListener(hear));

      s.rangeMove.endFrameRangeMoveDrag(joinTakenNames: true);

      expect(lastHeard, isNotEmpty, reason: '⛔전제: it was told');
      expect(lastHeard.where((name) => name == '1'), hasLength(1));
    });

    // An S row's names are its lines', not its drawings' identities
    // (`LayerKind.celNameIsIdentity`): two lines may say the same.
    test('a line carried onto an S row saying the same lands without '
        'asking', () {
      final [from, onto, ...] = s.activeTrack.seLayers;
      Layer saying(Layer row, String id, int at) => row.copyWith(
        frames: [
          Frame(id: FrameId(id), duration: 1, strokes: const [], name: 'A'),
        ],
        timeline: {at: TimelineExposure.drawing(FrameId(id), length: 1)},
      );
      s.repository.replaceLayer(layer: saying(from, 'line-1', 0));
      s.repository.replaceLayer(layer: saying(onto, 'line-2', 4));
      s.updateFrameRangeSelectionDrag(
        layerId: from.id,
        anchorIndex: 0,
        headIndex: 0,
      );
      expect(s.rangeMove.beginFrameRangeMoveDrag(from.id), isTrue);
      s.rangeMove.updateFrameRangeMoveDrag(
        frameDelta: 0,
        targetLayerId: onto.id,
      );

      expect(s.rangeMove.endFrameRangeMoveDrag(), isNull);
      final landed = s.activeTrack.seLayers.firstWhere(
        (layer) => layer.id == onto.id,
      );
      expect(
        landed.timeline[0]?.frameId,
        const FrameId('line-1'),
        reason: '⛔전제: the move reached the S row',
      );
    });
  });

  testWidgets('the release asks in the rename\'s own window — Cancel puts '
      'the blocks back, Link lands them joined', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final workspace = find.byType(EditorWorkspace);
    final s = tester.widget<EditorWorkspace>(workspace).session;
    const window = ValueKey<String>('frame-name-conflict-dialog');

    /// Lets the held band go and answers the window with [button].
    Future<void> releaseAnswering(String button) async {
      final answered = releaseRangeMoveAskingFirst(
        tester.element(workspace),
        s,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(window), findsOneWidget);
      expect(
        find.text(AppText.strings.frameNameConflictBody),
        findsOneWidget,
        reason: 'the listed frames are the carried ones, whose drawings a '
            'join discards — the rename\'s sentence',
      );
      await tester.tap(
        find.byKey(ValueKey<String>('frame-name-conflict-$button-button')),
      );
      await tester.pumpAndSettle();
      await answered;
      expect(find.byKey(window), findsNothing);
    }

    final (:a, :b, :a1, a2: _, b3: _, :b1) = heldOverB(s);
    await releaseAnswering('cancel');
    expect(rowIn(s, a).timeline[0]?.frameId, a1, reason: 'Cancel');
    expect(s.dragPreview.value, isNull, reason: 'the drag is let go of');

    s.updateFrameRangeSelectionDrag(layerId: a, anchorIndex: 0, headIndex: 1);
    expect(s.rangeMove.beginFrameRangeMoveDrag(a), isTrue);
    s.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: b);
    await releaseAnswering('link');
    expect(rowIn(s, b).timeline[0]?.frameId, b1, reason: 'Link');
  });

  // The hosts hand every range move's release to the one door that asks:
  // a release wired straight to the session would land the second 「1」.
  test('no panel lets a range move go without asking', () {
    final bypasses = <String>[];
    for (final file in dartFilesUnder('lib/src/ui')) {
      final text = file.readAsStringSync();
      if (text.contains('rangeMove.endFrameRangeMoveDrag') &&
          !file.path.endsWith('range_move_asking_first.dart')) {
        bypasses.add(file.path);
      }
    }
    expect(bypasses, isEmpty);
  });
}
