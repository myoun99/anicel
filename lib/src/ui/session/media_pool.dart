// The project's MEDIA POOL: which files this project names, what it knows
// about each one, and every verb that changes that list.
//
// Its own object since round 8 (G3, 2026-09-07). The ledgers beside the
// pool left in G1 — the content fingerprints
// (session/media_fingerprint_ledger.dart) and the OS grants
// (session/media_grant_ledger.dart) — and this is the surface that stayed
// on the host: the list itself, the import that registers a file, the
// relink that points an entry somewhere else, the sweep that says what is
// still on disk, and the promotion that makes the project carry the bytes.
//
// It is one object because those verbs are one conversation: every one of
// them either reads the pool or rewrites it, and three of them have to
// tell the fingerprints, the staged bytes and the conform cache in the
// same breath — which is exactly the coupling that made "the fingerprints
// follow" a comment instead of a call once already.

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../controllers/timeline_controller.dart' show TimelineController;
import '../../models/audio_clip.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart';
import '../../models/timeline_coverage.dart';
import '../../models/track_id.dart';
import '../../services/import/media_identity_reader.dart';
import '../../services/import/media_import_planner.dart'
    show importedMediaAsset;
import '../../services/media/media_asset_uses.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/persistence/media_staging_store.dart';
import '../../services/project_lookup.dart'
    show projectMediaCarryOf, requireLayerAnywhere;
import '../audio/audio_conform_store.dart';
import 'media_fingerprint_ledger.dart';
import 'project_file.dart';
import 'session_roles.dart';

/// The pool the media browser draws, and the verbs the browser, the import
/// window and the relink hunt call on it.
///
/// It OWNS the existence sweep's two answers ([missingMediaPaths] and
/// [mediaModifiedTimes]) — the only host fields the pool ever wrote, and
/// the reason the sweep came with it rather than staying behind.
class MediaPool {
  MediaPool({
    required ProjectAccess project,
    required ChangeSink changes,
    required ProjectFile file,
    required MediaStagingStore staging,
    required AudioConformStore conforms,
    required MediaFingerprintLedger fingerprints,
  }) : _project = project,
       _changes = changes,
       _file = file,
       _staging = staging,
       _conforms = conforms,
       _fingerprints = fingerprints;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final ProjectFile _file;
  final MediaStagingStore _staging;
  final AudioConformStore _conforms;
  final MediaFingerprintLedger _fingerprints;

  /// The project's media pool, in pool order (the browser panel's list).
  List<MediaAsset> get mediaAssets =>
      _project.repository.requireProject().mediaAssets;

  /// Every use the project has of the [path] asset — the rows placed from it
  /// and the frames that carry it ([mediaAssetUsesOf]): what the pool row's
  /// in-use mark lists, and what removing the asset takes with it (F-118).
  Iterable<MediaAssetUse> mediaAssetUses(String path) =>
      mediaAssetUsesOf(_project.repository.requireProject(), path);

  /// Adds [paths] to the pool (skipping known ones) without linking them
  /// anywhere — import-to-browse, one undo step.
  ///
  /// [carried] defaults to referencing, for the callers that are not an
  /// import and so have no answer to give: linking a file that was already
  /// on disk registers it as what it is, and only a picker the user
  /// answered can say the project should own the bytes.
  /// Registers [paths] in the pool. When [carried], the bytes are COPIED
  /// into the app container on the spot.
  ///
  /// 🚨★★★**That copy is what「품기」means now.** It used to be a promise
  /// kept only at SAVE time — the flag said the file travels with the
  /// project while the bytes were still the ones on disk, so editing or
  /// deleting the original before the first save changed or emptied what
  /// got saved. 유저 2026-08-30: 「품은 순간 데이터를 가지고있고 **불변**
  /// 이었으면좋겠어서」.
  ///
  /// ⚠️Async because that copy runs in an isolate now, and the pool must
  /// not record an asset before its bytes are secured. A caller that
  /// forgets to await gets the pre-carry behaviour back without a word.
  ///
  /// ⚠️SOUNDS: every caller registers one — a clip's file, a take, a
  /// .tvpp's sounds — and the entry says so, as the model's default always
  /// did. The pool's import of any kind is [importMediaFiles].
  Future<void> addMediaAssets(List<String> paths, {bool carried = false}) =>
      _admit([
        for (final path in paths)
          importedMediaAsset(
            path: path,
            kind: MediaAssetKind.audio,
            fit: MediaFitMode.contain,
            identity: readMediaIdentity(path),
            carried: carried,
          ),
      ]);

