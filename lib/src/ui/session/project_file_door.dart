// The .anicel door: everything that writes this session into a file, or
// reads one back into it.
//
// Its own object since round 8 (G1, 2026-09-06). Like
// [EditorVoiceRecording], it did not come free — its constructor lists the
// session members a save and an open actually touch, and that list IS the
// coupling this block always had. What it no longer does is own the
// FACTS: which file, what it carries, whether anything is unsaved and
// whether a recovery snapshot may run all live in [ProjectFile], which
// this pushes into.

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/brush_frame_key.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/frame_id.dart';
import '../../models/project.dart';
import '../../services/audio/conform_cache_maintenance.dart'
    show pruneConformCache;
import '../../services/brush_frame_store.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/project_media_sources.dart'
    show ProjectConforms, mediaEntryNamesFor, projectMediaSources;
import '../../services/persistence/anicel_file_service.dart';
import '../../services/persistence/anicel_project_archive.dart'
    show remapProjectMediaPaths;
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/folder_grant.dart' show FolderPicker;
import '../../services/persistence/media_staging_store.dart';
import '../../services/project_lookup.dart' show projectAudioSourcePaths;
import '../audio/audio_conform_store.dart';
import 'editor_voice_recording.dart';
import 'frame_clipboard.dart';
import 'layer_clipboard.dart';
import 'media_fingerprint_ledger.dart';
import 'media_grant_ledger.dart';
import 'project_file.dart';
import 'playback_rig.dart';
import 'session_roles.dart';
import 'text_cel_bakes.dart';

/// Saves the session into a `.anicel`, snapshots it for recovery, and
/// opens one back.
class ProjectFileDoor {
  ProjectFileDoor({
    required ProjectFile file,
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required PlaybackRig playbackRig,
    required BrushFrameStore conteInkRowStore,
    required BrushFrameStore conteInkPageStore,
    required BrushFrameStore envelopeInkStore,
    required MediaStagingStore staging,
    required MediaGrantLedger grants,
    required MediaFingerprintLedger fingerprints,
    required TextCelBakes textCelBakes,
    required EditorVoiceRecording voiceRecording,
    required FrameClipboard clipboard,
    required LayerClipboard layerClipboard,
    required AudioConformStore audioConformStore,
    required ValueNotifier<int> frameSeekCommitted,
    required void Function() refreshMediaExistence,
  }) : _file = file,
       _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _playbackRig = playbackRig,
       _conteInkRowStore = conteInkRowStore,
       _conteInkPageStore = conteInkPageStore,
       _envelopeInkStore = envelopeInkStore,
       _staging = staging,
       _grants = grants,
       _fingerprints = fingerprints,
       _textCelBakes = textCelBakes,
       _voiceRecording = voiceRecording,
       _clipboard = clipboard,
       _layerClipboard = layerClipboard,
       _audioConformStore = audioConformStore,
       _frameSeekCommitted = frameSeekCommitted,
       _refreshMediaExistence = refreshMediaExistence;

  final ProjectFile _file;
  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final PlaybackRig _playbackRig;
  final BrushFrameStore _conteInkRowStore;
  final BrushFrameStore _conteInkPageStore;
  final BrushFrameStore _envelopeInkStore;
  final MediaStagingStore _staging;
  final MediaGrantLedger _grants;
  final MediaFingerprintLedger _fingerprints;
  final TextCelBakes _textCelBakes;
  final EditorVoiceRecording _voiceRecording;
  final FrameClipboard _clipboard;
  final LayerClipboard _layerClipboard;
  final AudioConformStore _audioConformStore;
  final ValueNotifier<int> _frameSeekCommitted;
  final void Function() _refreshMediaExistence;

  static const AnicelFileService _anicelFileService = AnicelFileService();

  /// The four cel stores an archive holds, in the order every writer
  /// lists them: the drawings, then the two conte ink namespaces, then
  /// the cut envelope's.
  List<BrushFrameStore> get _auxCelStores => [
    _conteInkRowStore,
    _conteInkPageStore,
    _envelopeInkStore,
  ];

