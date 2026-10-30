import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/link_mirror.dart'
    show existenceMirrorTargets;
import 'package:anicel/src/ui/editor_session_manager.dart';
import '../../helpers/a_folder_made_by_hand.dart';

/// 🗣️I-73 — the drawn proposal 유저 took on 2026-10-08: 「머리 — 이름 ·
/// 라벨 · 블렌드 · 불투명도 · 눈 · 어태치 구성 · fx 구성 — 트랙의 모든
/// 컷이 하나」 · 「머리의 통일은 링크 그룹으로 만들지 않습니다」.
///
/// The attach rows a track's conte carries are its head's: a row added to
/// one cut's conte is added to every cut's, a conte born into the track is
/// born carrying them, and a row deleted goes from every cut — each in one
/// undo step, and none of it through a link group.
void main() {
  Layer conte(String cut) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    frames: [Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
  );

  Layer rider(
    String cut,
    String suffix, {
    required AttachedPlacement placement,
    String? name,
    double opacity = 1,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    bool onTimesheet = true,
  }) => Layer(
    id: LayerId('$cut-$suffix'),
    name: name ?? (placement == AttachedPlacement.above ? 'Over' : 'Under'),
    kind: LayerKind.storyboard,
    opacity: opacity,
    blendMode: blendMode,
    onTimesheet: onTimesheet,
    attachedToLayerId: LayerId('$cut-conte'),
    attachedPlacement: placement,
    attachedMode: AttachedMode.free,
    frames: const [],
    timeline: const {},
  );

  Layer cel(String cut) => Layer(
    id: LayerId('$cut-cel'),
    name: 'A',
    frames: const [],
    timeline: const {},
  );

  Cut cutOf(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: layers,
  );

  EditorSessionManager sessionOf(List<Cut> cuts) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('attach-rows'),
        name: 'Attach rows',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [Track(id: const TrackId('t1'), name: 'V1', cuts: cuts)],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  Cut cutIn(EditorSessionManager session, String id) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == CutId(id));

  /// A cut's conte group as `seat:name`, top row first.
  List<String> seats(EditorSessionManager session, String cut) => [
    for (final entry in conteGroupOf(cutIn(session, cut)))
      '${entry.seat}:${entry.row.name}',
  ];

  Layer seatRow(EditorSessionManager session, String cut, int seat) =>
      conteRowAtSeat(cutIn(session, cut), seat)!;

  void standOn(EditorSessionManager session, String cut, String layer) {
    session.selectCut(CutId(cut));
    session.selectLayer(LayerId(layer));
    expect(session.activeLayerId, LayerId(layer), reason: 'fixture: standing');
  }

  group('an attach row added to one cut\'s conte', () {
    for (final (placement, seat) in const [
      (AttachedPlacement.above, 1),
      (AttachedPlacement.below, -1),
    ]) {
      test('is added to every cut\'s — ${placement.name}: each riding its '
          'own cut\'s conte, on the same seat, unlinked, in one undo', () {
        final session = sessionOf([
          cutOf('a', [cel('a'), conte('a')]),
          cutOf('b', [cel('b'), conte('b')]),
          cutOf('c', [cel('c')]),
        ]);
        standOn(session, 'a', 'a-conte');
        final steps = session.historyManager.undoCount;

        session.folders.addAttachedLayer(placement);

        final inA = seatRow(session, 'a', seat);
        final inB = seatRow(session, 'b', seat);
        expect(conteGroupOf(cutIn(session, 'a')), hasLength(2));
        expect(conteGroupOf(cutIn(session, 'b')), hasLength(2));
        expect(
          (inA.attachedToLayerId, inB.attachedToLayerId),
          (const LayerId('a-conte'), const LayerId('b-conte')),
        );
        expect(inB.id, isNot(inA.id));
        expect(
          (inB.name, inB.kind, inB.attachedPlacement, inB.attachedMode),
          (inA.name, inA.kind, inA.attachedPlacement, inA.attachedMode),
          reason: 'the same row, born the same',
        );
        expect(
          session.repository.requireProject().linkRegistry.groups,
          isEmpty,
          reason: '⛔the head is no link group',
        );
        expect(
          cutIn(session, 'c').layers.map((layer) => layer.id.value),
          ['c-cel'],
          reason: 'a cut with no conte has nothing for the row to ride',
        );
        expect(session.activeLayerId, inA.id, reason: 'you stand on yours');
        expect(session.historyManager.undoCount, steps + 1);

        session.undo();
        expect(conteGroupOf(cutIn(session, 'a')), hasLength(1));
        expect(conteGroupOf(cutIn(session, 'b')), hasLength(1));
      });
    }

    test('lands at the end of its side in every cut — a second one above '
        'is +2 everywhere', () {
      final session = sessionOf([
        cutOf('a', [cel('a'), conte('a')]),
        cutOf('b', [conte('b'), cel('b')]),
      ]);
      standOn(session, 'a', 'a-conte');
      session.folders.addAttachedLayer(AttachedPlacement.above);
      standOn(session, 'a', 'a-conte');
      session.folders.addAttachedLayer(AttachedPlacement.above);

      expect(seats(session, 'a').map((row) => row.split(':').first), [
        '2',
        '1',
        '0',
      ]);
      expect(seats(session, 'b').map((row) => row.split(':').first), [
        '2',
        '1',
        '0',
      ]);
      // In b the conte is the bottom row: its attach rows stand right over
      // it, under the cel that was above it.
      expect(cutIn(session, 'b').layers.last.id, const LayerId('b-cel'));
      // …and each cut holds the cel, the conte and the two rows: nothing
      // was born riding a row that rides.
      expect(cutIn(session, 'a').layers, hasLength(4));
      expect(cutIn(session, 'b').layers, hasLength(4));
    });

    for (final (placement, seat) in const [
      (AttachedPlacement.above, 1),
      (AttachedPlacement.below, -1),
    ]) {
      // ↩️I-73: a row added to a cut lacking a seat another cut held was
      // born on that seat wearing its head, and the other cut was given no
      // second row. Since F-343 no cut lacks it past the open: the seat is
      // the structure's, given to every cut's conte.
      test('🚨a seat only another cut holds is every cut\'s from the open — '
          '${placement.name}: given wearing its head — and a row added lands '
          'past it in every cut', () {
        final session = sessionOf([
          cutOf('a', [cel('a'), conte('a')]),
          cutOf('b', [
            cel('b'),
            if (placement == AttachedPlacement.below)
              rider(
                'b',
                'side',
                placement: placement,
                name: 'Shadow',
                opacity: 0.5,
                blendMode: LayerBlendMode.multiply,
              ),
            conte('b'),
            if (placement == AttachedPlacement.above)
              rider(
                'b',
                'side',
                placement: placement,
                name: 'Shadow',
                opacity: 0.5,
                blendMode: LayerBlendMode.multiply,
              ),
          ]),
        ]);
        final given = seatRow(session, 'a', seat);
        expect(
          (given.name, given.opacity, given.blendMode),
          ('Shadow', 0.5, LayerBlendMode.multiply),
        );
        standOn(session, 'a', 'a-conte');

        session.folders.addAttachedLayer(placement);

        expect(seatRow(session, 'a', seat).id, given.id);
        expect(seatRow(session, 'b', seat).id, const LayerId('b-side'));
        expect(seatRow(session, 'b', seat * 2).id, isNot(given.id));
        expect(conteGroupOf(cutIn(session, 'b')), hasLength(3));
      });
    }

    test('every row the step plants has an id of its own', () {
      final session = sessionOf([
        for (final cut in const ['a', 'b', 'c', 'd'])
          cutOf(cut, [cel(cut), conte(cut)]),
      ]);
      standOn(session, 'a', 'a-conte');

      session.folders.addAttachedLayer(AttachedPlacement.above);

      final planted = [
        for (final cut in const ['a', 'b', 'c', 'd'])
          seatRow(session, cut, 1).id,
      ];
      expect(planted.toSet(), hasLength(4));
    });

    test('🚨a row added on ANOTHER row of the cut is that cut\'s alone, and '
        'wears no head', () {
      final session = sessionOf([
        cutOf('a', [cel('a'), conte('a')]),
        cutOf('b', [
          cel('b'),
          conte('b'),
          rider('b', 'over', placement: AttachedPlacement.above, opacity: 0.5),
        ]),
      ]);
      final bWas = [
        for (final layer in cutIn(session, 'b').layers) layer.id.value,
      ];
      standOn(session, 'a', 'a-cel');

      session.folders.addAttachedLayer(AttachedPlacement.above);

      final born = cutIn(
        session,
        'a',
      ).layers.firstWhere((layer) => layer.id == session.activeLayerId);
      expect(born.attachedToLayerId, const LayerId('a-cel'), reason: 'fixture');
      expect(born.opacity, 1, reason: 'the cel\'s row is no seat of the conte');
      expect(
        [for (final layer in cutIn(session, 'b').layers) layer.id.value],
        bWas,
      );
    });

    // 🗣️I-73-one-head-Q2 (유저 2026-10-09 → `all`): 「넷 다 모든 컷에 함께」
    // — 오거나이저 안 추가 is one of the four. ↩️Such a row was its cut's
    // alone: the planner named only the group's edge, and stood down. And
    // it was born in no folder in the other cuts, until the 공정 folder was
    // the track's structure's as well (F-343).
    test('🚨a row born INTO an organizer of the conte\'s rows is born on its '
        'seat in every cut\'s — riding the conte there, in that cut\'s row of '
        'the folder', () {
      final session = sessionOf([
        cutOf('a', [
          cel('a'),
          conte('a'),
          rider('a', 'over', placement: AttachedPlacement.above),
        ]),
        cutOf('b', [
          cel('b'),
          conte('b'),
          rider('b', 'over', placement: AttachedPlacement.above),
        ]),
      ]);
      standOn(session, 'a', 'a-over');
      groupTheActiveAttachIntoAFolder(session);
      standOn(session, 'a', 'a-over');
      final organizer = cutIn(
        session,
        'a',
      ).layers.firstWhere((layer) => layer.id == const LayerId('a-over'));
      expect(organizer.folderId, isNotNull, reason: 'fixture: filed');

      session.folders.addAttachedLayer(AttachedPlacement.above);

      final inA = conteGroupOf(cutIn(session, 'a'));
      final inB = conteGroupOf(cutIn(session, 'b'));
      expect(inA, hasLength(4), reason: '⛔전제: the folder holds a seat too');
      expect(inB, hasLength(4));
      bool isNew(ConteSeat entry) =>
          entry.seat != 0 &&
          !entry.row.kind.groupsLayers &&
          entry.row.id != const LayerId('a-over');
      final bornSeat = inA.firstWhere(isNew).seat;
      final bornInB = inB.firstWhere((entry) => entry.seat == bornSeat).row;
      expect(bornInB.id, isNot(const LayerId('b-over')), reason: 'a new row');
      expect(bornInB.attachedToLayerId, const LayerId('b-conte'));
      final folderInA = cutIn(session, 'a').layers.byId(organizer.folderId!)!;
      expect(
        cutIn(session, 'b').layers.byId(bornInB.folderId!)?.conteKey,
        folderInA.conteKey,
      );
    });
  });

  test('🚨with a 겸용 cut on the track: the sibling takes the row AS the '
      'same layer, every other cut a row of its own — and none takes two', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    Cut cutBy(CutId id) =>
        session.activeTrack.cuts.firstWhere((cut) => cut.id == id);
    List<Layer> riders(CutId id) => [
      for (final entry in conteGroupOf(cutBy(id)))
        if (entry.seat != 0) entry.row,
    ];

    // A cut with a conte, its 겸용 sibling, and a third cut with a conte of
    // its own.
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final source = session.requireActiveCut.id;
    session.cutVerbs.createLinkedCutFromActiveCut();
    final linked = session.requireActiveCut.id;
    session.cutVerbs.createCut();
    final apart = session.requireActiveCut.id;
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    expect({source, linked, apart}, hasLength(3), reason: 'fixture');
    for (final cut in [source, linked, apart]) {
      expect(
        storyboardLayerForCut(cutBy(cut)),
        isNotNull,
        reason: 'fixture: every cut has a conte',
      );
    }

    session.selectCut(source);
    session.selectLayer(storyboardLayerForCut(cutBy(source))!.id);
    session.folders.addAttachedLayer(AttachedPlacement.above);

    for (final cut in [source, linked, apart]) {
      expect(riders(cut), hasLength(1), reason: 'one row a cut: $cut');
    }
    final registry = session.repository.requireProject().linkRegistry;
    final group = registry.groupOf(
      cutId: source,
      layerId: riders(source).single.id,
    );
    expect(
      {for (final member in group!.members) member.layerId},
      {riders(source).single.id, riders(linked).single.id},
      reason: 'the 겸용 pair\'s rows are one layer; the third cut\'s is not',
    );
    expect(
      registry.groupOf(cutId: apart, layerId: riders(apart).single.id),
      isNull,
    );

    // And it goes from all three at once.
    session.layerVerbs.deleteActiveLayer();
    for (final cut in [source, linked, apart]) {
      expect(riders(cut), isEmpty, reason: 'gone from $cut');
    }
    session.undo();
    for (final cut in [source, linked, apart]) {
      expect(riders(cut), hasLength(1), reason: 'back in $cut');
    }
  });

  group('with 겸용 pairs on the track', () {
    /// A default project's track, grown to [pairs] 겸용 pairs of cuts — every
    /// cut with a conte, each pair's contes one layer — the session standing
    /// on the first cut's conte.
    ({EditorSessionManager session, List<(CutId, CutId)> pairs}) paired(
      int pairs,
    ) {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final made = <(CutId, CutId)>[];
      for (var pair = 0; pair < pairs; pair += 1) {
        if (pair > 0) {
          session.cutVerbs.createCut();
        }
        session.layerStack.addLayerOfKind(LayerKind.storyboard);
        final source = session.requireActiveCut.id;
        session.cutVerbs.createLinkedCutFromActiveCut();
        made.add((source, session.requireActiveCut.id));
      }
      session.selectCut(made.first.$1);
      session.selectLayer(
        storyboardLayerForCut(session.requireActiveCut)!.id,
      );
      return (session: session, pairs: made);
    }

    Cut cutBy(EditorSessionManager session, CutId id) =>
        session.activeTrack.cuts.firstWhere((cut) => cut.id == id);

    test('🚨each pair\'s rows are one layer of their own — two pairs, two '
        'groups', () {
      final (:session, :pairs) = paired(2);
      final groupsBefore = session.repository
          .requireProject()
          .linkRegistry
          .groups
          .length;

      session.folders.addAttachedLayer(AttachedPlacement.above);

      final registry = session.repository.requireProject().linkRegistry;
      final groupOfPair = [
        for (final (source, linked) in pairs)
          {
            for (final cut in [source, linked])
              registry
                  .groupOf(
                    cutId: cut,
                    layerId: conteRowAtSeat(cutBy(session, cut), 1)!.id,
                  )
                  ?.id,
          },
      ];
      expect(groupOfPair[0], hasLength(1), reason: 'the first pair: one');
      expect(groupOfPair[1], hasLength(1), reason: 'the second pair: one');
      expect(groupOfPair[0].single, isNotNull);
      expect(groupOfPair[1].single, isNot(groupOfPair[0].single));
      expect(registry.groups, hasLength(groupsBefore + 2));
    });

    test('🚨a conte born into a pair is born carrying the track\'s rows in '
        'both cuts — the sibling\'s riding the sibling\'s conte, as the '
        'same layer', () {
      final (:session, :pairs) = paired(1);
      session.folders.addAttachedLayer(AttachedPlacement.above);
      // A new pair of cuts with no conte yet.
      session.cutVerbs.createCut();
      final source = session.requireActiveCut.id;
      session.cutVerbs.createLinkedCutFromActiveCut();
      final linked = session.requireActiveCut.id;
      expect(pairs.single, isNot((source, linked)), reason: 'fixture');
      expect(storyboardLayerForCut(cutBy(session, linked)), isNull);

      session.selectCut(source);
      session.layerStack.addLayerOfKind(LayerKind.storyboard);

      for (final cut in [source, linked]) {
        expect(
          conteRowAtSeat(cutBy(session, cut), 1),
          isNotNull,
          reason: 'a row rides the conte of $cut',
        );
      }
      final born = [
        for (final cut in [source, linked])
          (
            conte: storyboardLayerForCut(cutBy(session, cut))!,
            rider: conteRowAtSeat(cutBy(session, cut), 1)!,
          ),
      ];
      expect(born[0].rider.attachedToLayerId, born[0].conte.id);
      expect(born[1].rider.attachedToLayerId, born[1].conte.id);
      final registry = session.repository.requireProject().linkRegistry;
      final group = registry.groupOf(
        cutId: source,
        layerId: born[0].rider.id,
      );
      expect(group, isNotNull, reason: 'the born rows are linked');
      expect(
        {for (final member in group!.members) member.layerId},
        {born[0].rider.id, born[1].rider.id},
      );
    });
  });

  group('a conte born into a track whose contes carry attach rows', () {
    test('🚨takes each seat\'s row in its place — two a side, each as its '
        'head is: its name, its side, its sheet switch', () {
      final session = sessionOf([
        cutOf('a', [
          rider(
            'a',
            'deep',
            placement: AttachedPlacement.below,
            name: 'Deep',
            onTimesheet: false,
          ),
          rider('a', 'under', placement: AttachedPlacement.below),
          conte('a'),
          rider('a', 'over', placement: AttachedPlacement.above),
          rider('a', 'high', placement: AttachedPlacement.above, name: 'High'),
        ]),
        cutOf('c', [cel('c')]),
      ]);
      expect(
        seats(session, 'a'),
        ['2:High', '1:Over', '0:Conte', '-1:Under', '-2:Deep'],
        reason: 'fixture',
      );
      standOn(session, 'c', 'c-cel');

      session.layerStack.addLayerOfKind(LayerKind.storyboard);

      expect(
        seats(session, 'c'),
        ['2:High', '1:Over', '0:Conte', '-1:Under', '-2:Deep'],
      );
      expect(
        [
          for (final seat in const [2, 1, -1, -2])
            seatRow(session, 'c', seat).attachedPlacement,
        ],
        [
          AttachedPlacement.above,
          AttachedPlacement.above,
          AttachedPlacement.below,
          AttachedPlacement.below,
        ],
      );
      expect(
        [
          for (final seat in const [2, 1, -1, -2])
            seatRow(session, 'c', seat).onTimesheet,
        ],
        [true, true, true, false],
        reason: 'the conte row\'s sheet switch is its head\'s (I-89-Q22: '
            '「콘티행은 그런부분 글로벌이니까 … 머리로 하나」) — Deep\'s off the '
            'sheet, the rest on. ↩️It was born off the sheet, as the ＋ makes '
            'an attach row, until the head wore the switch (F-443)',
      );
    });

    test('is born carrying them — a row a seat, wearing its head and '
        'holding nothing — in one undo', () {
      final session = sessionOf([
        cutOf('a', [
          cel('a'),
          rider('a', 'under', placement: AttachedPlacement.below),
          conte('a'),
          rider('a', 'over', placement: AttachedPlacement.above, opacity: 0.4),
        ]),
        cutOf('c', [cel('c')]),
      ]);
      standOn(session, 'c', 'c-cel');
      final steps = session.historyManager.undoCount;

      session.layerStack.addLayerOfKind(LayerKind.storyboard);

      expect(seats(session, 'c'), ['1:Over', '0:Conte', '-1:Under']);
      final over = seatRow(session, 'c', 1);
      final base = seatRow(session, 'c', 0);
      expect(over.attachedToLayerId, base.id);
      expect(over.opacity, 0.4, reason: 'the seat\'s head');
      expect(over.attachedMode, AttachedMode.free);
      expect(over.frames, isEmpty);
      expect(seatRow(session, 'c', -1).attachedToLayerId, base.id);
      expect(session.activeLayerId, base.id, reason: 'you stand on the conte');
      expect(session.historyManager.undoCount, steps + 1);

      session.undo();
      expect(conteGroupOf(cutIn(session, 'c')), isEmpty);
    });

    test('the first conte on a track is born alone', () {
      final session = sessionOf([cutOf('c', [cel('c')])]);
      standOn(session, 'c', 'c-cel');

      session.layerStack.addLayerOfKind(LayerKind.storyboard);

      expect(conteGroupOf(cutIn(session, 'c')), hasLength(1));
    });
  });

  group('deleting', () {
    List<Cut> twoCutsWithRiders() => [
      cutOf('a', [
        cel('a'),
        rider('a', 'under', placement: AttachedPlacement.below),
        conte('a'),
        rider('a', 'over', placement: AttachedPlacement.above),
      ]),
      cutOf('b', [
        rider('b', 'under', placement: AttachedPlacement.below),
        conte('b'),
        rider('b', 'over', placement: AttachedPlacement.above),
        cel('b'),
      ]),
    ];

    test('🚨an attach row takes its seat from every cut — and one undo puts '
        'each back where it stood', () {
      final session = sessionOf(twoCutsWithRiders());
      final before = [
        for (final cut in const ['a', 'b'])
          [for (final layer in cutIn(session, cut).layers) layer.id.value],
      ];
      standOn(session, 'a', 'a-over');
      final steps = session.historyManager.undoCount;

      session.layerVerbs.deleteActiveLayer();

      expect(seats(session, 'a'), ['0:Conte', '-1:Under']);
      expect(seats(session, 'b'), ['0:Conte', '-1:Under']);
      expect(session.historyManager.undoCount, steps + 1);

      session.undo();
      expect([
        for (final cut in const ['a', 'b'])
          [for (final layer in cutIn(session, cut).layers) layer.id.value],
      ], before);
    });

    test('a cut\'s CONTE takes its own attach rows with it and no other '
        'cut\'s', () {
      final session = sessionOf(twoCutsWithRiders());
      standOn(session, 'a', 'a-conte');

      session.layerVerbs.deleteActiveLayer();

      expect(conteGroupOf(cutIn(session, 'a')), isEmpty);
      expect(
        cutIn(session, 'a').layers.map((layer) => layer.id.value),
        ['a-cel'],
      );
      expect(seats(session, 'b'), ['1:Over', '0:Conte', '-1:Under']);
    });

    test('whose seat goes with a row: an attach row\'s, in every cut — a '
        'conte\'s own place is its cut\'s', () {
      final project = sessionOf(
        twoCutsWithRiders(),
      ).repository.requireProject();

      expect(
        existenceMirrorTargets(
          project,
          cutId: const CutId('a'),
          layerId: const LayerId('a-over'),
        ),
        [
          (cutId: const CutId('a'), layerId: const LayerId('a-over')),
          (cutId: const CutId('b'), layerId: const LayerId('b-over')),
        ],
      );
      expect(
        existenceMirrorTargets(
          project,
          cutId: const CutId('a'),
          layerId: const LayerId('a-conte'),
        ),
        [(cutId: const CutId('a'), layerId: const LayerId('a-conte'))],
      );
    });

    test('🚨the last row of an organizer takes the folder with it — in '
        'every cut that filed its row, each in its own cut', () {
      final session = sessionOf(twoCutsWithRiders());
      for (final cut in const ['a', 'b']) {
        standOn(session, cut, '$cut-over');
        groupTheActiveAttachIntoAFolder(session);
      }
      List<LayerKind> kindsIn(String cut) => [
        for (final layer in cutIn(session, cut).layers) layer.kind,
      ];
      expect(kindsIn('a'), contains(LayerKind.folder), reason: 'fixture');
      expect(kindsIn('b'), contains(LayerKind.folder), reason: 'fixture');
      final before = [
        for (final cut in const ['a', 'b'])
          [for (final layer in cutIn(session, cut).layers) layer.id.value],
      ];
      standOn(session, 'a', 'a-over');
      final steps = session.historyManager.undoCount;

      session.layerVerbs.deleteActiveLayer();

      for (final cut in const ['a', 'b']) {
        expect(seats(session, cut), ['0:Conte', '-1:Under'], reason: cut);
        expect(kindsIn(cut), isNot(contains(LayerKind.folder)), reason: cut);
      }
      expect(session.historyManager.undoCount, steps + 1);

      session.undo();
      expect([
        for (final cut in const ['a', 'b'])
          [for (final layer in cutIn(session, cut).layers) layer.id.value],
      ], before);
    });
  });
}
