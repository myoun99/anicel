import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_cells_agreement.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show buildAnicelProjectJsonBytes, decodeAnicelProjectDocument;
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/row_folds.dart';
import '../../helpers/a_folder_made_by_hand.dart';

/// 🚨F-360 (유저 2026-10-14): 「어태치레이어 분명 접은채로 저장했는데
/// 다시열면 펼쳐져있음. fx나 폴더나 이런 접음/펼침상태가 기록이 안되는건지?
/// 제대로 기록되도록」.
///
/// How a row is folded and twirled is the ROW'S, as a folder's fold always
/// was: `Layer.collapsed` folds a folder's members and a base's attach
/// group alike, `Layer.lanesExpanded` is its property-lane twirl and
/// `Layer.expandedLaneGroups` the lane groups open inside it. The file
/// keeps them, one command writes them on every row of the row's head, and
/// the rail reads them off the document (`RailView.readFolds`).
///
/// ↩️The attach fold and both twirls were the rail's session view —
/// `RailView`'s three sets — and every reopen opened them all back up.
void main() {
  final transform = transformGroupHeaderLane.laneId;

  EditorSessionManager sessionOn(Project project) {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    return session;
  }

  Layer rowOf(EditorSessionManager session, LayerId id) =>
      requireLayerAnywhere(session.repository.requireProject(), id);

  group('the file keeps them', () {
    test('🚨what was folded and twirled when the file was saved is folded '
        'and twirled when it opens — a folder, an attach group, a row\'s '
        'lanes, a group inside them, the camera\'s lanes', () {
      final s = sessionOn(createDefaultProject());
      final base = s.layers
          .firstWhere((layer) => layer.kind == LayerKind.animation)
          .id;
      final camera = s.layers
          .firstWhere((layer) => layer.kind == LayerKind.camera)
          .id;
      LayerId added() {
        final before = {for (final layer in s.layers) layer.id};
        s.layerStack.addLayerOfKind(LayerKind.animation);
        return s.layers.firstWhere((layer) => !before.contains(layer.id)).id;
      }

      final plain = added();
      final filed = added();
      s.selectLayer(filed);
      groupTheActiveRowIntoAFolder(s);
      final folder = s.requireActiveCut.layers.folderLayers.single.id;
      s.selectLayer(base);
      s.folders.addAttachedLayer(AttachedPlacement.below);

      SessionRowButtonPresses(s)
        ..toggleGroupFold(folder)
        ..toggleGroupFold(base)
        ..toggleLanes(plain)
        ..toggleLaneGroup(laneGroupKey(plain, transform))
        ..toggleLanes(camera);

      final opened = sessionOn(
        decodeAnicelProjectDocument(
          buildAnicelProjectJsonBytes(project: s.repository.requireProject()),
        ).project,
      );

      for (final (name, session) in [('saved', s), ('opened', opened)]) {
        expect(
          session.railView.collapsedAttachBaseIds.value,
          {base},
          reason: '$name: 「어태치레이어 분명 접은채로 저장했는데 다시열면 '
              '펼쳐져있음」',
        );
        expect(session.railView.expandedLaneLayerIds.value, {
          plain,
          camera,
        }, reason: '$name: the fx lanes — 「fx나」');
        expect(session.railView.expandedLaneGroupKeys.value, {
          laneGroupKey(plain, transform),
        }, reason: name);
        expect(
          rowOf(session, folder).collapsed,
          isTrue,
          reason: '$name: 「폴더나」 — the one law it already kept',
        );
      }
    });

    test('a fold or a twirl is no cell of its row: the row\'s tiles keep, '
        'and the row is still another row', () {
      final row = Layer(
        id: const LayerId('row'),
        name: 'row',
        frames: [
          Frame(id: const FrameId('cel'), duration: 1, strokes: const []),
        ],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('cel'), length: 3),
        },
      );

      for (final (name, folded) in [
        ('folded', row.copyWith(collapsed: true)),
        ('twirled', row.copyWith(lanesExpanded: true)),
        ('a group open', row.copyWith(expandedLaneGroups: {transform})),
      ]) {
        expect(
          firstCellThatMayDiffer(row, folded),
          isNull,
          reason: '$name: 🚨F-244 — a twirl baked every tile of the row again',
        );
        expect(
          folded,
          isNot(row),
          reason: '$name: the file keeps it, so it is an edit of the row',
        );
      }
    });
  });

  group('a press writes them', () {
    /// A cel and its 겸용 use in a second cut — one row seen from two cuts.
    ({EditorSessionManager s, LayerId cel, LayerId twin}) linkedCel() {
      final s = sessionOn(createDefaultProject());
      final origin = s.requireActiveCut.id;
      final cel = s.layers
          .firstWhere((layer) => layer.kind == LayerKind.animation)
          .id;
      s.cutVerbs.createLinkedCutFromActiveCut();
      final twin = s.repository
          .requireProject()
          .linkRegistry
          .groupOf(cutId: origin, layerId: cel)!
          .members
          .firstWhere((member) => member.cutId != origin)
          .layerId;
      return (s: s, cel: cel, twin: twin);
    }

    test('🚨a lane group\'s twirl is ONE undo step, and what it writes and '
        'puts back is that group\'s — on every use of the row, whatever '
        'else each has open', () {
      final (:s, :cel, :twin) = linkedCel();
      // Two uses that disagree about the rest — as a file may hold them.
      setRowFolds(s, cel, expandedLaneGroups: {'fx-group:a'});
      setRowFolds(s, twin, expandedLaneGroups: {'fx-group:b'});
      final depth = s.historyManager.undoCount;

      SessionRowButtonPresses(
        s,
      ).toggleLaneGroup(laneGroupKey(twin, transform));

      expect(rowOf(s, cel).expandedLaneGroups, {'fx-group:a', transform});
      expect(rowOf(s, twin).expandedLaneGroups, {'fx-group:b', transform});
      expect(
        s.historyManager.undoCount,
        depth + 1,
        reason: '↩️the one fold that did not undo',
      );

      s.undo();

      expect(rowOf(s, cel).expandedLaneGroups, {'fx-group:a'});
      expect(rowOf(s, twin).expandedLaneGroups, {'fx-group:b'});
    });

    test('🚨a 겸용 change hands the origin\'s folds and twirls to the row '
        'that joins it — its fold, its lanes, its groups', () {
      Layer drawing(
        String id, {
        required String name,
        String? ridesOn,
        bool collapsed = false,
        bool lanesExpanded = false,
        Set<String> groups = const {},
      }) => Layer(
        id: LayerId(id),
        name: name,
        frames: const [],
        timeline: const {},
        attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
        attachedPlacement: AttachedPlacement.below,
        collapsed: collapsed,
        lanesExpanded: lanesExpanded,
        expandedLaneGroups: groups,
      );
      Cut cut(String id, List<Layer> layers) => Cut(
        id: CutId(id),
        name: id,
        duration: 12,
        canvasSize: const CanvasSize(width: 640, height: 360),
        layers: layers,
      );
      final s = sessionOn(
        Project(
          id: const ProjectId('convert'),
          name: 'Convert',
          createdAt: DateTime.utc(2026, 10, 14),
          tracks: [
            Track(
              id: const TrackId('t1'),
              name: 'V1',
              cuts: [
                cut('o', [
                  drawing('o-b-1', name: 'B-1', ridesOn: 'o-b'),
                  drawing('o-b', name: 'B', collapsed: true),
                  drawing(
                    'o-p',
                    name: 'P',
                    lanesExpanded: true,
                    groups: {transform},
                  ),
                ]),
                cut('t', [
                  drawing('t-b-1', name: 'B-1', ridesOn: 't-b'),
                  drawing('t-b', name: 'B'),
                  drawing('t-p', name: 'P'),
                ]),
              ],
            ),
          ],
        ),
      );
      expect(s.requireActiveCut.id, const CutId('o'), reason: '⛔전제');

      s.cutVerbs.convertActiveCutToLinked(const CutId('t'));

      expect(
        s.repository.requireProject().linkRegistry.isLinked(
          cutId: const CutId('t'),
          layerId: const LayerId('t-p'),
        ),
        isTrue,
        reason: '⛔전제: the rows paired by name',
      );
      expect(rowOf(s, const LayerId('t-b')).collapsed, isTrue);
      expect(rowOf(s, const LayerId('t-p')).lanesExpanded, isTrue);
      expect(rowOf(s, const LayerId('t-p')).expandedLaneGroups, {transform});
    });
  });

  // 🗣️I-73 (유저 2026-10-08): 「콘티행도 동일하게 … 어태치 접기펼치기버튼등
  // 동일하게 할수있는거 다 넣는거 잊지말고」 — the rows at one seat of a
  // track's conte groups wear one head, their fold among it.
  test('🚨the walk that opens what hides the row you are taken to opens it '
      'on every row of its head — the conte at its seat in the track\'s '
      'other cuts', () {
    Layer conteRow(String id, {String? ridesOn}) => Layer(
      id: LayerId(id),
      name: id,
      kind: LayerKind.storyboard,
      attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
      attachedPlacement: AttachedPlacement.below,
      // The file folded the head: every conte of the track.
      collapsed: ridesOn == null,
      frames: [
        Frame(id: FrameId('$id-cel'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: TimelineExposure.drawing(FrameId('$id-cel'), length: 12),
      },
    );
    Cut conteCut(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 12,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: [
        conteRow('$id-under', ridesOn: '$id-conte'),
        conteRow('$id-conte'),
      ],
    );
    final s = sessionOn(
      Project(
        id: const ProjectId('conte-head'),
        name: 'Conte head',
        createdAt: DateTime.utc(2026, 10, 14),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [conteCut('a'), conteCut('b')],
          ),
        ],
      ),
    );
    const heads = [LayerId('a-conte'), LayerId('b-conte')];
    expect(
      s.railView.collapsedAttachBaseIds.value,
      heads.toSet(),
      reason: '⛔전제: the file folded the head',
    );

    s.standing.standOn(
      (cut: const CutId('a'), layer: const LayerId('a-under'), frame: 0),
    );

    expect(s.activeLayerId, const LayerId('a-under'));
    expect([for (final head in heads) rowOf(s, head).collapsed], [
      false,
      false,
    ], reason: 'one head: open in cut a, open in cut b');
    expect(s.railView.collapsedAttachBaseIds.value, isEmpty);
  });
}