  /// Records the [entries] the pool does not have yet — once the bytes of
  /// every one that is CARRIED are held.
  ///
  /// 🚨★★★**THE ONE WAY AN IMPORT ENTERS THE POOL.** [importMediaFiles] — the
  /// import window's pool and the viewer's register button — built its own
  /// entries and recorded them carried without holding a byte, from the day
  /// staging landed until 2026-09-24, while [addMediaAssets] beside it held
  /// them (card `a-registered-carry-holds-its-bytes`). Two ways in, and only
  /// one of them kept 「품은 순간 데이터를 가지고있고 불변」 (유저 08-30).
  Future<void> _admit(List<MediaAsset> entries) async {
    final seen = {for (final asset in mediaAssets) asset.path};
    final fresh = [
      for (final entry in entries)
        if (seen.add(entry.path)) entry,
    ];
    final toHold = _carriesToHold(fresh);
    // ⚠️Waited for ONLY when there is something to hold. Nothing carried,
    // the entries are recorded in the same breath as the call — the order
    // an unawaited caller counts on: `AudioClips` registers the sound and
    // places its clip right after, and a wait here moved the registration
    // behind the clip, onto the undo the clip should have had
    // (`audio_import_test`).
    if (toHold.isNotEmpty) {
      await _staging.stageCarriedBytes(toHold);
    }
    // Read after the wait: what landed meanwhile is kept, not written over.
    final pool = mediaAssets;
    final known = {for (final asset in pool) asset.path};
    final added = [
      for (final entry in fresh)
        if (known.add(entry.path)) entry,
    ];
    if (added.isEmpty) {
      return;
    }
    _project.cutCommandCoordinator.updateMediaAssets([
      ...pool,
      ...added,
    ], description: 'Import media');
    _changes.notifyChanged();
  }

  /// Holds the bytes of every CARRIED one among [arriving] that the pool
  /// does not have yet — the ones a landing will record, since a landing
  /// keeps the pool's own entry for a path it already has.
  ///
  /// 🚨★★★**EVERY DOOR THAT RECORDS AN ASSET ASKS THIS, BEFORE IT RECORDS**
  /// (the order is [MediaStagingStore.stageCarriedBytes]'s law). The pool's
  /// own verbs ([_admit]), the placement doors and the cut folder each
  /// spelled the question; the doors asked whether the project already
  /// held the PATH — which, after a removal, an earlier carry of that path
  /// answered yes to, so the new carry's bytes were never taken (card
  /// `recarry-after-remove-reads-the-old`). Each carry is its own now
  /// ([MediaAsset.carriedAs]), and one that arrives is new by definition.
  Future<void> holdCarriedBytes(Iterable<MediaAsset> arriving) =>
      _staging.stageCarriedBytes(_carriesToHold(arriving));

  /// The carries among [arriving] whose bytes a landing needs held — the
  /// question [holdCarriedBytes] and [_admit] both ask.
  List<MediaCarry> _carriesToHold(Iterable<MediaAsset> arriving) {
    final known = {for (final asset in mediaAssets) asset.path};
    return [
      for (final asset in arriving)
        // The first of a path only — the one a landing records.
        if (known.add(asset.path))
          ?asset.carry,
    ];
  }

  /// Renames the [path] asset's display name; one undo step.
  void renameMediaAsset(String path, String name) {
    _project.cutCommandCoordinator.updateMediaAssets([
      for (final asset in mediaAssets)
        if (asset.path == path) asset.copyWith(name: name) else asset,
    ], description: 'Rename media');
    _changes.notifyChanged();
  }

