import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/link_mirror.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️I-73 (유저 2026-10-08): 「콘티레이어 권고한대로 머리만 한벌 ok.
/// 맘에드는생각이야. 겸용컷이랑 같은 느낌이네」 · 「6. 이거만 눈이랑
/// 불투명도조차 링크하도록. 그거마저 머리로서 하나로되도록 통일 프레임
/// 이름으로 링크하는거 자체는 컷 기준으로 내부에서만 이름같으면, 겸용컷에서만
/// 이름같으면 이런식은 지키는게 나을듯」.
///
/// A track's conte rows wear ONE head. Whichever cut's row a head edit is
/// written through — in the cut's own timeline, or on the storyboard's one
/// head under whichever cut is active — it lands on every cut of the track,
/// and one undo puts each row's own back. What a row HOLDS stays its cut's.
void main() {
  Layer conte(String cut, {String name = 'Conte'}) => Layer(
    id: LayerId('$cut-conte'),
    name: name,
    kind: LayerKind.storyboard,
    frames: [Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
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

  /// Track `t1`: cuts `a` and `b` with a conte, `c` with none. Track `t2`:
  /// cut `d` with a conte of its own — another track's, another head.
  Project film({String bName = 'Conte', LayerLinkRegistry? links}) => Project(
    id: const ProjectId('one-head'),
    name: 'One head',
    createdAt: DateTime.utc(2026, 10, 8),
    linkRegistry: links,
    tracks: [
      Track(
        id: const TrackId('t1'),
        name: 'V1',
        cuts: [
          cutOf('a', [cel('a'), conte('a')]),
          cutOf('b', [cel('b'), conte('b', name: bName)]),
          // Four empty frames before it: global 24–27 is a gap.
          cutOf('c', [cel('c')]).copyWith(leadingGapFrames: 4),
        ],
      ),
      Track(
        id: const TrackId('t2'),
        name: 'V2',
        cuts: [
          cutOf('d', [cel('d'), conte('d')]),
        ],
      ),
    ],
  );

  EditorSessionManager sessionOf(Project project) {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    return session;
  }

  Layer row(EditorSessionManager session, String id) {
    for (final track in session.repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        for (final layer in cut.layers) {
          if (layer.id == LayerId(id)) {
            return layer;
          }
        }
      }
    }
    throw StateError('no row $id');
  }

  List<T> heads<T>(EditorSessionManager session, T Function(Layer row) read) =>
      [
        for (final id in const ['a-conte', 'b-conte', 'd-conte'])
          read(row(session, id)),
      ];

  group('where a head edit lands', () {
    test('every cut of the track that has a row at the seat — the row '
        'itself first, another track\'s never', () {
      expect(
        conteHeadTargets(film(), const LayerId('b-conte')),
        [
          (cutId: const CutId('b'), layerId: const LayerId('b-conte')),
          (cutId: const CutId('a'), layerId: const LayerId('a-conte')),
        ],
      );
    });

    test('a row that sits in no conte group has no seat', () {
      expect(conteHeadTargets(film(), const LayerId('a-cel')), isEmpty);
      expect(
        headMirrorTargets(
          film(),
          cutId: const CutId('a'),
          layerId: const LayerId('a-cel'),
        ),
        [(cutId: const CutId('a'), layerId: const LayerId('a-cel'))],
      );
    });

    test('🚨the row\'s cut is FOUND: a head pressed under another cut still '
        'reaches its own track\'s rows', () {
      // The storyboard draws one head for every cut and presses it under
      // whichever cut is active — here `d`, on the other track.
      expect(
        headMirrorTargets(
          film(),
          cutId: const CutId('d'),
          layerId: const LayerId('a-conte'),
        ),
        [
          (cutId: const CutId('a'), layerId: const LayerId('a-conte')),
          (cutId: const CutId('b'), layerId: const LayerId('b-conte')),
        ],
      );
    });

    test('a 겸용 sibling on another track brings that track\'s conte rows '
        'with it — one head is one head', () {
      // `b-conte` and `d-conte` are one linked row; `a-conte` wears
      // `b-conte`'s head, so all three wear one.
      final linked = film(
        links: LayerLinkRegistry(
          groups: [
            LayerLinkGroup(
              id: 'link-1',
              members: const [
                LayerLinkMember(
                  trackId: TrackId('t1'),
                  cutId: CutId('b'),
                  layerId: LayerId('b-conte'),
                ),
                LayerLinkMember(
                  trackId: TrackId('t2'),
                  cutId: CutId('d'),
                  layerId: LayerId('d-conte'),
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        {
          for (final target in headMirrorTargets(
            linked,
            cutId: const CutId('a'),
            layerId: const LayerId('a-conte'),
          ))
            target.layerId.value,
        },
        {'a-conte', 'b-conte', 'd-conte'},
        reason: 'a → b by the seat, b → d by the link',
      );
    });
  });

  /// Each head field, written through the verb its button calls.
  final fields = <String, ({
    void Function(EditorSessionManager session, LayerId row) write,
    Object? Function(Layer row) read,
    Object? written,
  })>{
    'the name': (
      write: (session, row) => session.layerVerbs.renameLayer(row, 'Board'),
      read: (row) => row.name,
      written: 'Board',
    ),
    'the label': (
      write: (session, row) => session.layerMarks.setLayerMark(
        row,
        const LayerMark(process: LayerProcess.layout),
      ),
      read: (row) => row.mark,
      written: const LayerMark(process: LayerProcess.layout),
    ),
    'the blend': (
      write: (session, row) => session.layerSwitches.setBlendModeForLayers({
        row,
      }, LayerBlendMode.multiply),
      read: (row) => row.blendMode,
      written: LayerBlendMode.multiply,
    ),
    'the static opacity': (
      write: (session, row) =>
          session.opacityVerbs.commitLayerOpacity(row, 0.25),
      read: (row) => row.opacity,
      written: 0.25,
    ),
    'the eye': (
      write: (session, row) =>
          session.layerSwitches.toggleLayerVisibility(row),
      read: (row) => row.isVisible,
      written: false,
    ),
    'the fx switch': (
      write: (session, row) => session.effectsAndFx.toggleLayerFx(row),
      read: (row) => row.transformEnabled,
      written: false,
    ),
    // 🗣️I-89-Q22 (유저 2026-10-16): 「콘티행은 그런부분 글로벌이니까 아니면
    // 글로벌시키고 넣고 머리로 하나」. ↩️Each cut's own until then.
    'the sheet switch': (
      write: (session, row) =>
          session.layerSwitches.toggleLayerTimesheet(row),
      read: (row) => row.onTimesheet,
      written: false,
    ),
  };

  for (final MapEntry(key: name, value: field) in fields.entries) {
    // Under the row's own cut, under a cut of the track that has no conte,
    // under another track's cut, and in a GAP: the storyboard's head is
    // pressed wherever the session stands.
    for (final under in const ['b', 'c', 'd', 'a gap']) {
      test('$name, written on cut b\'s row standing on $under, is every '
          'cut\'s on the track — and one undo puts each back', () {
        final session = sessionOf(film());
        if (under == 'a gap') {
          session.selectGlobalFrame(25);
          expect(session.activeCutOrNull, isNull, reason: 'in the gap');
        } else {
          session.selectCut(CutId(under));
        }
        final before = heads(session, field.read);
        expect(
          before[0],
          isNot(field.written),
          reason: 'the premise: the write changes something',
        );
        final steps = session.historyManager.undoCount;

        field.write(session, const LayerId('b-conte'));

        expect(
          heads(session, field.read),
          [field.written, field.written, before[2]],
          reason: 'a and b wear it; track 2\'s conte is another head',
        );
        expect(
          session.historyManager.undoCount,
          steps + 1,
          reason: 'one edit, one step',
        );

        session.undo();
        expect(heads(session, field.read), before);
      });
    }
  }

  // ↩️Two cuts of a track could disagree on a head, and an undo gave each
  // its own back. A file's cuts that disagree open wearing the first cut's
  // (F-343 — the track's structure is laid as the open writes it).
  test('two cuts that disagreed in the file open wearing the first cut\'s '
      'head — and an undo puts back the head they opened with', () {
    final session = sessionOf(film(bName: 'Story'));
    expect(heads(session, (row) => row.name), ['Conte', 'Conte', 'Conte']);

    session.layerVerbs.renameLayer(const LayerId('a-conte'), 'Board');
    expect(heads(session, (row) => row.name), ['Board', 'Board', 'Conte']);

    session.undo();
    expect(heads(session, (row) => row.name), ['Conte', 'Conte', 'Conte']);
  });

  group('the fx chain', () {
    LayerEffect blur() =>
        LayerEffect(id: const EffectId('fx-1'), kind: EffectKind.blur);

    test('its SHAPE is the head\'s: an effect added on one cut\'s row is on '
        'every cut\'s, the same effect', () {
      final session = sessionOf(film());
      session.selectCut(const CutId('a'));

      session.effectsAndFx.updateLayerEffects(const LayerId('a-conte'), [
        blur(),
      ]);

      expect(
        heads(
          session,
          (row) => [for (final effect in row.effects) effect.id.value],
        ),
        [
          ['fx-1'],
          ['fx-1'],
          <String>[],
        ],
      );
    });

    test('⛔its VALUES are each cut\'s: a number changed on one row leaves '
        'the others\'', () {
      final session = sessionOf(film());
      session.selectCut(const CutId('a'));
      session.effectsAndFx.updateLayerEffects(const LayerId('a-conte'), [
        blur(),
      ]);
      final parameter = row(session, 'b-conte').effects.single.parameters.keys
          .first;
      final was = row(session, 'b-conte').effects.single.parameters[parameter]!
          .value;

      session.effectsAndFx.updateLayerEffects(const LayerId('a-conte'), [
        row(session, 'a-conte').effects.single.withParameter(
          parameter,
          EffectParameter(value: was + 7),
        ),
      ]);

      expect(
        row(session, 'a-conte').effects.single.parameters[parameter]!.value,
        was + 7,
        reason: 'LIVENESS: the write landed',
      );
      expect(
        row(session, 'b-conte').effects.single.parameters[parameter]!.value,
        was,
        reason: '「칸 — 칸의 자리와 길이, fx 의 값과 키 — 컷마다」',
      );
    });
  });

  test('⛔the KIND is not the head: one cut\'s conte turned back into a '
      'drawing row leaves the others theirs', () {
    final session = sessionOf(film());
    session.selectCut(const CutId('a'));
    session.selectLayer(const LayerId('a-conte'));

    session.layerSwitches.toggleTargetLayerKind();

    expect(
      heads(session, (row) => row.kind),
      [LayerKind.animation, LayerKind.storyboard, LayerKind.storyboard],
    );
  });

  test('a cut\'s conte is BORN wearing the head its track already wears', () {
    final session = sessionOf(film());
    session.layerVerbs.renameLayer(const LayerId('a-conte'), 'Board');
    session.opacityVerbs.commitLayerOpacity(const LayerId('a-conte'), 0.25);
    session.layerSwitches.toggleLayerVisibility(const LayerId('a-conte'));
    session.layerSwitches.toggleLayerTimesheet(const LayerId('a-conte'));
    session.layerMarks.setLayerMark(
      const LayerId('a-conte'),
      const LayerMark(process: LayerProcess.layout),
    );
    session.effectsAndFx.toggleLayerTransformFx(const LayerId('a-conte'));
    session.effectsAndFx.updateLayerEffects(const LayerId('a-conte'), [
      LayerEffect(id: const EffectId('fx-1'), kind: EffectKind.blur),
    ]);
    final headSwitch = row(session, 'a-conte').transformEnabled;
    expect(
      headSwitch,
      isNot(row(session, 'c-cel').transformEnabled),
      reason: 'fixture: the head\'s transform switch is not the default',
    );

    session.selectCut(const CutId('c'));
    session.layerStack.addLayerOfKind(LayerKind.storyboard);

    final born = storyboardLayerForCut(
      session.repository
          .requireProject()
          .tracks
          .first
          .cuts
          .firstWhere((cut) => cut.id == const CutId('c')),
    )!;
    expect(
      (born.name, born.opacity, born.isVisible, born.mark),
      ('Board', 0.25, false, const LayerMark(process: LayerProcess.layout)),
    );
    expect(born.transformEnabled, headSwitch);
    expect(born.onTimesheet, isFalse, reason: 'the head\'s sheet switch');
    expect(
      [for (final effect in born.effects) effect.id.value],
      ['fx-1'],
      reason: 'the chain\'s shape is the head\'s',
    );
    expect(born.timeline, isNotEmpty, reason: 'and it holds its OWN panel');
  });

  test('🚨a head is renamed from wherever the session stands — under '
      'another cut, and from a gap — by the rail\'s own rename', () {
    for (final gap in const [false, true]) {
      final session = sessionOf(film());
      if (gap) {
        session.selectGlobalFrame(25);
        expect(session.activeCutOrNull, isNull, reason: 'fixture: a gap');
      } else {
        session.selectCut(const CutId('b'));
      }

      // The label's double click renames the rows its press acted on.
      session.layerVerbs.renameRows(const [LayerId('a-conte')], 'Board');

      expect(
        heads(session, (row) => row.name),
        ['Board', 'Board', 'Conte'],
        reason: gap ? 'from a gap' : 'under cut b',
      );
    }
  });

  test('the FIRST conte on a track is born as its kind is', () {
    final bare = sessionOf(
      Project(
        id: const ProjectId('bare'),
        name: 'Bare',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [
              cutOf('a', [cel('a')]),
            ],
          ),
        ],
      ),
    );
    bare.layerStack.addLayerOfKind(LayerKind.storyboard);

    final born = storyboardLayerForCut(bare.requireActiveCut)!;
    expect(
      (born.name, born.opacity, born.isVisible),
      ('Conte', 1.0, true),
    );
  });

  /// 🗣️I-89-Q22 (유저 2026-10-16): 「어니언도 콘티행 기본적으로 버튼
  /// 글로벌이니까 넣음」 — the onion is session state, not the head's
  /// (F-162), and it is ONE for the track's conte rows all the same.
  group('the onion', () {
    List<bool> ghosting(EditorSessionManager session) => [
      for (final id in const ['a-conte', 'b-conte', 'd-conte'])
        session.onionSkin.isLayerOnionSkinEnabled(LayerId(id)),
    ];

    for (final under in const ['b', 'c', 'd', 'a gap']) {
      test('turned on through cut b\'s row standing on $under, every cut\'s '
          'conte on the track ghosts — and off through cut a\'s, none', () {
        final session = sessionOf(film());
        if (under == 'a gap') {
          session.selectGlobalFrame(25);
        } else {
          session.selectCut(CutId(under));
        }

        session.onionSkin.toggleLayerOnionSkin(const LayerId('b-conte'));
        expect(
          ghosting(session),
          [true, true, false],
          reason: 'track 2\'s conte is another head',
        );

        session.onionSkin.toggleLayerOnionSkin(const LayerId('a-conte'));
        expect(ghosting(session), [false, false, false]);
      });
    }

    test('a conte born into a cut afterwards ghosts with the rest', () {
      final session = sessionOf(film());
      session.onionSkin.toggleLayerOnionSkin(const LayerId('a-conte'));
      // Asked once before the birth, as the rail and the canvas ask it of
      // every row they draw: the answer read then is not the one after.
      expect(
        session.onionSkin.isLayerOnionSkinEnabled(const LayerId('b-conte')),
        isTrue,
        reason: '⛔전제',
      );

      session.selectCut(const CutId('c'));
      session.layerStack.addLayerOfKind(LayerKind.storyboard);
      final born = storyboardLayerForCut(session.requireActiveCut)!;

      expect(session.onionSkin.isLayerOnionSkinEnabled(born.id), isTrue);
    });

    test('🚨the canvas ghosts the conte of the cut stood in, turned on '
        'through another cut\'s', () {
      final session = sessionOf(film());
      session.selectCut(const CutId('b'));
      session.selectLayer(const LayerId('b-conte'));
      session.selectFrameIndex(6);
      session.createDrawingAtCurrentFrame();
      expect(
        session.onionSkin.onionSkinCanvasRequests(),
        isEmpty,
        reason: '⛔전제: nothing ghosts yet',
      );

      session.onionSkin.toggleLayerOnionSkin(const LayerId('a-conte'));

      expect(
        [
          for (final request in session.onionSkin.onionSkinCanvasRequests())
            request.frameKey.layerId,
        ],
        [const LayerId('b-conte')],
        reason: 'b\'s panel before the playhead',
      );
    });

    test('⛔a row in no conte group ghosts alone', () {
      final session = sessionOf(film());
      session.onionSkin.toggleLayerOnionSkin(const LayerId('a-cel'));

      expect(
        [
          for (final id in const ['a-cel', 'b-cel'])
            session.onionSkin.isLayerOnionSkinEnabled(LayerId(id)),
        ],
        [true, false],
      );
    });
  });
}
