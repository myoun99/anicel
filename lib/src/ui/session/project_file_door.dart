// The .anicel door: everything that writes this session into a file, or
// reads one back into it.
//
// Its own object since round 8 (G1, 2026-09-06). Like
// [EditorVoiceRecording], it did not come free — its constructor lists the
// session members a save and an open actually touch, and that list IS the
// coupling this block always had. What it no longer does is own the
// FACTS: which file, what it carries, whether anything is unsaved and
// whether the autosave tick may run all live in [ProjectFile], which
// this pushes into.

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/brush_frame_key.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/frame_id.dart';
import '../../models/project.dart';
import '../../services/brush_frame_store.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/project_media_sources.dart'
    show ProjectConforms, mediaEntryNamesFor, projectMediaSources;
import '../../services/persistence/anicel_file_service.dart';
import '../../services/persistence/anicel_project_archive.dart'
    show AnicelSessionFields, remapProjectMediaPaths;
import '../../services/persistence/coordinated_project_swap.dart';
import '../../services/persistence/folder_grant.dart'
    show FolderPicker, MaterializeCancelled;
import '../../services/persistence/media_staging_store.dart';
import '../../services/persistence/session_scratch.dart';
import '../../services/persistence/open_project_file.dart';
import '../../services/project_lookup.dart'
    show cutPositionOf, projectAudioSourcePaths;
import 'project_resume.dart';
import '../audio/audio_conform_store.dart';
import 'frame_clipboard.dart';
import 'layer_clipboard.dart';
import 'media_fingerprint_ledger.dart';
import 'media_grant_ledger.dart';
import 'media_pool.dart';
import 'project_file.dart';
import 'visibility_solo.dart';
import 'playback_rig.dart';
import 'render_caches.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'live_stroke_landing.dart';

/// What every road of a save carries besides its path: THE PROJECT IT IS
/// WRITING, the media the archive stores, the conforms beside them, and
/// the reporter the UI gave it. Made once per save — by
/// [ProjectFileDoor._carryFor], the only place that reads either — and
/// handed whole, so the four roads cannot disagree about what a save is.
typedef _SaveCarry = ({
  Project project,
  Map<String, MediaByteSource> mediaToStore,
  ProjectConforms conforms,
  void Function(double)? onProgress,
});

/// What [ProjectFileDoor.writeArchiveCopy] wrote, and everything
/// [ProjectFileDoor.adoptPlacedArchive] needs to make that archive the
/// project: the media entry names it stored, and the edit count it is clean
/// as of ([ProjectFile.bindToSavedFile]).
typedef StagedArchive = ({Map<String, String> entryNames, int cleanAsOf});

/// Saves the session into a `.anicel` and opens one back.
/// Who asked for a save — the ONE thing the two entrances disagree about.
///
/// 🚨★★★**IT EXISTS SO THAT NOBODY HAS TO INFER IT.** The distinction was
/// already there and already load-bearing (a manual save puts a window in
/// front of itself, the tick does not), but it was readable only as 「is
/// `onProgress` non-null」 — a flag that means 「somebody wants a progress
/// bar」 being asked a second question it never agreed to answer. Naming it
/// costs one required parameter and makes a new call site state its case
/// instead of inheriting whichever answer the last author happened to get.
enum SaveAsked {
  /// A person pressed Save (the menu, the shortcut, the unsaved-work
  /// prompt). They are waiting, and whatever the pen is holding is part of
  /// what they asked to keep.
  byAPerson,

  /// The autosave clock came due. Nobody is watching, and the user may
  /// have a pen down — see [ProjectFileDoor._settleWorkInFlight].
  byTheClock,
}