  /// Removes the [path] asset from the pool, and every use of it with it
  /// ([mediaAssetUses]) — ONE undo step. False when the pool holds no such
  /// asset.
  ///
  /// 🚨★★★유저 2026-09-12 (F-118): 「풀에서 그냥 제거버튼 누르면 사용중인데
  /// 제거하겠습니까? 배치한 레이어/프레임이 삭제됩니다. 라고 표시해서
  /// 강제삭제할수있게」. This REFUSED while anything used the asset, and the
  /// refusal only said to take it off the timeline first — with no way to
  /// see where. The question is the pool panel's to ask; this is what a yes
  /// does.
  ///
  /// ⛔**It does NOT retire the staged copy, and that is deliberate.** This
  /// is UNDOABLE — the description above makes an undo entry — so throwing
  /// the bytes away here would mean an undo brings the asset back empty
  /// whenever the original file is also gone, which is precisely the case
  /// 품기 exists for. The RUN'S ROOM owns them instead
  /// ([SessionScratch]): they go when this run ends normally, which is
  /// after every undo that could have wanted them. Waiting costs a file in
  /// the container until then, and not waiting costs the picture.
  bool removeMediaAsset(String path) {
    final next = mediaAssets.where((asset) => asset.path != path).toList();
    if (next.length == mediaAssets.length) {
      return false;
    }
    final uses = mediaAssetUses(path).toList();
    _project.historyManager.runAsOneStep('Remove media', () {
      _removeUses(path, uses);
      _project.cutCommandCoordinator.updateMediaAssets(
        next,
        description: 'Remove media',
      );
    });
    if (uses.isNotEmpty) {
      // A row the stack no longer holds may be the one in hand.
      _changes.refreshAfterCutCommand();
    }
    _changes.notifyChanged();
    return true;
  }

  /// Takes [uses] of [path] out of the project through the verbs a person
  /// uses on each kind: a row is deleted, the blocks that show a frame are
  /// deleted — which takes the frame and its sound with it (REC1-A) — and a
  /// link on a frame no block shows is cut.
  void _removeUses(String path, List<MediaAssetUse> uses) {
    // A row already gone went with the base it rode: a base's delete takes
    // its attach rows along.
    for (final row in uses.whereType<RowMediaUse>()) {
      final cut = _project.cutById(row.cutId);
      if (cut == null || !cut.layers.any((layer) => layer.id == row.layerId)) {
        continue;
      }
      _project.cutCommandCoordinator.deleteLayer(
        cutId: row.cutId,
        layerId: row.layerId,
      );
    }
    // Blocks through the TIMELINE's own delete, through the lens a person's
    // own delete would use: a row of a cut through its cut, a row of a track
    // through the cut in hand when that cut is on the track — the lens the
    // session's timeline gives it, so a hold on a neighbouring block is
    // re-derived over the same cut either way.
    final project = _project.repository.requireProject();
    final activeCutId = _project.activeCutId;
    final activeTrackId = activeCutId == null
        ? null
        : _project.trackOwningCut(activeCutId)?.id;
    final blocks = <(TrackId, CutId?), Map<LayerId, List<int>>>{};
    for (final use in uses.whereType<FrameMediaUse>()) {
      final lens =
          use.cutId ?? (use.trackId == activeTrackId ? activeCutId : null);
      final byLayer = blocks[(use.trackId, lens)] ??= {};
      (byLayer[use.layerId] ??= []).addAll([
        for (final exposure
            in requireLayerAnywhere(project, use.layerId).timeline.entries)
          if (exposure.value.frameId == use.frameId) exposure.key,
      ]);
    }
    for (final MapEntry(key: (trackId, lens), value: byLayer)
        in blocks.entries) {
      TimelineController(
        repository: _project.repository,
        historyManager: _project.historyManager,
        cutId: lens,
        trackSeLayers: () => _project.trackById(trackId)?.seLayers ?? const [],
      ).deleteBlocksForLayers(byLayer);
    }
    // What no block took along: a link on a frame no block shows.
    for (final use in mediaAssetUses(path).whereType<FrameMediaUse>()) {
      final layer = requireLayerAnywhere(
        _project.repository.requireProject(),
        use.layerId,
      );
      _project.cutCommandCoordinator.updateLayerAudioClips(
        cutId: use.cutId,
        layerId: use.layerId,
        audioClips: [
          for (final clip in layer.audioClips)
            if (clip.filePath != path) clip,
        ],
        description: 'Remove media',
      );
    }
  }

