// The door a delivery FOLDER comes in through — the field's structure,
// not a file: symbol layers with named cels, `_BG`/`_BOOK` pictures,
// archived-process attach folders, and the 겸용컷 follow-up.
//
// Its own object since round 8 (G1, 2026-09-06).

import 'dart:io';

import '../../models/import/cut_folder_parse.dart';
import '../../models/media_asset.dart';
import '../../services/commands/import_media_command.dart';
import '../../services/editing/default_cut_helpers.dart'
    show defaultCutCanvasSize;
import '../../services/import/cut_folder_listing.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/media/media_byte_source.dart';
import 'import_landing.dart';
import 'render_caches.dart';
import 'session_roles.dart';
import '../../models/import/import_warning.dart';

/// The cut-folder import.
class CutFolderImportDoor {
  CutFolderImportDoor({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required TimelineAccess timeline,
    required ImportLanding landing,
    required HoldMediaBytes holdBytes,
    required Future<void> Function(Iterable<MediaAsset> arriving)
    holdCarriedBytes,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _internals = internals,
       _renderCaches = renderCaches,
       _timeline = timeline,
       _landing = landing,
       _holdBytes = holdBytes,
       _holdCarriedBytes = holdCarriedBytes;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;
  final TimelineAccess _timeline;
  final ImportLanding _landing;

  /// Where a file's bytes are — the project's own copy first — and the
  /// holding of what arrives carried ([MediaPool.holdCarriedBytes]): the
  /// two questions every placement door asks (`ProjectImportDoors`), asked
  /// here too. 🪦A folder imported again baked its cels from the files on
  /// disk and staged a second copy of what the project already carried
  /// (audit 2026-09-24).
  final HoldMediaBytes _holdBytes;
  final Future<void> Function(Iterable<MediaAsset> arriving)
  _holdCarriedBytes;

  /// Imports a CUT FOLDER (the field's delivery structure) parsed by
  /// [parseCutFolder]: one fully-formed cut — symbol layers with named
  /// cels one comma each, `_BG`/`_BOOK` picture layers, archived-process
  /// attach folders when opted in — plus reference registrations, in one
  /// undo. Multi-cut folders (rule H) follow up with linked-cut creation
  /// per extra number (the field 겸용컷; separate undo steps).
  /// Returns the parse-and-plan warnings, or null when nothing imported.
  Future<List<ImportWarning>?> importCutFolder({
    required String folderPath,
    required bool copyIntoProject,
    CutFolderParseConfig config = const CutFolderParseConfig(),
    MediaFitMode fit = MediaFitMode.contain,
  }) async {
    final directory = Directory(folderPath);
    if (!directory.existsSync()) {
      return null;
    }
    final List<CutFolderEntry> entries;
    try {
      // ASYNCHRONOUS on purpose, where the dialog's preview walks the same
      // folder synchronously: an import may be handed a delivery with
      // hundreds of scans and must not hold the frame while it counts them.
      // What a listed entity MEANS is shared; the walk is not.
      entries = cutFolderEntriesFrom(
        folderPath,
        await directory.list(recursive: true).toList(),
      );
    } on FileSystemException {
      return null; // Unreadable folder (permissions, vanished share).
    }
    final parsed = parseCutFolderAt(
      folderPath,
      entries: entries,
      config: config,
    );

    final canvasSize =
        _project.activeCutOrNull?.canvasSize ?? defaultCutCanvasSize;
    final plan = planCutFolderImport(
      parsed: parsed,
      resolveFile: (relativePath) => '$folderPath/$relativePath',
      canvasSize: canvasSize,
      fit: fit,
      mint: _landing.idMint(),
    );
    if (plan.bakes.isEmpty && plan.assets.isEmpty) {
      return plan.warnings;
    }

    // A cut folder's reference registrations follow the import's
    // carry-or-reference choice like any other file. The planner cannot
    // know it — it is given a folder, not a window — so the answer is
    // stamped on the way out.
    //
    // 🚨 It used to be stamped as a COPY into `.assets/Media` and nothing
    // else, which meant the pool entry itself said `carried: false`: the
    // one thing the save reads. The first save after a folder import left
    // every 参考 scan OUTSIDE the archive, and only a reopen put it right
    // (the old `sourcePath` spelling of the same answer).
    //
    // 🪦This paragraph used to end「the kind still sets the ceiling above
    // this, so a delivery's 참고영상 stays a reference either way」. That
    // ceiling died 2026-08-14 — the kind only picks the import window's
    // DEFAULT now, and a movie carries if the person says so.
    //
    // Each carried one is a carry of its own ([mintMediaCarry]).
    final registeredAssets = [
      for (final asset in plan.assets)
        if (copyIntoProject)
          asset.copyWith(carriedAs: mintMediaCarry())
        else
          asset,
    ];
    // ⛔Awaited BEFORE the command that registers them. The isolate that
    // secures these bytes is the reason this is a `Future` at all, and
    // letting the registration overtake it is the one thing carrying must
    // not do.
    await _holdCarriedBytes(registeredAssets);

    _project.historyManager.execute(
      ImportMediaCommand(
        repository: _project.repository,
        editingSession: _timeline.editingSession,
        trackId: _selection.selectedTrackId,
        newCuts: [plan.cut],
        assetAdditions: registeredAssets,
        description: 'Import folder ${mediaFileName(folderPath)}',
      ),
    );

    final bakedCut = _project.cutById(plan.cut.id);
    if (bakedCut != null) {
      // Each file bakes exactly once — decode, bake, dispose, so the
      // peak stays ONE image no matter how large the folder (the
      // measured folders run past 100 scanned cels).
      for (final bake in plan.bakes) {
        final List<DecodedImageFrame> frames;
        try {
          frames = await decodeImageFrames(
            await readHeldMediaBytes(_holdBytes, bake.sourceFile),
          );
        } on Object {
          continue; // Unreadable file — the cel stays empty.
        }
        if (frames.isEmpty) {
          continue;
        }
        try {
          final surface = await rasterizeImageToSurface(
            image: frames.first.image,
            canvas: bakedCut.canvasSize,
            fit: bake.fit,
          );
          bakeCelSurface(
            _renderCaches.brushFrameStore,
            _internals.brushFrameKeyForCut(
              bakedCut,
              bake.layerId,
              bake.frameId,
            ),
            surface,
          );
        } finally {
          for (final frame in frames) {
            frame.image.dispose();
          }
        }
      }
    }

    // Rule H: the folder's extra cut numbers become 겸용컷 copies of the
    // imported cut, sharing its cel banks.
    for (final extraNumber in plan.extraCutNumbers) {
      _project.cutCommandCoordinator.createLinkedCut(
        sourceCutId: plan.cut.id,
        name: extraNumber,
      );
    }

    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
    return plan.warnings;
  }
}