class ProjectFileDoor {
  ProjectFileDoor({
    required ProjectFile file,
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required PlaybackRig playbackRig,
    required RenderCaches renderCaches,
    required MediaStagingStore staging,
    required MediaGrantLedger grants,
    required MediaFingerprintLedger fingerprints,
    required FrameClipboard clipboard,
    required LayerClipboard layerClipboard,
    required AudioConformStore audioConformStore,
    required ValueNotifier<int> frameSeekCommitted,
    required MediaPool mediaPool,
    required LiveStrokeLanding liveStrokeLanding,
    required VisibilitySolo solo,
  }) : _file = file,
       _project = project,
       _solo = solo,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _controllers = controllers,
       _playbackRig = playbackRig,
       _renderCaches = renderCaches,
       _staging = staging,
       _grants = grants,
       _fingerprints = fingerprints,
       _clipboard = clipboard,
       _layerClipboard = layerClipboard,
       _audioConformStore = audioConformStore,
       _frameSeekCommitted = frameSeekCommitted,
       _mediaPool = mediaPool,
       _liveStrokeLanding = liveStrokeLanding;

  final ProjectFile _file;
  final ProjectAccess _project;

  /// 🚨Here for ONE question — what the eyes said before the solo — asked
  /// in [_carryFor]. See the law there.
  final VisibilitySolo _solo;

  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final PlaybackRig _playbackRig;
  final RenderCaches _renderCaches;
  final MediaStagingStore _staging;
  final MediaGrantLedger _grants;
  final MediaFingerprintLedger _fingerprints;
  final FrameClipboard _clipboard;
  final LayerClipboard _layerClipboard;
  final AudioConformStore _audioConformStore;
  final ValueNotifier<int> _frameSeekCommitted;
  final LiveStrokeLanding _liveStrokeLanding;
  final MediaPool _mediaPool;

  static const AnicelFileService _anicelFileService = AnicelFileService();

