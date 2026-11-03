import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/cut_sync.dart';
import '../../models/cut_sync_alignment.dart' show syncedCopy;
import '../../models/layer_id.dart';
import '../../models/layer_link_join.dart';
import '../../models/layer_link_registry.dart';
import '../editing/editing_session_state.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'cut_insertion.dart';
import 'transitions_ride_the_cuts.dart';

/// 동기컷 생성 (I-150-Q3): [sourceCutId] made a cut of the timeline open as
/// well — the SAME cut ([CutSync]), standing where [landing] says, named
/// [newName].
///
/// 🗣️유저 2026-11-03 (I-150-Q3): 「다른 타임라인끼리는 단순 겸용컷
/// 작동안하게 … 이 동작을 겸용컷이라기보다 새 시스템으로 … 이는 겸용컷이면서
/// 추가로 타임라인까지 완벽동기화된 실질 같은컷 취급」. So the new cut is the
/// source's content under ids of its own ([syncedCopy], the law each write
/// then keeps it one by): every row of a kind that links linked to the row
/// it copies — the pictures are one — and the two of them a sync, joining
/// the source's when it has one. Unlike a 겸용 cut ([CreateLinkedCutCommand])
/// nothing starts over: the length, the timing, the camera's keys and the
/// direction rows are the source's.
///
/// It takes its room as every cut landing in front of others does — THE one
/// insertion ([projectWithCutInserted]) — in this command's own write, so
/// the table lands with the cut it names. One undo step.
class CreateSyncedCutCommand implements Command {
  CreateSyncedCutCommand({
    required this.repository,
    required this.editingSession,
    required this.sourceCutId,
    required this.newCutId,
    required this.newName,
    required this.layerIdMap,
    required this.newGroupIdBySource,
    required this.newSyncId,
    required this.landing,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final CutId sourceCutId;
  final CutId newCutId;
  final String newName;

  /// EVERY row of the source → its row in the new cut.
  final Map<LayerId, LayerId> layerIdMap;

  /// Planned registry group ids for the source rows that link and are
  /// linked to nothing yet.
  final Map<LayerId, String> newGroupIdBySource;

  /// The sync's id when the source is in none yet.
  final String newSyncId;

  /// Where the new cut lands — in the timeline open.
  final CutLanding landing;

  CutId? _previousActiveCutId;
  LayerLinkRegistry? _registryBefore;
  Map<CutId, int> _gapsBefore = const {};
  bool _hasExecuted = false;

  @override
  String get description => 'Create synced cut $newName';

  late final TransitionsRideTheCuts _ride = TransitionsRideTheCuts(repository);

  @override
  void execute() {
    _previousActiveCutId = editingSession.activeCutId;
    void insert() => repository.updateProject((project) {
      final position = requireCutPosition(project, sourceCutId);
      final source = position.cut;
      final before = project.linkRegistry;
      _registryBefore = before;
      var groups = before.groups;
      for (final row in source.layers) {
        if (!row.kind.linksIntoLinkedCut) {
          continue;
        }
        groups = linkGroupsJoined(
          groups,
          origin: LayerLinkMember(
            trackId: position.trackId,
            cutId: sourceCutId,
            layerId: row.id,
          ),
          joiner: LayerLinkMember(
            trackId: landing.trackId,
            cutId: newCutId,
            layerId: _rowFor(row.id),
          ),
          plannedGroupId: newGroupIdBySource[row.id],
        );
      }
      final made = syncedCopy(
        source,
        onto: Cut(
          id: newCutId,
          name: newName,
          layers: const [],
          duration: source.duration,
          canvasSize: source.canvasSize,
          leadingGapFrames: landing.leadingGapFrames,
        ),
        rowOf: layerIdMap,
      );
      final inserted = projectWithCutInserted(
        project,
        trackId: landing.trackId,
        cut: made,
        index: landing.index,
      );
      _gapsBefore = inserted.gapsBefore;
      return inserted.project.copyWith(
        linkRegistry: before.copyWith(
          groups: groups,
          syncs: _syncsJoined(before.syncs),
        ),
      );
    });
    _ride.carry(insert);
    editingSession.setActiveCutId(newCutId);
    _hasExecuted = true;
  }

  /// [syncs] with the new cut one of the source's — a sync of the two when
  /// the source is in none.
  List<CutSync> _syncsJoined(List<CutSync> syncs) {
    final at = syncs.indexWhere((sync) => sync.cuts.contains(sourceCutId));
    if (at < 0) {
      return [
        ...syncs,
        CutSync(id: newSyncId, cuts: [sourceCutId, newCutId]),
      ];
    }
    return [
      for (final (index, sync) in syncs.indexed)
        if (index == at)
          sync.copyWith(cuts: [...sync.cuts, newCutId])
        else
          sync,
    ];
  }

  @override
  void undo() {
    final registryBefore = _registryBefore;
    if (!_hasExecuted || registryBefore == null) {
      throw StateError('Command has not been executed.');
    }
    void remove() => repository.updateProject(
      (project) => projectWithCutTakenOut(
        project,
        cutId: newCutId,
        gapsBefore: _gapsBefore,
      ).copyWith(linkRegistry: registryBefore),
    );
    _ride.carryBack(remove);
    editingSession.setActiveCutId(_previousActiveCutId);
  }

  LayerId _rowFor(LayerId sourceId) =>
      layerIdMap[sourceId] ??
      (throw StateError('No planned row for $sourceId'));
}
