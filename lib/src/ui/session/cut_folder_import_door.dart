// The door a delivery FOLDER comes in through — the field's structure,
// not a file: symbol layers with named cels, their corrections as attach
// rows, and `_BG`/`_BOOK` pictures.
//
// Its own object since round 8 (G1, 2026-09-06).

import 'dart:io';

import '../../models/import/cut_folder_edits.dart';
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
    required RenderCaches renderCaches,
    required TimelineAccess timeline,
    required ImportLanding landing,
    required HoldMediaBytes holdBytes,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _renderCaches = renderCaches,
       _timeline = timeline,
       _landing = landing,
       _holdBytes = holdBytes;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final RenderCaches _renderCaches;
  final TimelineAccess _timeline;
  final ImportLanding _landing;

  /// Where a file's bytes are — the project's own copy first: the question
  /// every placement door asks (`ProjectImportDoors`), asked here too.
  /// 🪦A folder imported again baked its cels from the files on disk
  /// (audit 2026-09-24).
  final HoldMediaBytes _holdBytes;

  /// Imports a CUT FOLDER (the field's delivery structure) parsed by
  /// [parseCutFolder], as the import window answered it ([edits]): ONE
  /// fully-formed cut — symbol layers with named cels one comma each,
  /// their corrections as attach rows, `_BG`/`_BOOK` picture layers — in
  /// one undo. 🗣️F-429-Q3 (유저 10-21): 「겸용컷으로 읽는 로직 삭제. 항상
  /// 한 컷으로만 들어오는느낌」 — a folder naming several cuts is one cut too.
  /// Returns the parse-and-plan warnings, or null when nothing imported.
  ///
  /// The folder's timesheet scans and reference movie are not this door's:
  /// the window lists them as files of their own and registers or places
  /// each as its row says (F-429-Q4).
  ///
  /// [onProgress] hears each scan baked — the import window's wait counts
  /// them (F-282-Q1).
  Future<List<ImportWarning>?> importCutFolder({
    required String folderPath,
    CutFolderEdits edits = const CutFolderEdits(),
    void Function(int baked, int total)? onProgress,
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
    final parsed = parseCutFolderAt(folderPath, entries: entries);

    final canvasSize =
        _project.activeCutOrNull?.canvasSize ?? defaultCutCanvasSize;
    final plan = planCutFolderImport(
      parsed: parsed,
      edits: edits,
      resolveFile: (relativePath) => cutFolderFilePath(folderPath, relativePath),
      canvasSize: canvasSize,
      mint: _landing.idMint(),
    );
    if (plan.bakes.isEmpty) {
      return plan.warnings;
    }

    _project.historyManager.execute(
      ImportMediaCommand(
        repository: _project.repository,
        editingSession: _timeline.editingSession,
        trackId: _selection.selectedTrackId,
        newCuts: [plan.cut],
        description: 'Import folder ${mediaFileName(folderPath)}',
      ),
    );

    final bakedCut = _project.cutById(plan.cut.id);
    if (bakedCut != null) {
      // Each file bakes exactly once — decode, bake, dispose, so the
      // peak stays ONE image no matter how large the folder (the
      // measured folders run past 100 scanned cels).
      for (final (index, bake) in plan.bakes.indexed) {
        onProgress?.call(index, plan.bakes.length);
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
          final picture = frames.first.picture;
          final surface = await layCelPicture(
            picture: picture,
            canvas: bakedCut.canvasSize,
            placement: fitPlacement(
              picture.size,
              bakedCut.canvasSize,
              plan.fits[bake.layerId]!,
            ),
          );
          bakeCelSurface(
            _renderCaches.brushFrameStore,
            _project.brushFrameKeyForCut(
              bakedCut,
              bake.layerId,
              bake.frameId,
            ),
            surface,
          );
        } finally {
          for (final frame in frames) {
            frame.picture.dispose();
          }
        }
      }
    }

    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
    return plan.warnings;
  }
}