  /// The four cel stores an archive holds, in the order every writer
  /// lists them: the drawings, then the two conte ink namespaces, then
  /// the cut envelope's.
  List<BrushFrameStore> get _auxCelStores => [
    _renderCaches.conteInkRowStore,
    _renderCaches.conteInkPageStore,
    _renderCaches.envelopeInkStore,
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

  /// Saves the project + every drawn frame into ONE .anicel file (atomic
  /// temp-then-rename write; media stays external with relative paths
  /// recorded for Drive portability).
  ///
  /// 🚨★★★**THE ONE WRITER, AND THE AUTOSAVE TICK IS NOW ONE OF ITS
  /// CALLERS** (유저 2026-09-07). There is no second path that writes the
  /// user's work to disk any more — the tick calls this, minus the window.
  ///
  /// [onProgress] is called with 0..1 as the write proceeds, for the window
  /// a manual save puts in front of itself. Omitted by the autosave tick,
  /// which nobody is watching.
  /// **EVERYTHING IN FLIGHT LANDS HERE, AND THIS IS THE ONLY PLACE THAT
  /// LIST EXISTS.** The first statement of every writer.
  ///
  /// 🚨★★★**BEFORE THE STORE SNAPSHOTS, AND THAT ORDER IS THE POINT.** The
  /// snapshot records each cel's edit tick, and
  /// `BrushFrameStore.adoptSavedFile` refuses to mark clean anything whose
  /// tick moved past it — so work that lands one line later is correctly
  /// kept dirty for the NEXT save, and correctly missing from the file the
  /// user just asked for. Landing it first is what puts it in this one.
  ///
  /// ⛔**IT IS ONE VERB BECAUSE IT WAS ONE LAW WRITTEN TWICE.** The text
  /// bake flush stood at the head of both writers, and the pen landing was
  /// about to stand beside it in both — four call sites for 「settle what
  /// is in flight」, and the fifth kind of in-flight work would have had to
  /// find all four. It finds this instead.
  ///
  /// **The pen** — 유저 2026-09-10: 「그냥 스트로크 커밋시키고 저장로직
  /// 발동시키면 되는거아닌가?」. Press Ctrl+S with the pen down and the
  /// stroke used to reach the cel after the snapshot, so the file the user
  /// asked for did not have the line they were drawing when they asked.
  ///
  /// ⛔**ONLY WHEN A PERSON ASKED.** The autosave tick runs with no window
  /// and nobody watching, so the user may be mid-stroke when it fires;
  /// ending their stroke under their hand would split one line into two,
  /// with two undo entries. [AutosaveClock] already answers that case the
  /// right way — it HOLDS the fire until the pen lifts — and the residual
  /// race (a stroke that starts after the fire) costs nothing, because a
  /// save is clean only as of the edits it captured before reading the
  /// project ([ProjectFile.bindToSavedFile]'s `cleanAsOf`): the stroke stays
  /// unsaved, for the next save and for the close. 🪦Until F-128 this
  /// sentence was false — the save cleared the mark at its end, stroke or
  /// no stroke.
  ///
  /// ⚠️[SaveAsked] is required rather than derived so a new caller has to
  /// answer the question. ⛔It must never be read off `onProgress`, which
  /// happens to be non-null for exactly the manual saves today: that would
  /// be one flag answering two questions, and the day a tick wanted
  /// progress the pen would start landing under it.
  ///
  /// ⚠️The pen goes FIRST and synchronously. Its landing is the pointer-up
  /// path's own four-step sequence, which finishes inside one event;
  /// putting an await in front of it would reopen the window this closes.
  ///
  /// Returns the edit count the save is clean as of — counted once what was
  /// in flight has landed and before anything reads the project. Counted
  /// HERE and nowhere else, so a writer that settles cannot forget to count
  /// ([ProjectFile.bindToSavedFile]).
  Future<int> _settleWorkInFlight(SaveAsked asked) async {
    if (asked == SaveAsked.byAPerson) {
      _liveStrokeLanding.landNow();
    }
    return _file.editCount;
  }

  Future<void> saveProjectToFile(
    String filePath, {
    required SaveAsked asked,
    void Function(double)? onProgress,
  }) async {
    // Raised for the WHOLE save, so a tick that comes due inside one stands
    // down instead of starting a SECOND write of the same file — an
    // incremental append reads the tail it is about to extend, and two of
    // them interleaving is a torn archive rather than a lost edit.
    _file.beginSave();
    // The breadcrumb a silent kill cannot erase. A save is the work this
    // app is most likely to die inside — and when iOS kills for memory
    // there is no exception, no crash report, and nothing in App Store
    // Connect (실기 08-27: three kills, an iPad that survived the same
    // press, and not one line of evidence anywhere). An entry with no END
    // at the next launch is the only thing that says otherwise.
    MemoryBlackBox.begin('save');
    try {
      await _writeProjectToFile(filePath, asked: asked, onProgress: onProgress);
    } finally {
      _file.endSave();
      MemoryBlackBox.end('save');
    }
  }

  /// Writes the CURRENT state to [path] as a complete, standalone archive
  /// and changes NOTHING about this session — no path adoption, no ref
  /// adoption, no dirty-flag movement. The Save As STAGING
  /// writer on scoped platforms: the file this produces is about to be
  /// MOVED by a document picker, so anything the session learned from it
  /// would name a path that stops existing moments later.
  ///
  /// It does REPORT what it could not carry, in [celsLostToAMissingFile] —
  /// the one thing the person must hear either way (F-72: a copy one cel
  /// short said nothing, and the previous save's answer stood in for it).
  ///
  /// 🚨 Exists because of the 22-byte placeholder this replaces (실측
  /// iPhone+Drive, 08-26): a provider that refuses in-place writes made
  /// the post-placement save fail, and what the picker had placed was the
  /// EMPTY placeholder — an unopenable husk where the user meant to put
  /// their project. A complete archive staged up front costs the same
  /// move and can never strand a husk.
  /// Returns what [adoptPlacedArchive] needs if this copy becomes the
  /// project: the media entry names it was written with, and the edit count
  /// it is clean as of.
  Future<StagedArchive> writeArchiveCopy(
    String path, {
    required SaveAsked asked,
    void Function(double)? onProgress,
  }) async {
    final cleanAsOf = await _settleWorkInFlight(asked);
    final carry = _carryFor(onProgress: onProgress);
    celsLostToAMissingFile = await _saveArchive(path, carry, adoptRefs: false);
    return (
      entryNames: mediaEntryNamesFor(carry.mediaToStore),
      cleanAsOf: cleanAsOf,
    );
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
    required StagedArchive staged,
  }) {
    _file.bindToSavedFile(
      placedPath,
      entryNames: staged.entryNames,
      cleanAsOf: staged.cleanAsOf,
    );
    _changes.notifyChanged();
  }