  /// Points the [oldPath] asset at [newPath] — the pool entry AND every
  /// referencing clip, one undo step (Resolve-style relink for moved
  /// files). Waveforms re-extract from the new file.
  ///
  /// ⚠️Async because the re-stage below runs in an isolate — see
  /// [MediaStagingStore.stageCarriedBytes].
  Future<void> relinkMediaAsset(String pickedOld, String picked) async {
    // In the pool's one spelling: the pool, the conforms, the fingerprints
    // and the staging are all keyed by it ([normalizedMediaPath]).
    final oldPath = normalizedMediaPath(pickedOld);
    final newPath = normalizedMediaPath(picked);
    final carriedBefore = projectMediaCarryOf(
      _project.repository.requireProject(),
      oldPath,
    );
    _conforms.invalidate(newPath);
    _project.cutCommandCoordinator.relinkMediaAsset(
      oldPath: oldPath,
      newPath: newPath,
    );
    _fingerprints.moveMediaFingerprints({oldPath: newPath});
    // 🚨★★★**THIS RELINK RE-STAGES; THE BATCH ONE MOVES. THE DIFFERENCE
    // IS WHAT EACH CALLER KNOWS.**
    //
    // Here the user picked a file by hand and said「this asset is THAT
    // one」. Nothing checked that it holds the same content — so carrying
    // the OLD staged bytes over to the new key would keep serving the old
    // picture under the name of the new file, for ever, with the project
    // insisting it was right.
    //
    // The batch relink below verified identity before proposing anything,
    // so there the bytes ARE the same and moving them costs one rename
    // instead of re-reading every matched file.
    if (carriedBefore != null) {
      _staging.retire(carriedBefore);
    }
    // ⛔Through [projectMediaCarryOf] rather than a hand-rolled
    // `any(... && asset.carried)`. The asset's carry is the ONE answer to
    // 「does this project carry it」, and a second spelling of it here is
    // how the kind ceiling came to be enforced in two places and disagree
    // with itself. The carry keeps its token across the move; its name
    // changes with the path, so the new file's bytes are a new name.
    final carriedAfter = projectMediaCarryOf(
      _project.repository.requireProject(),
      newPath,
    );
    if (carriedAfter != null) {
      await _staging.stageCarriedBytes([carriedAfter]);
    }
    refreshMediaExistence();
    _changes.notifyChanged();
  }

  /// RELINK-2: the batch form — the media pool's "find them all under
  /// this folder" pass, in one undo step.
  ///
  /// Conforms are invalidated for every destination for the same reason the
  /// single form does it: the file behind the path changed, so a conform
  /// fingerprinted against the old one is stale even though the pool entry
  /// now looks correct.
  void relinkMediaAssets(Map<String, String> picked) {
    final moves = {
      for (final move in picked.entries)
        normalizedMediaPath(move.key): normalizedMediaPath(move.value),
    };
    if (moves.isEmpty) {
      return;
    }
    for (final newPath in moves.values) {
      _conforms.invalidate(newPath);
    }
    _project.cutCommandCoordinator.relinkMediaAssets(moves);
    // 🚨 The fingerprints follow, or the next save erases the very facts
    // this relink was decided by — the store is keyed by path and the save
    // keeps only keys the pool still holds. Left out, the feature works
    // exactly once per asset and only on the machine that imported it.
    _fingerprints.moveMediaFingerprints(moves);
    // And the staged bytes, keyed by the same path — see
    // [MediaStagingStore.rename]. The sentence above about derived state
    // is the whole reason both of these lines exist.
    //
    // ⚠️MOVED, not re-staged, and only because this caller EARNED it: the
    // matcher accepts a candidate only when its identity matches the one
    // recorded for the missing asset, so the bytes are the same bytes and
    // re-reading every matched file would be work for nothing. The
    // by-hand relink above cannot say that, and re-stages.
    final project = _project.repository.requireProject();
    for (final move in moves.entries) {
      if (projectMediaCarryOf(project, move.value) case final moved?) {
        _staging.rename((poolPath: move.key, token: moved.token), move.value);
      }
    }
    refreshMediaExistence();
    _changes.notifyChanged();
  }

  /// RELINK-2: pool paths that were not on disk as of the last refresh.
  ///
  /// CACHED rather than probed per row. The media pool used to call
  /// `File.existsSync()` while building every row, and the loss banner
  /// would have multiplied that — a banner has to count the WHOLE pool, so
  /// one repaint became one disk hit per asset.
  ///
  /// Nothing polls. This is refreshed when the project opens, after
  /// anything that moves files, and when the user asks — the three moments
  /// where the answer can actually have changed.
  Set<String> get missingMediaPaths => _missingMediaPaths;
  Set<String> _missingMediaPaths = const <String>{};

  /// Test seam for the existence probe. Widget tests must not depend on
  /// what happens to exist on the machine running them.
  @visibleForTesting
  bool Function(String path)? debugMediaFileExists;

  /// When each pool file was last written, for the browser's rows.
  ///
  /// Filled by the same sweep that answers "is it still there", because
  /// the sweep is already touching every file: a row that asked the disk
  /// for its own date would turn one repaint into one stat per asset, and
  /// a panel repaints for reasons that have nothing to do with the file
  /// system (the same argument that moved the existence probe here).
  Map<String, DateTime> get mediaModifiedTimes => _mediaModifiedTimes;
  Map<String, DateTime> _mediaModifiedTimes = const <String, DateTime>{};

