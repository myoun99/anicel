// Where an import LANDS, and what it must know before it reads a byte.
//
// Its own object since round 8 (G1, 2026-09-06): the image, PSD and PDF
// doors each carried their own copy of the destination gate and of the
// six facts derived from it, and all three then called one landing verb.
// The gate is the law; three copies of it were three chances for one to
// slip behind a decode.

import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/media_asset.dart';
import '../../services/commands/import_media_command.dart';
import '../../services/editing/default_cut_helpers.dart'
    show createDefaultCut, defaultCutCanvasSize, importedCut;
import '../../services/import/media_import_planner.dart';
import '../../services/project_lookup.dart' show projectLayerIdValues;
import 'session_roles.dart';

/// Where this import is landing, and the identity it lands under.
///
/// ⛔THE DESTINATION GATE RUNS BEFORE ANY READ. Each door said it in its
/// own words — "before any decode", "before any read", "before any native
/// work" — because a refused import must not have images, a PSD's bytes
/// or an open PDF document to leak. It is one law, so it is one object:
/// [ImportLanding.arriveAt] answers null when the destination refuses,
/// and every door's first statement is that answer.
class ImportArrival {
  ImportArrival({
    required this.targetCut,
    required this.canvasSize,
    required this.mint,
    required this.source,
    required this.displayName,
    required this.projectFps,
  });

  /// The cut the layers join, or null when this import brings its own.
  ///
  /// ⛔This is also the answer to "which destination was asked for": the
  /// gate refuses [ImportDestination.activeCutLayer] with no active cut,
  /// so a non-null cut here IS that destination and a null one is the new
  /// cut. One field, one question — the destination used to be carried
  /// alongside and the two had to agree.
  final Cut? targetCut;
  final CanvasSize canvasSize;
  final ImportIdMint mint;

  /// The source file, spelled the one way the project records paths.
  final String source;
  final String displayName;
  final int projectFps;

  /// The cut this import lands in — the target's own id, or a fresh one.
  ///
  /// ⚠️Minted on FIRST READ, which is after the decode in every door. A
  /// door that refuses its file (unreadable, undecodable, no pages) must
  /// not have spent a cut number on it.
  late final CutId cutId = targetCut?.id ?? mint.nextCutId();

  /// How long a STILL holds: the cut it joins keeps its own length, and a
  /// new cut takes what the import window asked for, or a project second.
  int stillDuration({int? lengthFrames}) {
    final cut = targetCut;
    if (cut == null) {
      return lengthFrames ?? projectFps;
    }
    return cut.duration < 1 ? 1 : cut.duration;
  }
}

/// The gate every media-file import passes, the id mint it passes it
/// with, and the one landing both destinations go through.
class ImportLanding {
  ImportLanding({
    required ProjectAccess project,
    required SelectionAccess selection,
    required FrameIds frameIds,
    required TimelineAccess timeline,
    required SessionInternals internals,
  }) : _project = project,
       _selection = selection,
       _frameIds = frameIds,
       _timeline = timeline,
       _internals = internals;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final FrameIds _frameIds;
  final TimelineAccess _timeline;
  final SessionInternals _internals;

  int _importCutSequence = 0;

  /// Whether this import may land where it was aimed, and everything the
  /// door needs about the file once it may — or null when the destination
  /// refuses, which is the door's first `return`.
  ImportArrival? arriveAt(
    ImportDestination destination, {
    required String path,
  }) {
    final targetCut = destination == ImportDestination.activeCutLayer
        ? _project.activeCutOrNull
        : null;
    if (destination == ImportDestination.activeCutLayer && targetCut == null) {
      return null;
    }
    final source = normalizedMediaPath(path);
    return ImportArrival(
      targetCut: targetCut,
      canvasSize:
          targetCut?.canvasSize ??
          _project.activeCutOrNull?.canvasSize ??
          defaultCutCanvasSize,
      mint: idMint(),
      source: source,
      displayName: mediaAssetDefaultName(source),
      projectFps: _project.repository.requireProject().fps,
    );
  }

  ImportIdMint idMint() {
    // ONE scan for the whole batch. An import mints an id per layer and per
    // cut it brings in, and scanning the project inside each of those turns
    // a 200-layer PSD landing in a heavy project into 200 walks of every
    // layer in it. The snapshot stays correct because the counters only
    // climb: an id minted a moment ago is not in this set, and it is not
    // reachable again either.
    final usedLayerIds = projectLayerIdValues(
      _project.repository.requireProject(),
    );
    final usedCutIds = {
      for (final track in _project.repository.requireProject().tracks)
        for (final cut in track.cuts) cut.id.value,
    };
    return ImportIdMint(
      nextLayerId: () => _internals.mintLayerId(usedIds: usedLayerIds),
      // Through the MINT, not the formatter. `nextFrameId` reads
      // `_frameSequence` and does not advance it, so calling it directly
      // leaves the wall clock as the only thing telling two cels apart —
      // and an import mints a whole layer inside one clock tick. Every cel
      // of that layer came out with the SAME id, which is not "cels that
      // look alike": it is one drawing exposed N times. A 10-drawing layer
      // arrived as one drawing.
      nextFrameId: _frameIds.mintFrameId,
      nextCutId: () {
        _importCutSequence += 1;
        var candidate = 'import-cut-$_importCutSequence';
        while (usedCutIds.contains(candidate)) {
          _importCutSequence += 1;
          candidate = 'import-cut-$_importCutSequence';
        }
        return CutId(candidate);
      },
    );
  }

  /// Lands imported [layers] where [arrival] says: as rows in the cut
  /// that is already there, or as a NEW cut built from the default.
  ///
  /// ⛔THREE IMPORTERS, ONE LANDING. Image, PSD and PDF each wrote both
  /// arms out with their own ImportMediaCommand, so a field the command
  /// grew reached one importer's new cut and not another's — and the two
  /// arms have to agree about the description the undo stack shows, which
  /// is the only thing the user sees of either.
  void land(
    List<Layer> layers, {
    required ImportArrival arrival,
    required int duration,
    List<MediaAsset> assets = const [],
  }) {
    final description = 'Import ${arrival.displayName}';
    if (arrival.targetCut != null) {
      _project.historyManager.execute(
        ImportMediaCommand(
          repository: _project.repository,
          editingSession: _timeline.editingSession,
          targetCutId: arrival.cutId,
          newLayers: layers,
          assetAdditions: assets,
          description: description,
        ),
      );
      return;
    }
    final cut = importedCut(
      defaultCut: createDefaultCut(
        cutId: arrival.cutId,
        name: arrival.displayName,
        layerId: arrival.mint.nextLayerId(),
        canvasSize: arrival.canvasSize,
      ),
      layers: layers,
      duration: duration,
    );
    _project.historyManager.execute(
      ImportMediaCommand(
        repository: _project.repository,
        editingSession: _timeline.editingSession,
        trackId: _selection.selectedTrackId,
        newCuts: [cut],
        assetAdditions: assets,
        description: description,
      ),
    );
  }
}