  /// The provider-refusal fallback: a complete archive written into THIS
  /// RUN'S 이사대기 room, then swapped over [filePath] by the platform's
  /// file coordinator.
  ///
  /// 🚨**THE ROOM IS THE LIFETIME THIS NEEDS.** The refs the staging save
  /// adopts are valid only while the staging file is there, and a session
  /// holds them until it ends — which is exactly when the room goes. It
  /// used to be written into the Recovery folder and left for that
  /// folder's 30-day sweep, which outlived the need by a month and, once
  /// the snapshots were deleted, named a folder nothing else wrote to.
  ///
  /// The staging save ADOPTS normally. After a
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
  ///
  /// Answers what the staging save could not carry, as the direct save
  /// does — this path used to drop the answer (F-72).
  Future<Set<BrushFrameKey>> _saveViaCoordinatedReplace(
    String filePath,
    _SaveCarry carry,
  ) async {
    final stagingDirectory = Directory(SessionScratch.stagedFolder())
      ..createSync(recursive: true);
    final staging =
        '${stagingDirectory.path.replaceAll('\\', '/')}'
        '/replace.tmp-${DateTime.now().microsecondsSinceEpoch}';
    final lost = await _saveArchive(staging, carry);
    await _swapIn(from: staging, to: filePath);
    return lost;
  }

  /// Every save where the platform has a file coordinator: the ordinary
  /// save — an append in place, or a whole archive — with the coordinator
  /// told what happened. An append is followed by a coordinated touch; a
  /// whole write is left BESIDE the file by the service and swapped in
  /// through the coordinator (`.forReplacing`, a move on the same volume —
  /// what a plain rename cost), then the refs are repointed.
  ///
  /// A location that refuses even the temp beside the file (a file-scoped
  /// grant reaches the item and nothing next to it) throws out of the
  /// service, and the staging road takes over — the same swap, from this
  /// run's own room.
  Future<Set<BrushFrameKey>> _saveCoordinated(
    String filePath,
    _SaveCarry carry, {
    required bool rewriteWhole,
  }) async {
    String? leftBeside;
    final Set<BrushFrameKey> lost;
    try {
      lost = await _saveArchive(
        filePath,
        carry,
        rewriteWhole: rewriteWhole,
        onFullWriteLeftAt: (tempPath) => leftBeside = tempPath,
      );
    } on FileSystemException {
      return _saveViaCoordinatedReplace(filePath, carry);
    }
    final temp = leftBeside;
    if (temp == null) {
      // Appended in place: the item's content changed — said through the
      // coordinator, the one voice a provider hears. Best-effort by nature:
      // the append has landed whatever the answer, and there is nothing
      // else to do with a refusal but carry on.
      await FolderPicker.touchFileCoordinated(filePath);
      return lost;
    }
    await _swapIn(from: temp, to: filePath);
    return lost;
  }

  /// 🚨★★★**THE FILE NEVER SEES A VIEW STATE.** What this save is writing,
  /// decided ONCE — and the only place the door reads the project for a
  /// write at all, so no road can reach past it.
  ///
  /// 🗣️유저 2026-09-18 (F-153): 「활성레이어 솔로는 **저장시 저장안되도록**.
  /// 지금 솔로 on한상태로 저장하고 열면 **적용된채로 모드는 off**되있는
  /// 상태」 — answered on `solo-and-the-saved-file` with 「**저장이 솔로
  /// 이전의 눈을 기록한다**」.
  ///
  /// The solo really does flip the rows' eyes — 유저's own rule (「REAL eye
  /// flips」, 2026-08-29) — so a save cannot just decline to look at them.
  /// It asks the thing that already knows what they were:
  /// [VisibilitySolo.projectAsSavedWithoutSolo], which is identity when no
  /// solo is up.
  ///
  /// ⛔ONE read, not one per road. The media sources are resolved from the
  /// SAME project, and [_saveArchive] writes it — three roads answered
  ///「which project」 for themselves before this, and each was a place that
  /// could have kept the solo's eyes.
  ///
  /// The media is resolved against the CURRENT project path, before it
  /// moves. On a save-as that makes each source point into the file being
  /// left behind, and the writer streams from there into the new one —
  /// which is how a copy carries its media without a copy step of its own.
  ///
  /// ⚠️Call it AFTER `_settleWorkInFlight`: what is still in flight is not
  /// in the project yet.
  _SaveCarry _carryFor({void Function(double)? onProgress}) {
    final project = _solo.projectAsSavedWithoutSolo(
      _project.repository.requireProject(),
    );
    return (
      project: project,
      mediaToStore: projectMediaSources(
        project: project,
        projectFilePath: _file.path,
        mediaEntryNames: _file.mediaEntryNames,
        staging: _staging,
      ),
      conforms: _file.conformsToStore(),
      onProgress: onProgress,
    );
  }