  /// Re-probes the pool. Notifies only when the answer changed, so calling
  /// it after an import that touched nothing missing is free.
  void refreshMediaExistence() {
    final probe =
        debugMediaFileExists ?? (String path) => File(path).existsSync();
    final missing = <String>{};
    final modified = <String, DateTime>{};
    for (final asset in mediaAssets) {
      if (!probe(asset.path)) {
        // The import original leaving is NOT "missing" for an asset whose
        // bytes the project holds — deleting the original is the very act
        // carrying exists to survive. Probing only the path put the "File
        // missing — relink it" banner on assets the project already owns
        // and fed them to the relink hunt, whose "success" would re-key
        // the asset and orphan what held its bytes.
        if (!_file.projectHoldsMediaBytes(asset.path)) {
          missing.add(asset.path);
        }
        continue;
      }
      try {
        modified[asset.path] = File(asset.path).lastModifiedSync();
      } on Object {
        // Present but unreadable — a network share mid-reconnect. The row
        // shows no date rather than a wrong one.
      }
    }
    if (setEquals(missing, _missingMediaPaths) &&
        mapEquals(modified, _mediaModifiedTimes)) {
      return;
    }
    // A path that came BACK (the share mounted, the drive returned) may
    // have burned its conform attempt budget while it was gone — three
    // "missing" answers and the clip stayed silent for the whole session
    // even after the file reappeared. Reappearing is the retry signal.
    for (final path in _missingMediaPaths) {
      if (!missing.contains(path)) {
        _conforms.invalidate(path);
      }
    }
    _missingMediaPaths = missing;
    _mediaModifiedTimes = modified;
    _changes.notifyChanged();
  }

  /// Where [path]'s conformed audio is on disk, building it if this machine
  /// has not yet — or null when the asset has no audio to conform.
  ///
  /// 🔑The pool panel's export asks for this and nothing else. Reading the
  /// conform, swapping the header and placing the file are three different
  /// jobs living in three different places already; what was missing was
  /// only the session saying WHICH file.
  Future<MediaByteSource?> conformBytesForExport(String path) async {
    final result = await _conforms.ensureFor(path);
    if (result == null || !result.isUsable) {
      return null;
    }
    return result.conformBytes;
  }

  /// Marks the [path] asset as one the project CARRIES — the per-asset
  /// promotion out of the media pool, and the answer to what a
  /// REFERENCE does when the user decides they want the project to own it
  /// after all.
  ///
  /// One undo step, and nothing on disk moves. Carrying used to mean a
  /// copy under `<project>.assets/Media/`, so this verb relinked every
  /// referencing clip onto the copy's path and invalidated its conform;
  /// it now means the next save writes the bytes INSIDE the `.anicel`,
  /// and the file stays exactly where it was. Same sound, same address —
  /// nothing to relink, nothing to re-conform.
  ///
  /// Returns false when there is nothing to promote: no such asset, or one
  /// already carried. A promotion that changed nothing must not spend an
  /// undo step saying so.
  ///
  /// 🪦It used to add「or a kind that is never carried whatever anyone
  /// picks」. That ceiling died 2026-08-14 — every kind carries now, and
  /// the kind only chooses the import window's default.
  ///
  /// ⛔ONE DIRECTION on purpose. Carrying is always safe; UN-carrying
  /// strands a project whose original has since been moved or deleted, so
  /// the two are not a pair of switches to offer side by side. A reverse
  /// verb needs a "the original is still there" guard of its own first,
  /// and that is a separate decision.
  ///
  /// ⚠️Async because securing the bytes runs in an isolate — see
  /// [MediaStagingStore.stageCarriedBytes]. The answer still means「something changed」, and
  /// it is still decided before any waiting happens.
  Future<bool> promoteMediaAssetIntoProject(String path) async {
    final pool = mediaAssets;
    var promotes = false;
    for (final asset in pool) {
      if (asset.path != path) {
        continue;
      }
      // Any kind: the kind decides the DEFAULT at import, and this verb is
      // the user changing their mind afterwards.
      promotes = !asset.carried;
      break;
    }
    if (!promotes) {
      return false;
    }
    // A carry of its own, even for a path carried once before and removed:
    // that one's bytes are an undo's to bring back ([MediaAsset.carriedAs]).
    final carriedAs = mintMediaCarry();
    await _staging.stageCarriedBytes([(poolPath: path, token: carriedAs)]);
    _project.cutCommandCoordinator.updateMediaAssets([
      for (final asset in pool)
        if (asset.path == path) asset.copyWith(carriedAs: carriedAs) else asset,
    ], description: 'Register media in project');
    _changes.notifyChanged();
    return true;
  }

