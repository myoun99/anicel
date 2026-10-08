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
import 'package:anicel/src/ui/editor_session_manager.dart';

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
  }) => Layer(
    id: LayerId('$cut-$suffix'),
    name: name ?? (placement == AttachedPlacement.above ? 'Over' : 'Under'),
    kind: LayerKind.storyboard,
    opacity: opacity,
    blendMode: blendMode,
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
    });

    test('🚨wears the head of the seat it lands on, and a cut that already '
        'holds that seat is given no second row', () {
      final session = sessionOf([
        cutOf('a', [cel('a'), conte('a')]),
        cutOf('b', [
          cel('b'),
          conte('b'),
          rider(
            'b',
            'over',
            placement: AttachedPlacement.above,
            name: 'Shadow',
            opacity: 0.5,
            blendMode: LayerBlendMode.multiply,
          ),
        ]),
      ]);
      standOn(session, 'a', 'a-conte');

      session.folders.addAttachedLayer(AttachedPlacement.above);

      final born = seatRow(session, 'a', 1);
      expect(
        (born.name, born.opacity, born.blendMode),
        ('Shadow', 0.5, LayerBlendMode.multiply),
      );
      expect(seats(session, 'b'), ['1:Shadow', '0:Conte']);
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

  group('a conte born into a track whose contes carry attach rows', () {
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
  });
}