  /// THE save call, once. Four sites used to build it — the direct save,
  /// the staging road, the coordinated road and the door's own writer —
  /// and the clone gate counted the fourth (2026-09-13). What differs per
  /// road is the path, whether a Save As forces a whole write, whether the
  /// caller takes the swap, and whether the session adopts what was
  /// written; everything else is this session's.
  ///
  /// The Save As staging copy was a fifth, still spelling the call for
  /// itself to say `adoptRefs: false`. It goes through here now (F-123,
  /// 2026-09-15): a field the session adds to every save would otherwise
  /// have had to be remembered there as well.
  Future<Set<BrushFrameKey>> _saveArchive(
    String filePath,
    _SaveCarry carry, {
    bool rewriteWhole = false,
    bool adoptRefs = true,
    void Function(String tempPath)? onFullWriteLeftAt,
  }) => _anicelFileService.save(
    project: carry.project,
    brushFrameStore: _renderCaches.brushFrameStore,
    auxCelStores: _auxCelStores,
    filePath: filePath,
    mediaToStore: carry.mediaToStore,
    conforms: carry.conforms,
    sessionFields: AnicelSessionFields(
      grants: _grants.grantsToStore(),
      mediaCrcs: _fingerprints.crcsToStore(),
      resume: _whereTheWorkStands().toJson(),
    ),
    onProgress: carry.onProgress,
    heldEntries: _file.heldArchiveEntries,
    adoptRefs: adoptRefs,
    rewriteWhole: rewriteWhole,
    onFullWriteLeftAt: onFullWriteLeftAt,
  );

  /// What the tools are holding — read at each save and put back on open by
  /// whoever holds them: the shell's tool notifier and the workspace's
  /// preset library, neither of which the door can reach. Null until the
  /// workspace installs it; a session with no workspace carries no tools.
  ToolChoiceBridge? toolChoice;

  /// Where the work stands right now, as every save writes it beside the
  /// project (F-123) — read as the save is made, so the file holds the place
  /// the person pressed Save from.
  ProjectResume _whereTheWorkStands() => ProjectResume(
    cutId: _timeline.editingSession.activeCutId,
    layerId: _selection.activeLayerId,
    frameIndex: _selection.currentFrameIndex,
    tools: toolChoice?.read() ?? const {},
  );

  Future<void> _swapIn({required String from, required String to}) =>
      replaceProjectFileCoordinated(
        from: from,
        to: to,
        stores: [_renderCaches.brushFrameStore, ..._auxCelStores],
      );