  /// Links the pool asset at [path] to the SE block of [layerId] starting
  /// at [blockStartFrame] (the browser's drag-drop target hook). The block
  /// carries the sound exactly like an import at that spot; unknown pool
  /// paths register first (their own undo step, same as import).
  void linkMediaAssetToSeBlock({
    required LayerId layerId,
    required int blockStartFrame,
    required String path,
  }) {
    final layer = _project.layerById(layerId);
    // An SE row holds sounds: a picture's path is no clip to link.
    if (layer == null ||
        layer.kind != LayerKind.se ||
        mediaAssetKindForPath(path) != MediaAssetKind.audio) {
      return;
    }
    FrameId? frameId;
    for (final block in drawingBlocks(layer.timeline)) {
      if (block.startIndex == blockStartFrame) {
        frameId = block.frameId;
        break;
      }
    }
    if (frameId == null) {
      return;
    }
    final resolvedFrameId = frameId;
    // The same frame already carrying this sound is a no-op (a second link
    // would double the playback).
    if (layer.audioClips.any(
      (clip) => clip.filePath == path && clip.frameId == resolvedFrameId,
    )) {
      return;
    }
    unawaited(addMediaAssets([path]));
    _project.cutCommandCoordinator.updateLayerAudioClips(
      cutId: _project.requireActiveCut.id,
      layerId: layerId,
      audioClips: [
        ...layer.audioClips,
        AudioClip(filePath: path, frameId: resolvedFrameId),
      ],
      description: 'Link sound',
    );
    _changes.notifyChanged();
  }

  /// Kicks [sourcePath]'s conform and returns the path the project records
  /// for it — the file where the user keeps it, whichever way the import
  /// window's carry-or-reference switch is set.
  ///
  /// CARRYING used to mean a second copy on disk under
  /// `<project>.assets/Media/`, and that copy was the last thing making a
  /// `.anicel` grow a sibling folder. It now means the save writes the
  /// bytes INSIDE the archive, so the choice is recorded as
  /// [MediaAsset.carried] — where a choice belongs — instead of being
  /// smuggled into the path and read back off it later.
  String importAudioFile(String sourcePath) {
    final effectivePath = normalizedMediaPath(sourcePath);
    // Fresh conform + waveform budget: on a re-import the file may have
    // changed on disk. (A byte-identical reused copy re-fingerprints
    // against the existing conform and lands as `reused` without a
    // decode.)
    _conforms.invalidate(effectivePath);
    _conforms.warmPaths([effectivePath]);
    return effectivePath;
  }

  /// The media pool's import: same carry-or-reference choice as a
  /// timeline import, pool only (no clip link). Non-audio kinds register
  /// with their detected kind (R3b), and the batch is one undo step — held
  /// before it is recorded, like every import ([_admit]).
  ///
  /// A path [cutFrom] names is a trimmed file's PIECE ([TrimmedPieces]),
  /// and the file it names is where the piece was cut from: provenance
  /// only, as a placed piece's is.
  Future<void> importMediaFiles(
    List<String> paths, {
    required bool copyIntoProject,
    Map<String, String> cutFrom = const {},
  }) {
    final known = {for (final asset in mediaAssets) asset.path};
    final entries = <MediaAsset>[];
    for (final path in paths) {
      final source = normalizedMediaPath(path);
      final kind = mediaAssetKindForPath(source) ?? MediaAssetKind.image;
      if (kind == MediaAssetKind.audio) {
        importAudioFile(source);
      }
      if (!known.add(source)) {
        continue;
      }
      entries.add(
        importedMediaAsset(
          path: source,
          kind: kind,
          fit: MediaFitMode.contain,
          sourcePath: cutFrom[path],
          // Answers "which file is this?", so it is stamped for a carried
          // asset and a reference alike — a reference is exactly the one
          // that can go missing and have to be found again, and a carried
          // asset still has an original on disk until the first save.
          identity: readMediaIdentity(source),
          // What the user asked for. The kind still decides whether it CAN
          // be carried, and NEITHER is a path any more: every import
          // records the file where the user keeps it, and the save reads
          // this to decide whose bytes travel inside the archive.
          carried: copyIntoProject,
        ),
      );
    }
    return _admit(entries);
  }
}