  /// Cels the last save could not write because the file their only copy
  /// lived in had been deleted.
  ///
  /// 🚨★★★**EMPTY IS THE ONLY ANSWER ANYBODY EXPECTED** until 유저 hit it
  /// on an iPad (2026-08-30): open a project, delete the file in the Files
  /// app, draw a stroke, press Save. A save turns every cel into a file ref
  /// and drops its cold blob as「redundant with the file」, so once that
  /// file is gone the untouched cels have their bytes nowhere — and the
  /// save used to come apart with a raw `PathNotFoundException` carrying a
  /// path.
  ///
  /// It now writes everything it can still reach and says what it could
  /// not. ⛔The UI has to SHOW this: a save that quietly wrote fewer cels
  /// than it holds is the shape this repo refuses for media, and a cel is
  /// the picture itself.
  Set<BrushFrameKey> celsLostToAMissingFile = const {};

  /// Writes the current state to [path] WITHOUT touching the dirty flag or
  /// the project path — the recovery service's snapshot writer.
  ///
  /// An OVERLAY on the saved project: only the cels edited since the last
  /// manual save. This runs mid-session on the periodic tick (F-1 made the
  /// clock the only trigger), so it has to cost what the user drew rather
  /// than what the project weighs. Everything left out is already in the
  /// project file, unchanged, which is also what the base stamp inside the
  /// overlay is there to guarantee.
  Future<void> writeAutosaveSnapshot(String path) async {
    final base = _file.path;
    if (base == null) {
      return;
    }
    // 🚨A RECOVERED session must not write one. Recovery pointed every
    // restored cel's ref INTO this file and cleared the RAM tiers, and it
    // also cleared the dirty set — so a snapshot taken now would carry no
    // cels at all and rename itself over the only copy of the work, and
    // the live refs would then read past the end of a file holding a
    // stamp and a project.json. The session has nothing new to snapshot
    // until a manual save moves those pixels into the project file, which
    // is exactly when this unblocks.
    if (_file.isRecoveredSession) {
      return;
    }
    // The user chose to throw this session's work away and the app is
    // shutting down around that choice; the lifecycle callbacks that
    // follow must not put it back.
    if (_file.discardedUnsavedWork) {
      return;
    }
    await _textCelBakes.flushTextCelBakes();
    await _anicelFileService.writeRecoveryOverlay(
      project: _project.repository.requireProject(),
      brushFrameStore: _internals.brushFrameStore,
      auxCelStores: _auxCelStores,
      filePath: path,
      baseFilePath: base,
      // The overlay's project.json replaces the base file's, so a snapshot
      // that left these out would hand the recovered session no grants —
      // and its first save would write that emptiness back over the file.
      grants: _grants.grantsToStore(),
      // What the base file already carries. Without it the recovered
      // session forgets its media is inside the archive and its first
      // save writes one that no longer holds it.
      mediaInArchive: _file.mediaEntryNames.keys.toSet(),
      // And what it knows about its media's content. A recovered session
      // without these still opens and still looks right — it has just
      // forgotten how to tell one `A1.png` from another.
      mediaCrcs: _fingerprints.crcsToStore(),
      // Asked again at the rename: a manual save can begin and finish
      // while this one is in the isolate, and it retires the snapshot on
      // its way out. Generation-armed, not just the in-flight flag — the
      // flag is already down again by the time a spanning snapshot asks.
      isStale: _file.beginAutosaveStaleCheck(),
    );
  }