  Future<void> _writeProjectToFile(
    String filePath, {
    required SaveAsked asked,
    void Function(double)? onProgress,
  }) async {
    final cleanAsOf = await _settleWorkInFlight(asked);
    // Captured BEFORE the save moves the project path — it is what tells a
    // Save As from an ordinary save, which decides `rewriteWhole` below.
    // 🪦The comment here said 「a Save As has to retire the sidecars of the
    // file it was saved FROM as well」; the retirement is gone and the
    // capture stayed, for the reason further down.
    final previousPath = _file.path;
    final carry = _carryFor(onProgress: onProgress);
    final mediaToStore = carry.mediaToStore;
    // 🚨A Save As is「writing somewhere else」and nothing more subtle: the
    // target is not the file this session has been saving to. 유저
    // 2026-08-31 asked for it to be a full write every time — 「기존 파일에
    // 저장 덮어씌우기를 하더라도 고치기위해 풀저장」 — and the case that was
    // NOT already whole is exactly this one, an overwrite onto an older copy
    // of the same project.
    final saveAs =
        previousPath != null &&
        previousPath.replaceAll(r'\', '/') != filePath.replaceAll(r'\', '/');
    // 🎯ONE LAW FOR A GRANTED PATH: where the platform has a file
    // coordinator, every write ends in it — an append is followed by a
    // coordinated touch, a whole write is swapped in through a coordinated
    // `.forReplacing` move. A rename the provider happens to allow but is
    // never told about changes the file on disk and uploads nothing: the
    // iPad's saves「landed」and Drive's modified date never moved (M-1,
    // 2026-09-11). ⛔Not by what the path is:「provider item or not」was the
    // first draft and it was two rules for one write (유저 2026-09-13); a
    // local file pays nothing for coordination, so nothing is asked.
    if (FolderPicker.hasFileCoordinator) {
      celsLostToAMissingFile = await _saveCoordinated(
        filePath,
        carry,
        rewriteWhole: saveAs,
      );
    } else {
      try {
        celsLostToAMissingFile = await _saveArchive(
          filePath,
          carry,
          rewriteWhole: saveAs,
        );
      } on FileSystemException {
        // A scoped platform WITHOUT a coordinator (Android) still reaches
        // the staging road, where the coordinated replace answers false
        // and the refusal is reported in full; a desktop refusal (locked
        // file, dead drive) has nothing to appeal to and stays loud.
        if (!FolderPicker.grantsAreScoped) {
          rethrow;
        }
        celsLostToAMissingFile = await _saveViaCoordinatedReplace(
          filePath,
          carry,
        );
      }
    }
    // 🚨The save ABSORBED the staged bytes, so the staged copy stops being
    // anything — 유저 08-27: 「사본 남으면 진짜 용서안할게」. Retired HERE
    // rather than on close or on import-undo, because this is the one
    // moment the bytes provably live somewhere else. The save's own step,
    // so it stays here rather than joining the binding below.
    for (final path in mediaToStore.keys) {
      _staging.retire(path);
    }
    _file.bindToSavedFile(
      filePath,
      entryNames: mediaEntryNamesFor(mediaToStore),
      cleanAsOf: cleanAsOf,
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

  /// Makes the session let go of the conforms whose PCM lives only on
  /// disk — ON PROJECT OPEN ONLY.
  ///
  /// A conform past the streaming threshold is held with no resident PCM
  /// and the file as the copy of record, so a session that opened another
  /// project would keep readers on bytes the new project has no business
  /// with. See [AudioConformStore.releaseDiskBacked].
  ///
  /// 🪦It used to run the cache collector here too, and the doc explained
  /// why open was the right moment to enforce a size bound. There is no
  /// bound and no collector: a conform waits in the RUN'S room and the
  /// room goes when the run does, so nothing accumulates to collect.
  ///
  /// ⚠️ Deliberately NOT switched off under `FLUTTER_TEST` — a call site
  /// compiled out of every test is a call site with no observer, which is
  /// how the path assembly went unwatched before
  /// ([[verify-before-claiming-shared]]).
  void settleConformCache() {
    _audioConformStore.releaseDiskBacked();
  }

  /// Opens a .anicel file, replacing the WHOLE session state: project,
  /// drawings, selection (first cut, frame 0) — and BOTH undo stacks
  /// (loaded state has no history; the load→draw→undo path is pinned by
  /// test).
  ///
  /// Reads [filePath]; the session is BOUND to [bindTo] when the bytes came
  /// from somewhere other than the project's own address — a local staged
  /// copy of a cloud file that refused a direct read, where saves still
  /// have to go back to the real one.
  ///
  /// 🚨A session bound elsewhere counts as UNSAVED. The archive it is
  /// reading its cels out of is a temp the app made, so a save is what puts
  /// those pixels back at the address the user knows.
  ///
  /// 🪦Two parameters stood beside [bindTo] until 2026-09-08 — `recoverAs`,
  /// which is what [bindTo] used to be called when the autosave recovery
  /// flow was its main caller, and `overlayPath`, which laid a snapshot
  /// over the base. Both are gone with the sidecars, and so is the
  /// FormatException that refused an overlay fed through the
  /// whole-archive arm. ⛔The rename is the point: one name was answering
  /// 「which file do I save back to」 and 「is this a recovery」 at once.
  Future<void> openProjectFromFile(
    String filePath, {
    String? bindTo,
    bool Function()? isCancelled,
  }) async {
    final result = await _anicelFileService.open(
      filePath: filePath,
    );
    // The read is the wait, and nothing has been applied yet: a press on
    // the wait window's Cancel during it is honoured HERE, at the last
    // moment it still means「nothing changed」— past this line the project
    // lands. The same answer the materializer gives for the same press.
    if (isCancelled?.call() ?? false) {
      throw const MaterializeCancelled();
    }
    _playbackRig.playback.stop();
    // BEFORE the project lands: a bookmark tracks the file rather than the
    // path, so resolving one is how a referenced movie that was renamed or
    // moved is found again — and the project has to be told, or the pool
    // goes on naming an address nothing answers at. This is the same move
    // the relative-path remap above makes, at the same moment, for the
    // same reason.
    final movedByGrant = await _grants.resolveMediaGrants(
      result.session.grants,
    );
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
    _fingerprints.restoreFromFile(
      result.session.mediaFingerprints.moved(movedByGrant),
    );
    // R22-C: opens land every cel FILE-BACKED — pixels stay in the .anicel
    // until a cel is first shown (near-zero RAM for 1500-cut projects).
    // The conte ink namespace routes to its own stores (R5); a ROW entry
    // whose storyboard block no longer exists in the loaded project is
    // pruned HERE — the load boundary is where "ink dies with the
    // drawing" becomes permanent (saving never prunes, so an undone
    // delete keeps its ink within the session).
    final cels = _sortLoadedCels(result);
    _renderCaches.brushFrameStore.restoreFromFile(cels.main);
    final healed = _healStaleCelSizes(
      cels.main,
      project: result.project,
      store: _renderCaches.brushFrameStore,
    );
    _renderCaches.conteInkRowStore.restoreFromFile(cels.inkRow);
    _renderCaches.conteInkPageStore.restoreFromFile(cels.inkPage);
    _renderCaches.envelopeInkStore.restoreFromFile(cels.envelope);
    // Held from now on, not from the first cel read — see
    // [OpenProjectFile.hold] for the gap that left.
    OpenProjectFile.instance.hold(filePath);
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
    // Where the work stood when it was saved (F-123) — each part only if this
    // project still has it: a cut that is gone opens on the first cut, as a
    // file without the part does; a row that is gone lands on the top row,
    // the rebuild's own fallback; the frame lands inside the cut through the
    // rebuild's own clamp.
    final resume = ProjectResume.fromJson(result.session.resume);
    final savedCut = resume.cutId;
    _timeline.editingSession.setActiveCutId(
      savedCut != null && cutPositionOf(result.project, savedCut) != null
          ? savedCut
          : result.project.tracks.first.cuts.first.id,
    );
    _controllers.rebuild(
      preferredActiveLayerId: resume.layerId,
      preferredFrameIndex: resume.frameIndex,
    );
    toolChoice?.resume(resume.tools);
    _file.bindToOpenedFile(
      bindTo ?? filePath,
      // What this project carries, as the file on disk says. Anything the
      // pool names that is NOT here is an ordinary outside reference and
      // resolves by path like it always did.
      entryNames: result.mediaEntryNames,
      // Dirty when the cels are being read out of a staged copy rather than
      // the project's own address — and when the load just HEALED
      // mismatched cels, where memory no longer matches the file (R7q2).
      unsaved: bindTo != null || healed,
    );
    settleConformCache();
    warmAudioConforms();
    // RELINK-2: the first of the three refresh moments. A project opened
    // on a machine that does not have its referenced media has to SAY so —
    // that is the whole point of the banner, and it is the one moment the
    // user has not done anything to prompt it.
    _mediaPool.refreshMediaExistence();
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
