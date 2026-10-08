import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/convert_to_linked_cut_command.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart'
    show planConvertToLinkedCutCommandInput;
import 'package:anicel/src/services/project_repository.dart';

/// 겸용 변경 unions a row only ONE cut holds into the other. A row that
/// rides a base is nothing without it (`planAddLayerCommandInput`: 「an
/// attach row without its base is not a row at all」) — but the union copied
/// an attach row with its link still naming the base in the cut it came
/// from, and appended it on top of the other cut's stack: a row with no
/// base there, which the rail and the composite both skip (found 2026-10-04,
/// measured, while F-278 was on the bench).
///
/// The copy rides its base's COUNTERPART — the row the base is paired with,
/// or the base's own union copy — and sits where a new attach row is added:
/// the outer end of that base's group, on its own side.
void main() {
  const originId = CutId('origin');
  const targetId = CutId('target');

  Layer cel(String id, String name, {String? folder}) => Layer(
    id: LayerId(id),
    name: name,
    frames: const [],
    timeline: const {},
    folderId: folder == null ? null : LayerId(folder),
  );

  Layer rider(
    String id,
    String name, {
    required String on,
    AttachedPlacement placement = AttachedPlacement.above,
  }) => Layer(
    id: LayerId(id),
    name: name,
    frames: const [],
    timeline: const {},
    onTimesheet: false,
    attachedToLayerId: LayerId(on),
    attachedPlacement: placement,
  );

  /// Two cuts holding [origin] and [target] (bottom row first), converted
  /// origin → target.
  ({ProjectRepository repository, ConvertToLinkedCutCommand convert})
  converted({
    required List<Layer> origin,
    required List<Layer> target,
  }) {
    Cut cut(CutId id, String name, List<Layer> layers) => Cut(
      id: id,
      name: name,
      duration: 4,
      canvasSize: const CanvasSize(width: 8, height: 8),
      layers: layers,
    );
    final repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'T',
            cuts: [
              cut(originId, '1', origin),
              cut(targetId, '2', target),
            ],
          ),
        ],
      ),
    );
    final project = repository.requireProject();
    final cuts = project.tracks.single.cuts;
    final input = planConvertToLinkedCutCommandInput(
      project: project,
      originCut: cuts.first,
      targetCut: cuts.last,
    );
    final convert = ConvertToLinkedCutCommand(
      repository: repository,
      brushFrameStore: BrushFrameStore(),
      originCutId: originId,
      targetCutId: targetId,
      unionLayerIdMap: input.unionLayerIdMap,
      newGroupIdBySource: input.newGroupIdBySource,
      coveringFrameIdBySource: input.coveringFrameIdBySource,
    )..execute();
    return (repository: repository, convert: convert);
  }

  List<Layer> rowsOf(ProjectRepository repository, CutId cutId) => repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == cutId)
      .layers;

  /// The row of [cutId] linked to ([fromCut], [id]).
  Layer counterpart(
    ProjectRepository repository,
    CutId fromCut,
    String id,
    CutId cutId,
  ) {
    final group = repository.requireProject().linkRegistry.groupOf(
      cutId: fromCut,
      layerId: LayerId(id),
    )!;
    final there = group.members.firstWhere((member) => member.cutId == cutId);
    return rowsOf(
      repository,
      cutId,
    ).firstWhere((layer) => layer.id == there.layerId);
  }

  List<String> names(List<Layer> rows) => [for (final row in rows) row.name];

  test('an attach row only the origin holds rides the TARGET\'s base, right '
      'above it — and undo takes it back out', () {
    final (:repository, :convert) = converted(
      origin: [cel('a', 'A'), rider('a+1', 'A+1', on: 'a'), cel('b', 'B')],
      target: [cel('ta', 'A'), cel('tb', 'B')],
    );

    final target = rowsOf(repository, targetId);
    final copy = counterpart(repository, originId, 'a+1', targetId);
    expect(copy.attachedToLayerId, const LayerId('ta'));
    expect(
      attachedBaseOf(copy, target)?.name,
      'A',
      reason: 'a row with its base in the cut it lives in',
    );
    expect(names(target), ['A', 'A+1', 'B'], reason: 'in its base\'s group');

    convert.undo();
    expect(names(rowsOf(repository, targetId)), ['A', 'B']);
  });

  test('…and one only the TARGET holds rides the origin\'s base, below it '
      'when it sits below', () {
    final (:repository, convert: _) = converted(
      origin: [cel('x', 'X'), cel('a', 'A')],
      target: [
        cel('tx', 'X'),
        rider('ta-1', 'A-1', on: 'ta', placement: AttachedPlacement.below),
        cel('ta', 'A'),
      ],
    );

    final origin = rowsOf(repository, originId);
    final copy = counterpart(repository, targetId, 'ta-1', originId);
    expect(copy.attachedToLayerId, const LayerId('a'));
    expect(names(origin), ['X', 'A-1', 'A']);
  });

  test('a base only one cut holds takes its attach rows with it: they ride '
      'the base\'s own copy, in the order they stood', () {
    final (:repository, convert: _) = converted(
      origin: [
        cel('a', 'A'),
        rider('c-2', 'C-2', on: 'c', placement: AttachedPlacement.below),
        rider('c-1', 'C-1', on: 'c', placement: AttachedPlacement.below),
        cel('c', 'C'),
        rider('c+1', 'C+1', on: 'c'),
        rider('c+2', 'C+2', on: 'c'),
      ],
      target: [cel('ta', 'A')],
    );

    final target = rowsOf(repository, targetId);
    final base = counterpart(repository, originId, 'c', targetId);
    expect(names(target), ['A', 'C-2', 'C-1', 'C', 'C+1', 'C+2']);
    for (final id in ['c-2', 'c-1', 'c+1', 'c+2']) {
      expect(
        counterpart(repository, originId, id, targetId).attachedToLayerId,
        base.id,
        reason: id,
      );
    }
    expect(
      names(attachedGroupSlice(base.id, target)),
      ['C-2', 'C-1', 'C', 'C+1', 'C+2'],
      reason: 'one group, contiguous',
    );
  });

  test('new rows join the rows the group already has, at its outer end — '
      'where a new attach row is added', () {
    final (:repository, convert: _) = converted(
      origin: [
        cel('a', 'A'),
        rider('a+1', 'A+1', on: 'a'),
        rider('a+2', 'A+2', on: 'a'),
      ],
      target: [cel('ta', 'A'), rider('ta+1', 'A+1', on: 'ta'), cel('tb', 'B')],
    );

    expect(names(rowsOf(repository, targetId)), ['A', 'A+1', 'A+2', 'B']);
    expect(names(rowsOf(repository, originId)), ['A', 'A+1', 'A+2', 'B']);
  });

  test('the copy takes its base\'s folder there — a row with none inside a '
      'folder\'s run would break the run', () {
    final (:repository, convert: _) = converted(
      origin: [cel('a', 'A'), rider('a+1', 'A+1', on: 'a')],
      // A folder row sits directly above its members' run.
      target: [
        cel('ta', 'A', folder: 'tf'),
        cel('tz', 'Z', folder: 'tf'),
        createFolderLayer(id: const LayerId('tf'), name: 'F'),
      ],
    );

    final target = rowsOf(repository, targetId);
    final copy = counterpart(repository, originId, 'a+1', targetId);
    expect(copy.folderId, const LayerId('tf'));
    expect(names(target), ['A', 'A+1', 'Z', 'F']);
    expect(folderStructureProblem(target), isNull);
  });

  // The two halves of the union ran as one loop written twice until this
  // round; these two say what each way round still does.
  test('the side a row comes from is canonical for it — it holds the '
      'pixels — whichever cut that is', () {
    final (:repository, convert: _) = converted(
      origin: [cel('a', 'A'), cel('o', 'OnlyHere')],
      target: [cel('ta', 'A'), cel('t', 'OnlyThere')],
    );
    final registry = repository.requireProject().linkRegistry;

    expect(
      registry.groupOf(cutId: originId, layerId: const LayerId('o'))!.canonical,
      isA<LayerLinkMember>()
          .having((member) => member.cutId, 'cut', originId)
          .having((member) => member.layerId, 'row', const LayerId('o')),
    );
    expect(
      registry.groupOf(cutId: targetId, layerId: const LayerId('t'))!.canonical,
      isA<LayerLinkMember>()
          .having((member) => member.cutId, 'cut', targetId)
          .having((member) => member.layerId, 'row', const LayerId('t')),
    );
  });

  test('a row that rides nothing still lands on top, as it always did', () {
    final (:repository, convert: _) = converted(
      origin: [cel('c', 'C'), cel('a', 'A')],
      target: [cel('ta', 'A'), cel('tb', 'B')],
    );

    expect(names(rowsOf(repository, targetId)), ['A', 'B', 'C']);
  });
}