  /// Saves the project + every drawn frame into ONE .anicel file (atomic
  /// temp-then-rename write; media stays external with relative paths
  /// recorded for Drive portability). A successful save retires the
  /// autosave sidecar.
  ///
  /// [onProgress] is called with 0..1 as the write proceeds, for the window
  /// a manual save puts in front of itself. Omitted by the autosave tick,
  /// which nobody is watching.
  Future<void> saveProjectToFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    // A text bake in flight must land before the store snapshots — the
    // archive's parameters and raster must never disagree.
    // Raised for the WHOLE save, retirement included. An autosave tick that
    // starts inside a save renames its own temp onto the sidecar path
    // AFTER the retirement ran, and the session is clean by then — so the
    // exit gate returns early, nothing retires it, and the next open offers
    // recovery for a project that was closed cleanly. Making the delete
    // synchronous did not close this: sync ordering settles delete-versus-
    // write, and this is write-versus-delete, which is an isolate wide.
    _file.beginSave();
    // The breadcrumb a silent kill cannot erase. A save is the work this
    // app is most likely to die inside — and when iOS kills for memory
    // there is no exception, no crash report, and nothing in App Store
    // Connect (실기 08-27: three kills, an iPad that survived the same
    // press, and not one line of evidence anywhere). An entry with no END
    // at the next launch is the only thing that says otherwise.
    MemoryBlackBox.begin('save');
    try {
      await _writeProjectToFile(filePath, onProgress: onProgress);
    } finally {
      _file.endSave();
      MemoryBlackBox.end('save');
    }
  }

  /// Writes the CURRENT state to [path] as a complete, standalone archive
  /// and changes NOTHING about this session — no path adoption, no ref
  /// adoption, no dirty-flag or sidecar movement. The Save As STAGING
  /// writer on scoped platforms: the file this produces is about to be
  /// MOVED by a document picker, so anything the session learned from it
  /// would name a path that stops existing moments later.
  ///
  /// 🚨 Exists because of the 22-byte placeholder this replaces (실측
  /// iPhone+Drive, 08-26): a provider that refuses in-place writes made
  /// the post-placement save fail, and what the picker had placed was the
  /// EMPTY placeholder — an unopenable husk where the user meant to put
  /// their project. A complete archive staged up front costs the same
  /// move and can never strand a husk.
  /// Returns the media entry names the archive was written with, which is
  /// what [adoptPlacedArchive] needs if this copy becomes the project.
  Future<Map<String, String>> writeArchiveCopy(
    String path, {
    void Function(double)? onProgress,
  }) async {
    await _textCelBakes.flushTextCelBakes();
    final mediaToStore = projectMediaSources(
      project: _project.repository.requireProject(),
      projectFilePath: _file.path,
      mediaEntryNames: _file.mediaEntryNames,
      staging: _staging,
    );
    final conforms = _file.conformsToStore();
    await _anicelFileService.save(
      project: _project.repository.requireProject(),
      brushFrameStore: _internals.brushFrameStore,
      auxCelStores: _auxCelStores,
      filePath: path,
      mediaToStore: mediaToStore,
      conforms: conforms,
      grants: _grants.grantsToStore(),
      mediaCrcs: _fingerprints.crcsToStore(),
      onProgress: onProgress,
      adoptRefs: false,
    );
    return mediaEntryNamesFor(mediaToStore);
  }

  /// The archive at [placedPath] IS this project now — no second write.
  ///
  /// iOS has no save panel: the export picker MOVES a file the app wrote
  /// and reports where it landed, so by the time Save As knows the
  /// destination, [writeArchiveCopy]'s bytes are already sitting there and
  /// the picker's modality means nothing could have edited them since.
  ///
  /// 🚨Saving AGAIN over that path was the old shape and it is not merely
  /// wasteful. A destination the picker moved a file INTO is not one the
  /// app may keep writing to: Save As died with 「the location refused
  /// both a direct write and a coordinated replace」 on a path it had just
  /// successfully filled (실기 08-27, iPhone). Adoption cannot be refused,
  /// because there is nothing left to write.
  ///
  /// ⚠️Cel refs are NOT repointed into the placed file. [writeArchiveCopy]
  /// writes with `adoptRefs: false` precisely because a file about to be
  /// MOVED cannot back a ref, and the destination may be somewhere the app
  /// cannot read back on demand either. The pixels stay where they were —
  /// in RAM — which is what a never-saved session was already doing.
  void adoptPlacedArchive(
    String placedPath, {
    required Map<String, String> mediaEntryNames,
  }) {
    _file.bindToSavedFile(placedPath, entryNames: mediaEntryNames);
    _changes.notifyChanged();
  }

  /// The provider-refusal fallback: a complete archive written into the
  /// app's own Recovery folder (so an orphan is swept in ≤30 days), then
  /// swapped over [filePath] by the platform's file coordinator.
  ///
  /// The staging save ADOPTS normally — its refs are valid while the
  /// staging file exists, and it exists until the sweep. After a
  /// successful replace the copy at [filePath] is byte-identical, so the
  /// same offsets hold there and clean keys' refs are simply repointed.
  /// ⚠️ Keys dirty AGAIN (drawn on while the save ran) keep their staging
  /// refs and their dirt: repointing them through [adoptSavedFile] would
  /// CLEAR that dirt, and the next save would quietly skip the stroke —
  /// the exact loss shape the editTick round closed.
  ///
  /// A replace that also fails rethrows the file-system refusal: the
  /// notice names the real problem, and Q-drive-resave owns what the app
  /// should offer instead.
  Future<void> _saveViaCoordinatedReplace(
    String filePath, {
    required Map<String, MediaByteSource> mediaToStore,
    required ProjectConforms conforms,
    void Function(double)? onProgress,
  }) async {
    final stagingDirectory = Directory(AppSave.recoveryDirectory())
      ..createSync(recursive: true);
    final staging =
        '${stagingDirectory.path.replaceAll('\\', '/')}'
        '/replace.tmp-${DateTime.now().microsecondsSinceEpoch}';
    await _anicelFileService.save(
      project: _project.repository.requireProject(),
      brushFrameStore: _internals.brushFrameStore,
      auxCelStores: _auxCelStores,
      filePath: staging,
      mediaToStore: mediaToStore,
      conforms: conforms,
      grants: _grants.grantsToStore(),
      mediaCrcs: _fingerprints.crcsToStore(),
      onProgress: onProgress,
    );
    final replaced = await FolderPicker.replaceFileCoordinated(
      sourcePath: staging,
      destinationPath: filePath,
    );
    if (!replaced) {
      throw FileSystemException(
        'the location refused both a direct write and a coordinated '
        'replace — this provider cannot be saved to in place',
        filePath,
      );
    }
    for (final store in [_internals.brushFrameStore, ..._auxCelStores]) {
      final snapshot = store.bakedSnapshotForSave();
      final dirtyAgain = store.dirtyCelKeysSinceSave;
      final moved = <BrushFrameKey, AnicelCelFileRef>{
        for (final entry in snapshot.fileRefs.entries)
          if (!dirtyAgain.contains(entry.key) &&
              entry.value.filePath.replaceAll('\\', '/') == staging)
            entry.key: AnicelCelFileRef(
              filePath: filePath,
              dataOffset: entry.value.dataOffset,
              length: entry.value.length,
              canvasSize: entry.value.canvasSize,
              tileSize: entry.value.tileSize,
            ),
      };
      if (moved.isNotEmpty) {
        store.adoptSavedFile(moved, dirtyTicksAtSnapshot: snapshot.dirtyTicks);
      }
    }
  }

  Future<void> _writeProjectToFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    await _textCelBakes.flushTextCelBakes();
    // Captured BEFORE the save moves the project path: a Save As has to
    // retire the sidecars of the file it was saved FROM as well.
    final previousPath = _file.path;
    // Before serializing: the first save takes this session's recordings
    // off the shelf. Nothing moves on disk — see the verb.
    _voiceRecording.releaseShelfTakesToProject();
    // Resolved against the CURRENT project path, before it moves. On a
    // save-as that makes each source point into the file being left
    // behind, and the writer streams from there into the new one — which
    // is how a copy carries its media without a copy step of its own.
    final mediaToStore = projectMediaSources(
      project: _project.repository.requireProject(),
      projectFilePath: _file.path,
      mediaEntryNames: _file.mediaEntryNames,
      staging: _staging,
    );
    final conforms = _file.conformsToStore();
    try {
      celsLostToAMissingFile = await _anicelFileService.save(
        project: _project.repository.requireProject(),
        brushFrameStore: _internals.brushFrameStore,
        auxCelStores: _auxCelStores,
        filePath: filePath,
        mediaToStore: mediaToStore,
        conforms: conforms,
        grants: _grants.grantsToStore(),
        mediaCrcs: _fingerprints.crcsToStore(),
        onProgress: onProgress,
        // 🚨A Save As is「writing somewhere else」and nothing more subtle:
        // the target is not the file this session has been saving to. 유저
        // 2026-08-31 asked for it to be a full write every time — 「기존
        // 파일에 저장 덮어씌우기를 하더라도 고치기위해 풀저장」 — and the
        // case that was NOT already whole is exactly this one, an overwrite
        // onto an older copy of the same project.
        rewriteWhole:
            previousPath != null &&
            previousPath.replaceAll(r'\', '/') !=
                filePath.replaceAll(r'\', '/'),
      );
    } on FileSystemException {
      // 실측 (08-26, iPhone + Google Drive): a File Provider can refuse
      // plain in-place writes outright. The sanctioned way through is a
      // COORDINATED replace — write the whole archive app-locally, then
      // hand it to NSFileCoordinator to swap over the provider file.
      // Scoped platforms only: a desktop refusal (locked file, dead
      // drive) has no coordinator to appeal to and must stay loud.
      if (!FolderPicker.grantsAreScoped) {
        rethrow;
      }
      await _saveViaCoordinatedReplace(
        filePath,
        mediaToStore: mediaToStore,
        conforms: conforms,
        onProgress: onProgress,
      );
    }
    // 🚨The save ABSORBED the staged bytes, so the staged copy stops being
    // anything — 유저 08-27: 「사본 남으면 진짜 용서안할게」. Retired HERE
    // rather than on close or on import-undo, because this is the one
    // moment the bytes provably live somewhere else.
    for (final path in mediaToStore.keys) {
      _staging.retire(path);
    }
    _file.bindToSavedFile(
      filePath,
      entryNames: mediaEntryNamesFor(mediaToStore),
    );
    _changes.notifyChanged();
  }

  /// Every audio path the project references (SE clips + the SOUND entries
  /// of the media pool) — what a project open warms so waveforms and
  /// playback PCM are ready before the first play.
  ///
  void warmAudioConforms() {
    _audioConformStore.warmPaths(
      projectAudioSourcePaths(_project.repository.requireProject()),
    );
  }

  /// Settles the conform cache's size — ON PROJECT OPEN ONLY.
  ///
  /// That is the moment a fresh batch of conforms is about to be built, so
  /// it is where the bound is worth enforcing, and it costs one directory
  /// scan instead of one per conform on the UI isolate. Pruning FIRST also
  /// means the entries this project is about to touch are the newest in
  /// the cache, so they are the last things a later prune considers.
  ///
  /// ⛔ NOT on the audio-settings knobs. Warming happens there too — a
  /// rate or speed change re-keys every conform — but a directory walk on
  /// the UI isolate is not something to hang off a knob somebody drags
  /// through four values to compare them ([[old-device-support-policy]]).
  ///
  /// The store lets go BEFORE the collector runs. A conform past the
  /// streaming threshold is held with no resident PCM and the file as the
  /// copy of record, so pruning one out from under a live entry leaves the
  /// clip silent for the session — see [AudioConformStore.releaseDiskBacked].
  ///
  /// ⚠️ Deliberately NOT switched off under `FLUTTER_TEST`. The root is
  /// already redirected to a temp folder there, and a call site compiled
  /// out of every test is a call site with no observer — which is how the
  /// path assembly went unwatched before ([[verify-before-claiming-shared]]).
  /// It costs nothing when the cache does not exist yet, which is the
  /// state every test starts in.
  void settleConformCache() {
    _audioConformStore.releaseDiskBacked();
    pruneConformCache();
  }

  /// Opens a .anicel file, replacing the WHOLE session state: project,
  /// drawings, selection (first cut, frame 0) — and BOTH undo stacks
  /// (loaded state has no history; the load→draw→undo path is pinned by
  /// test). [recoverAs] opens autosave SIDECAR bytes while keeping the
  /// real file as the project path (the recovery flow).
  Future<void> openProjectFromFile(
    String filePath, {
    String? recoverAs,
    String? overlayPath,
  }) async {
    // The mirror of "a whole archive is refused as an overlay" (pinned in
    // recovery_overlay_test): an OVERLAY fed through the legacy
    // whole-archive arm is refused too. Its project.json is the full
    // project, so it would OPEN and look right while every base cel reads
    // as empty — and the next full rewrite makes that loss permanent.
    // Loud beats silently lossy; the shell's routing is the one caller and
    // routes overlays to [overlayPath].
    if (recoverAs != null && anicelSnapshotIsOverlay(filePath)) {
      throw const FormatException(
        'this snapshot is a recovery overlay — it holds only what changed '
        'since its base was saved, and has to be opened OVER that base, '
        'never as the project itself',
      );
    }
    final result = await _anicelFileService.open(
      filePath: filePath,
      overlayPath: overlayPath,
    );
    _playbackRig.playback.stop();
    // BEFORE the project lands: a bookmark tracks the file rather than the
    // path, so resolving one is how a referenced movie that was renamed or
    // moved is found again — and the project has to be told, or the pool
    // goes on naming an address nothing answers at. This is the same move
    // the relative-path remap above makes, at the same moment, for the
    // same reason.
    final movedByGrant = await _grants.resolveMediaGrants(result.grants);
    _project.repository.replaceProject(
      movedByGrant.isEmpty
          ? result.project
          : remapProjectMediaPaths(result.project, movedByGrant),
    );
    // Through the bookmark move as well. The service already narrowed these
    // against the RELATIVE-path remap it can see; this second move happens
    // out here, after a bookmark resolved to a file the user renamed, and
    // the service never learns about it. Two movers, both of which have to
    // be followed — miss one and the next save deletes the fact.
    _fingerprints.restoreFromFile(result.mediaFingerprints.moved(movedByGrant));
    // R22-C: opens land every cel FILE-BACKED — pixels stay in the .anicel
    // until a cel is first shown (near-zero RAM for 1500-cut projects).
    // The conte ink namespace routes to its own stores (R5); a ROW entry
    // whose storyboard block no longer exists in the loaded project is
    // pruned HERE — the load boundary is where "ink dies with the
    // drawing" becomes permanent (saving never prunes, so an undone
    // delete keeps its ink within the session).
    final cels = _sortLoadedCels(result);
    _internals.brushFrameStore.restoreFromFile(cels.main);
    final healed = _healStaleCelSizes(
      cels.main,
      project: result.project,
      store: _internals.brushFrameStore,
    );
    _conteInkRowStore.restoreFromFile(cels.inkRow);
    _conteInkPageStore.restoreFromFile(cels.inkPage);
    _envelopeInkStore.restoreFromFile(cels.envelope);
    _project.historyManager.clear();
    _clipboard.clear();
    _layerClipboard.clear();
    // The selections name rows of the project being discarded, so no grid
    // can draw them — and a band nothing shows still CLAIMS the cell verbs
    // ([cellSelectionClaimsSubject]), which would leave Delete and the
    // comma buttons dark with nothing on screen to explain why. Every
    // other whole-state reset clears here; this one was the omission.
    _selection.clearAllSelections();
    _selection.trackFrameRangeSelection.value = null;
    _timeline.editingSession.setActiveCutId(
      result.project.tracks.first.cuts.first.id,
    );
    _internals.rebuildActiveCutControllers();
    // The replaced project's shelf takes are no longer this session's to
    // adopt — they stay on the shelf, findable.
    _voiceRecording.forgetShelfTakes();
    _file.bindToOpenedFile(
      recoverAs ?? filePath,
      // What this project carries, as the file on disk says. Anything the
      // pool names that is NOT here is an ordinary outside reference and
      // resolves by path like it always did.
      entryNames: result.mediaEntryNames,
      // Remembered because the recovered work lives ONLY in that file — an
      // overlay holds the edited cels and every ref for them points inside
      // it, and the RAM tiers were just cleared — so until a save moves
      // those pixels into the project file, deleting it is deleting the
      // work. (A snapshot from an older build is a whole archive opened as
      // [filePath]; same reasoning, same field.) Reset on an ordinary open
      // so a later session never inherits another one's exception.
      recoveredFrom: overlayPath ?? (recoverAs == null ? null : filePath),
      // A recovered session stays dirty: its content differs from the real
      // file until the user saves — and so does a session whose load just
      // HEALED mismatched cels (R7q2).
      unsaved: recoverAs != null || overlayPath != null || healed,
    );
    settleConformCache();
    warmAudioConforms();
    // RELINK-2: the first of the three refresh moments. A project opened
    // on a machine that does not have its referenced media has to SAY so —
    // that is the whole point of the banner, and it is the one moment the
    // user has not done anything to prompt it.
    _refreshMediaExistence();
    _changes.warmActiveCut();
    _frameSeekCommitted.value += 1;
    _changes.notifyChanged();
  }
}

