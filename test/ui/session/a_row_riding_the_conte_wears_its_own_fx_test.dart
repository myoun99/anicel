import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show chainWornBy, layerPlacementAt;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🗣️I-99 (유저 2026-10-28) — Q1 「콘티의 어태치 행만」, Q2 「애초에 기준이랑
/// 어태치랑 fx 완전독립. 별개 레이어처럼 fx작동」.
///
/// A row riding the conte authors its own fx — transform, animated opacity,
/// effects — and wears none of the conte's. Every other attach row, and
/// every 공정 organizer folder, still wears its base's (R9): the folder's
/// 「효과 추가」 was the hole the old gate left open.
void main() {
  const canvas = CanvasSize(width: 640, height: 360);
  const conteBlur = EffectId('conte-blur');
  const riderHue = EffectId('rider-hue');
  const baseBlur = EffectId('a-blur');

  TransformTrack positionAt(int frame, CanvasPoint value) =>
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(frame, value),
      );

  TransformTrack opacityAt0(double value) => TransformTrack.empty().copyWith(
    opacity: PropertyTrack<double>.empty().withKey(0, value),
  );

  /// An effect of [kind] whose [parameter] has moved off its default — one
  /// that filters, so a resolved chain keeps it.
  LayerEffect moved(EffectId id, EffectKind kind, String parameter) =>
      LayerEffect(
        id: id,
        kind: kind,
        parameters: {
          parameter: EffectParameter(
            track: PropertyTrack<double>.empty().withKey(0, 9),
          ),
        },
      );

  /// Two one-frame drawings, at 0 and at 1 — what an onion ghosts.
  ({List<Frame> frames, Map<int, TimelineExposure> timeline}) twoCels(
    String row,
  ) => (
    frames: [
      for (final at in [0, 1])
        Frame(id: FrameId('$row-$at'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final at in [0, 1])
        at: TimelineExposure.drawing(FrameId('$row-$at'), length: 1),
    },
  );

  Layer conte({TransformTrack? transform}) => Layer(
    id: const LayerId('conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    frames: [
      Frame(id: const FrameId('panel'), duration: 12, strokes: const []),
    ],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('panel'), length: 12),
    },
    transformTrack: transform ?? positionAt(0, CanvasPoint(x: 400, y: 200)),
    effects: [moved(conteBlur, EffectKind.blur, 'blurX')],
  );

  Layer rider({
    TransformTrack? transform,
    List<LayerEffect>? effects,
    LayerId? folderId,
  }) {
    final cels = twoCels('rider');
    return Layer(
      id: const LayerId('rider'),
      name: 'Over',
      kind: LayerKind.storyboard,
      attachedToLayerId: const LayerId('conte'),
      attachedPlacement: AttachedPlacement.above,
      attachedMode: AttachedMode.free,
      folderId: folderId,
      frames: cels.frames,
      timeline: cels.timeline,
      transformTrack: transform,
      effects: effects ?? [moved(riderHue, EffectKind.hueSaturation, 'hue')],
    );
  }

  Layer base() {
    final cels = twoCels('a');
    return Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: cels.frames,
      timeline: cels.timeline,
      transformTrack: positionAt(0, CanvasPoint(x: 400, y: 200)),
      effects: [moved(baseBlur, EffectKind.blur, 'blurX')],
    );
  }

  /// An attach row of a DRAWING base, filed in its 공정 folder — with a key
  /// of its own the file keeps but nothing shows (it wears its base's).
  Layer attach() {
    final cels = twoCels('a1');
    return Layer(
      id: const LayerId('a1'),
      name: 'A+1',
      attachedToLayerId: const LayerId('a'),
      attachedPlacement: AttachedPlacement.above,
      attachedMode: AttachedMode.free,
      folderId: const LayerId('proc'),
      frames: cels.frames,
      timeline: cels.timeline,
      transformTrack: positionAt(2, CanvasPoint(x: 100, y: 100)),
    );
  }

  final organizer = createFolderLayer(
    id: const LayerId('proc'),
    name: '[연출]',
  );

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('c1'),
    name: '1',
    duration: 12,
    canvasSize: canvas,
    layers: layers,
  );

  group('the law', () {
    test('a row riding the conte carries its own fx; every other attach row '
        'carries its base\'s', () {
      final layers = [base(), attach(), organizer, conte(), rider()];
      expect(fxCarrierOf(layers[4], layers)?.id, const LayerId('rider'));
      expect(fxCarrierOf(layers[1], layers)?.id, const LayerId('a'));
      expect(fxCarrierOf(layers[0], layers)?.id, const LayerId('a'));
      expect(
        fxCarrierOf(layers[4], [layers[4]]),
        isNull,
        reason: 'a rider whose conte is gone dangles like any attach row',
      );

      expect(attachRowWearsBaseComposite(layers[4], layers), isFalse);
      expect(attachRowWearsBaseComposite(layers[1], layers), isTrue);
      expect(
        attachRowWearsBaseComposite(organizer, layers),
        isTrue,
        reason: 'Q1: the folders keep wearing their base\'s',
      );
    });

    test('a 공정 folder of the conte wears its base\'s too — only the rows '
        'are the conte\'s exception', () {
      final filed = rider(folderId: const LayerId('proc'));
      final layers = [conte(), filed, organizer];
      expect(attachRowWearsBaseComposite(filed, layers), isFalse);
      expect(attachRowWearsBaseComposite(organizer, layers), isTrue);
    });
  });

  group('the composite lays the rider by its own fx', () {
    test('none of the conte\'s pose or chain reaches it', () {
      final bare = rider(effects: const []);
      final cut = cutOf([conte(), bare]);
      expect(
        layerPlacementAt(cut: cut, layer: cut.layers.first, frameIndex: 0),
        isNotNull,
        reason: '⛔premise: the conte is posed',
      );
      expect(
        layerPlacementAt(cut: cut, layer: bare, frameIndex: 0),
        isNull,
        reason: 'the rider has no pose of its own — where the conte is moved '
            'does not move it',
      );
      expect(chainWornBy(cut, bare), isEmpty);
      expect(
        chainWornBy(cut, rider()).map((effect) => effect.id),
        [riderHue],
      );
    });

    test('an attach row of a drawing base still stands and filters as its '
        'base does', () {
      final cut = cutOf([base(), attach(), organizer]);
      expect(
        layerPlacementAt(cut: cut, layer: cut.layers[1], frameIndex: 0),
        layerPlacementAt(cut: cut, layer: cut.layers[0], frameIndex: 0),
      );
      expect(
        chainWornBy(cut, cut.layers[1]).map((effect) => effect.id),
        [baseBlur],
      );
    });
  });

  group('the session works the rider\'s fx as its own', () {
    EditorSessionManager sessionOf(List<Layer> layers) {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('i-99'),
          name: 'I-99',
          createdAt: DateTime.utc(2026, 10, 28),
          tracks: [
            Track(
              id: const TrackId('t1'),
              name: 'V1',
              cuts: [cutOf(layers)],
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      return session;
    }

    EditorSessionManager standingOn(String layer, {List<Layer>? layers}) {
      final session = sessionOf(
        layers ??
            [
              base(),
              attach(),
              organizer,
              conte(),
              rider(transform: positionAt(2, CanvasPoint(x: 100, y: 100))),
            ],
      );
      session.selectCut(const CutId('c1'));
      session.selectLayer(LayerId(layer));
      return session;
    }

    Layer rowOf(EditorSessionManager session, String id) =>
        session.requireActiveCut.layers.byId(LayerId(id))!;

    test('「효과 추가」 is open on the rider and closed on every row that '
        'wears its base\'s — the 공정 folder among them', () {
      final onRider = standingOn('rider');
      expect(
        onRider.effectsAndFx.canAddEffectToActiveLayer(EffectKind.blur),
        isTrue,
      );
      onRider.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      expect(rowOf(onRider, 'rider').effects.map((effect) => effect.kind), [
        EffectKind.hueSaturation,
        EffectKind.blur,
      ]);
      expect(
        rowOf(onRider, 'conte').effects.map((effect) => effect.id),
        [conteBlur],
        reason: 'the conte\'s chain is its own, untouched',
      );

      for (final wearer in ['proc', 'a1']) {
        final session = standingOn(wearer);
        for (final kind in EffectKind.values) {
          expect(
            session.effectsAndFx.canAddEffectToActiveLayer(kind),
            isFalse,
            reason: '$wearer wears its base\'s fx: $kind',
          );
        }
      }
    });

    test('the lane verbs work the rider\'s keys and refuse a row that wears '
        'its base\'s', () {
      TimelineLaneSelection positionOf(String row) => TimelineLaneSelection(
        layerId: LayerId(row),
        laneId: 'position',
        startIndex: 2,
        endIndexExclusive: 3,
      );
      for (final (row, works) in [('rider', true), ('a1', false)]) {
        final session = standingOn(row);
        session.laneRangeSelection.value = positionOf(row);
        expect(
          session.laneVerbs.laneVerbRangeHasSomethingToDelete,
          works,
          reason: '$row: the key under the range',
        );
        expect(session.laneMove.beginLaneRangeMoveDrag(), works);
        session.laneMove.cancelLaneRangeMoveDrag();

        session.frameRangeSelection.value = TimelineFrameRangeSelection(
          layerId: LayerId(row),
          startIndex: 0,
          endIndexExclusive: 4,
          rows: [
            LayerRowAddress(LayerId(row)),
            LaneRowAddress(LayerId(row), 'position'),
          ],
        );
        expect(
          session.laneVerbs.bandLanesRiding().map((lane) => lane.row.id),
          works ? [LayerId(row)] : isEmpty,
          reason: '$row: a band over its lane carries its keys',
        );
        session.frameRangeSelection.value = null;

        expect(
          session.laneVerbs.removeLaneKeysForSelection(positionOf(row)),
          works,
        );
        expect(
          rowOf(session, row).transformTrack.position.keyAt(2) == null,
          works,
          reason: '$row: the key goes only where the verb works',
        );
      }
    });

    test('the rider\'s groups reset and its effect headers delete as its own',
        () {
      for (final (row, works) in [('rider', true), ('a1', false)]) {
        final session = standingOn(row);
        session.selectFrameIndex(2);
        session.laneRangeSelection.value = null;
        expect(
          session.laneVerbs.resetLaneGroup(
            LayerId(row),
            transformGroupHeaderLane.laneId,
          ),
          works,
          reason: '$row: the transform group resets at the playhead',
        );
      }

      final session = standingOn('rider');
      session.laneRangeSelection.value = TimelineLaneSelection(
        layerId: const LayerId('rider'),
        laneId: effectGroupLaneId(riderHue),
        startIndex: 0,
        endIndexExclusive: 1,
      );
      expect(
        session.laneVerbs.laneVerbRangeHasSomethingToDelete,
        isTrue,
        reason: 'a range over the rider\'s fx header names its effect',
      );
    });

    test('the rider\'s animated opacity is its own, not the conte\'s — an '
        'attach row of a drawing base shows its base\'s', () {
      final session = standingOn(
        'rider',
        layers: [
          base().copyWith(transformTrack: opacityAt0(0.3)),
          attach().copyWith(transformTrack: opacityAt0(0.8)),
          organizer,
          conte(transform: opacityAt0(0.2)),
          rider(transform: opacityAt0(0.5)),
        ],
      );
      final layers = session.requireActiveCut.layers;
      double shown(String row) => session.opacityVerbs.stackLayerOpacity(
        rowOf(session, row),
        layers,
        0,
      );
      expect(shown('rider'), closeTo(0.5, 1e-9));
      expect(shown('a1'), closeTo(0.3, 1e-9));
    });

    test('a ghost wears the chain the composite lays its row with', () {
      final session = standingOn('rider');
      session.selectFrameIndex(1);
      for (final row in ['rider', 'a1']) {
        session.onionSkin.toggleLayerOnionSkin(LayerId(row));
      }
      final ghosts = session.onionSkin.ghostsAt(session.requireActiveCut, 1);
      List<EffectKind> ghostOf(String row) => [
        for (final ghost in ghosts)
          if (ghost.frameKey.layerId == LayerId(row))
            for (final effect in ghost.effects) effect.kind,
      ];
      expect(
        ghostOf('rider'),
        [EffectKind.hueSaturation],
        reason: 'its own chain — not the conte\'s blur',
      );
      expect(
        ghostOf('a1'),
        [EffectKind.blur],
        reason: 'the base\'s chain, which a1 wears — it has none of its own',
      );
    });
  });
}
