// A ROW PLACEMENT DOES NOT MIRROR ONTO A LINKED SIBLING WHOSE FOLDERS HAVE
// DIVERGED: WHEN THE FOLDER A ROW JOINED HAS NO COUNTERPART THERE, THE
// MIRROR STANDS DOWN INSTEAD OF GUESSING.
//
// A survivor of the mutation campaign (2026-09-03): the stand-down flag in
// layerPlacementCommands (`translatable = false`) became `true`, so a
// diverged sibling still received a placement command built from a
// half-translated folder map. This pin builds the divergence — a linked
// cut, then a folder created on the source cut alone — and counts the
// commands one move produces.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/create_folder_command.dart';
import 'package:anicel/src/services/commands/create_linked_cut_command.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  const linkedCutId = CutId('linked-cut');
  const linkedLayerId = LayerId('linked-layer');
  const folderId = LayerId('folder-on-source-only');

  late ProjectRepository repository;
  late EditingSessionState editingSession;
  late Cut source;
  late Layer sourceLayer;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    source = repository.requireProject().tracks.first.cuts.first;
    sourceLayer = source.layers.first;
    editingSession = EditingSessionState(activeCutId: source.id);
    CreateLinkedCutCommand(
      repository: repository,
      editingSession: editingSession,
      sourceCutId: source.id,
      newCutId: linkedCutId,
      newName: 'Linked',
      layerIdMap: {sourceLayer.id: linkedLayerId},
      newGroupIdBySource: {sourceLayer.id: 'link-group'},
      // F-99: this case gives the copy no covering panel — the folder it
      // checks is the subject, not the room the cut takes.
      coveringFrameIdBySource: const {},
    ).execute();
    // The folder exists on the SOURCE cut only: the sibling never got one.
    CreateFolderCommand(
      repository: repository,
      cutId: source.id,
      name: 'Folder',
      memberLayerIds: [sourceLayer.id],
      folderIdByCut: {source.id: folderId},
      groupId: 'folder-group',
    ).execute();
  });

  test('a move into the unmirrored folder produces no sibling command', () {
    final coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: editingSession,
      historyManager: HistoryManager(),
      brushFrameStore: BrushFrameStore(),
    );
    final order = [
      for (final layer in requireCut(
        repository.requireProject(),
        source.id,
      ).layers)
        layer.id,
    ];
    final commands = coordinator.layerPlacementCommands(
      cutId: source.id,
      order: order,
      folderIds: {sourceLayer.id: folderId},
      movedIds: {sourceLayer.id},
    );
    expect(
      commands,
      hasLength(1),
      reason: 'the source cut\'s own placement, and nothing for the sibling',
    );
  });
}