/// Every cut the project holds — what a loaded envelope's owner is
/// checked against.
Set<CutId> _everyCutId(Project project) => {
  for (final track in project.tracks)
    for (final cut in track.cuts) cut.id,
};

/// Every drawing the project holds — what a loaded ROW ink entry is
/// checked against.
Set<FrameId> _everyFrameId(Project project) => {
  for (final track in project.tracks)
    for (final cut in track.cuts)
      for (final layer in cut.layers)
        for (final frame in layer.frames) frame.id,
};

/// The loaded cels, split by which store owns them — and PRUNED of the
/// ones whose drawing no longer exists in the project being opened.
///
/// The conte ink namespace routes to its own stores (R5); a ROW entry
/// whose storyboard block no longer exists in the loaded project is
/// pruned HERE — the load boundary is where "ink dies with the drawing"
/// becomes permanent (saving never prunes, so an undone delete keeps
/// its ink within the session).
({
  Map<BrushFrameKey, AnicelCelFileRef> main,
  Map<BrushFrameKey, AnicelCelFileRef> inkRow,
  Map<BrushFrameKey, AnicelCelFileRef> inkPage,
  Map<BrushFrameKey, AnicelCelFileRef> envelope,
})
_sortLoadedCels(AnicelOpenResult result) {
  final main = <BrushFrameKey, AnicelCelFileRef>{};
  final inkRow = <BrushFrameKey, AnicelCelFileRef>{};
  final inkPage = <BrushFrameKey, AnicelCelFileRef>{};
  final envelope = <BrushFrameKey, AnicelCelFileRef>{};
  Set<FrameId>? liveFrameIds;
  Set<CutId>? liveCutIds;
  for (final entry in result.cels.entries) {
    final key = entry.key;
    if (isEnvelopeInkKey(key)) {
      // An envelope's ink is keyed by its OWNER cut: the sheet dies with
      // the cut it describes. Which BOX a stroke sits in is never pruned
      // — swapping the form preset back has to bring the writing back
      // with it.
      liveCutIds ??= _everyCutId(result.project);
      if (liveCutIds.contains(key.cutId)) {
        envelope[key] = entry.value;
      }
    } else if (!isConteInkKey(key)) {
      main[key] = entry.value;
    } else if (key.layerId == conteInkRowLayerId) {
      liveFrameIds ??= _everyFrameId(result.project);
      if (liveFrameIds.contains(key.frameId)) {
        inkRow[key] = entry.value;
      }
    } else {
      inkPage[key] = entry.value;
    }
  }
  return (main: main, inkRow: inkRow, inkPage: inkPage, envelope: envelope);
}

/// R7q2 (유저 08-18: 「치유가 가볍게 가능하다면 해도 됨」): heal cels whose
/// stored canvas size disagrees with their cut.
///
/// Files written while the resize was still split in two could leave
/// 겸용 or unselected cuts' cels at a stale size, which display as EMPTY
/// and turn permanent on the first stroke (the D5 loss, preserved in the
/// save). A healthy file walks this map once and finds nothing; a broken
/// cel gets the same strictly cut-scoped crop the resize itself uses
/// (R27), and the heal marks the project unsaved so the next save writes
/// the repaired truth.
/// Answers whether anything WAS healed — a session whose load repaired
/// a cel is dirty, because the file on disk still holds the broken one.
bool _healStaleCelSizes(
  Map<BrushFrameKey, AnicelCelFileRef> cels, {
  required Project project,
  required BrushFrameStore store,
}) {
  final cutSizes = {
    for (final track in project.tracks)
      for (final cut in track.cuts) cut.id: cut.canvasSize,
  };
  final healedCuts = <CutId>{};
  for (final entry in cels.entries) {
    final cutSize = cutSizes[entry.key.cutId];
    if (cutSize != null && entry.value.canvasSize != cutSize) {
      healedCuts.add(entry.key.cutId);
    }
  }
  for (final cutId in healedCuts) {
    store.resizeBakedSurfaces(cutSizes[cutId]!, cutId: cutId);
  }
  return healedCuts.isNotEmpty;
}
