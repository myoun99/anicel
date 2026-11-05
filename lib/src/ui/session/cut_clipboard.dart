import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../services/commands/cut_insertion.dart' show CutLanding;
import '../../services/media/media_byte_source.dart' show MediaByteSource;
import '../../services/persistence/media_staging_store.dart';
import '../../services/project_lookup.dart' show cutPositionOf;
import '../../services/wait_window.dart' show drawingsOf;
import 'cut_copies.dart';
import 'cut_placement.dart';
import 'cut_verbs.dart';
import 'render_caches.dart';
import 'session_roles.dart';
import 'storyboard_rows.dart';
import 'what_a_copy_brings.dart';

/// The CUT CLIPBOARD — the cuts the user copied, and putting them down on a
/// track, each a cut of its own or a 겸용 cut of the one it copies.
///
/// 🗣️I-150 (유저 2026-11-03): 「컷 잘라내기/복사/붙여넣기/링크붙여넣기등
/// 공용알약 사용 가능하게. 병합만 불가능? 우선은?」 · 「링크붙여넣기는 물론
/// 겸용컷으로 만들면서 붙여넣는단느낌. 그리고 이를 통해 다른트랙에도
/// 링크붙여넣기 가능. 즉 다른트랙에 겸용컷만드는게 가능」 · 「다른트랙에 블록
/// 복사해서 붙여넣는다던가 전부 가능하게」.
///
/// The layer board's twin ([LayerClipboard]) at the cut's scale. What it
/// holds is BY VALUE — the cuts as they stood and what they showed
/// ([CutCopies.shownBy]) — so a paste lands after its sources were drawn
/// over or cut away, in another timeline, or in another project with the
/// media and the terms their rows name (I-7, [HeldArrival]). A LINKED paste
/// is 겸용컷 생성 where the paste lands, which serves the project the cuts
/// were copied in, while they still stand there.
class CutClipboard implements BringsMedia {
  CutClipboard({
    required CutBoard board,
    required ProjectAccess project,
    required ChangeSink changes,
    required CutVerbs cutVerbs,
    required StoryboardRows storyboardRows,
    required CutPlacement placement,
    required RenderCaches renderCaches,
    required MediaByteSource Function(String poolPath) mediaBytesOf,
    required MediaStagingStore staging,
  }) : _board = board,
       _project = project,
       _changes = changes,
       _cutVerbs = cutVerbs,
       _storyboardRows = storyboardRows,
       _placement = placement,
       _mediaBytesOf = mediaBytesOf,
       _staging = staging,
       _copies = CutCopies(project: project, renderCaches: renderCaches);

  /// The app's cut board ([CutBoard]) — every open project's clipboard
  /// reads and writes the same one (I-7).
  final CutBoard _board;
  final ProjectAccess _project;
  final ChangeSink _changes;

  /// The cuts in hand ([CutVerbs.cutsInHand]), and the delete a 잘라내기
  /// lifts them with.
  final CutVerbs _cutVerbs;

  /// The band of cuts a paste lands after.
  final StoryboardRows _storyboardRows;

  /// Where a paste lands with no band: where a new cut would.
  final CutPlacement _placement;

  /// Where this project keeps a medium's bytes ([CopiedNames.bytesOf]).
  final MediaByteSource Function(String poolPath) _mediaBytesOf;

  /// Where a paste from another project stages the media it carries in.
  final MediaStagingStore _staging;

  /// What a cut shows, taken and put down ([CutCopies]).
  final CutCopies _copies;

  /// What a wait held for the next paste of the board's copy.
  final HeldArrival _held = HeldArrival();

  /// Whether the hand holds cuts — what a paste puts down.
  bool get holdsCuts => _board._copy != null;

  /// The cuts in hand, as the project holds them now.
  List<Cut> get _cutsInHand => [
    for (final cutId in _cutVerbs.cutsInHand) ?_project.cutById(cutId),
  ];

  bool get canCopy => _cutsInHand.isNotEmpty;

  /// The drawings a copy — or a 잘라내기, which lifts all of them or none —
  /// takes: every row's of each cut in hand, the wait window's measure
  /// (`reachesManyBlocks`).
  Iterable<Object> get drawingsInHand =>
      drawingsOf([for (final cut in _cutsInHand) ...cut.layers]);

  /// The drawings a paste of the cuts on the board puts down, linked or not.
  Iterable<Object> get drawingsHeld => drawingsOf([
    for (final cut in _board._copy?.cuts ?? const <_CopiedCut>[])
      ...cut.source.layers,
  ]);

  void copy() {
    final cuts = _cutsInHand;
    if (cuts.isEmpty) {
      return;
    }
    _bank([for (final cut in cuts) _copyOf(cut)]);
  }

  /// Whether a 잘라내기 lifts the cuts in hand — the delete's own answer
  /// ([CutVerbs.canDeleteActiveCut]): the project keeps a cut.
  bool get canCut => _cutVerbs.canDeleteActiveCut;

  /// Lifts the cuts in hand as ONE step and puts them in hand.
  ///
  /// 🚨결정 14 ②ⓐ, the frame cut's law: a cut banks exactly what it lifts —
  /// and the delete lifts all of them, or none where the project would keep
  /// no cut ([canCut]). What they showed is read BEFORE the lift, while the
  /// stores hold it.
  void cut() {
    if (!canCut) {
      return;
    }
    final taken = [for (final cut in _cutsInHand) _copyOf(cut)];
    _cutVerbs.deleteActiveCut();
    _bank(taken);
  }

  /// Puts [copied] in hand, with what their rows name in this project.
  void _bank(List<_CopiedCut> copied) {
    final rows = [
      for (final cut in copied) ...cut.source.layers,
    ];
    _board._take(
      _CopiedCuts(
        from: this,
        cuts: copied,
        names: namesOfACopy(
          project: _project.repository.requireProject(),
          media: {
            for (final row in rows) ...{
              ?row.mediaReference?.assetPath,
              for (final sound in row.audioClips) sound.filePath,
            },
          },
          terms: {
            for (final row in rows)
              ...termsSpelledBy(row.timeline.values, row.instructions.values),
          },
          bytesOf: _mediaBytesOf,
        ),
      ),
    );
    _changes.notifyChanged();
  }

  _CopiedCut _copyOf(Cut cut) =>
      _CopiedCut(source: cut, pictures: _copies.shownBy(cut));

  /// WHERE A PASTE LANDS: right after the band of cuts when one is up —
  /// where a duplicate of them lands (F-455-Q1) — and elsewhere where a new
  /// cut would ([CutPlacement.cutCreationPlan]): in the gap the playhead
  /// is parked in or the range swept over, else right after the cut you
  /// stand in. Null where a new cut has no place.
  CutLanding? get _landing {
    final band = _storyboardRows.storyboardSelectedCutIds;
    if (band.isNotEmpty) {
      final last = cutPositionOf(
        _project.repository.requireProject(),
        band.last,
      );
      return last == null
          ? null
          : (
              trackId: last.trackId,
              index: last.cutIndex + 1,
              leadingGapFrames: 0,
            );
    }
    final plan = _placement.cutCreationPlan;
    if (plan == null) {
      return null;
    }
    return (
      trackId: plan.trackId,
      index:
          plan.index ??
          _project.cutCommandCoordinator.newCutIndexOn(plan.trackId),
      leadingGapFrames: plan.leadingGapFrames,
    );
  }

  /// [landing] for the cut [at] places into a block put down there: one
  /// after another, in the order they were copied, the first walking into
  /// the gap.
  static CutLanding _nth(CutLanding landing, int at) => (
    trackId: landing.trackId,
    index: switch (landing.index) {
      null => null,
      final index => index + at,
    },
    leadingGapFrames: at == 0 ? landing.leadingGapFrames : 0,
  );

  /// Whether a paste here must first HOLD the bytes of media the copy
  /// carries from another project — the UI's cue for its wait window
  /// (F-53: every wait has one).
  @override
  bool get pasteMustHoldMedia =>
      _held.mustHold(_board._copy, _project.repository.requireProject());

  /// Holds them — as carries of THIS project's own, staged before anything
  /// records them ([holdCarriedMediaOf]) — for the next paste of the copy.
  @override
  Future<void> holdWhatThePasteBrings() => _held.hold(
    _board._copy,
    _project.repository.requireProject(),
    _staging,
  );

  bool get canPaste => holdsCuts && _landing != null;

  /// The board's cuts, each a cut of its own, as ONE block where the paste
  /// lands ([_landing]) — its pictures and its sheets' handwriting along,
  /// as a duplicate's ([CutCopies]). ONE undo for the cuts and what they
  /// brought.
  void paste() {
    final copy = _board._copy;
    final landing = _landing;
    if (copy == null || landing == null) {
      return;
    }
    final arrival = _held.arrivalFor(
      copy,
      _project.repository.requireProject(),
    );
    _project.historyManager.runAsOneStep('Paste cuts', () {
      landArrival(_project, arrival);
      for (final (at, cut) in copy.cuts.indexed) {
        final landed = _project.cutCommandCoordinator.copyCut(
          _respelled(cut.source, arrival.respell),
          landing: _nth(landing, at),
        );
        _copies.carry(
          shown: cut.pictures,
          copy: landed.cutId,
          rows: landed.rows,
          cels: landed.minted,
        );
      }
    });
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  /// The board's cuts a LINKED paste makes 겸용 cuts of: those that still
  /// stand in the project they were copied in, in whichever of its
  /// timelines. A link is 「the same cel」 (I-7): a cut of another project
  /// has none of this one, though it may well wear the same id, and a cut
  /// that is gone has none to share.
  List<_CopiedCut> get _cutsToLink {
    final copy = _board._copy;
    if (copy == null || !identical(copy.from, this)) {
      return const [];
    }
    return [
      for (final cut in copy.cuts)
        if (_project.cutById(cut.source.id) != null) cut,
    ];
  }

  bool get canPasteLinked => _cutsToLink.isNotEmpty && _landing != null;

  /// Each of [_cutsToLink] put down linked, as ONE block where the paste
  /// lands in the timeline open now: a 겸용 cut of a cut that stands in it,
  /// made as the copy stands (`createLinkedCutAsItStands`, F-555), and of a
  /// cut of ANOTHER timeline the same cut made one of this one too — a
  /// 동기컷 (`CreateSyncedCutCommand`).
  ///
  /// 🗣️I-150-Q3 (유저 2026-11-03): 「일단 다른 타임라인끼리는 단순 겸용컷
  /// 작동안하게 … 이 동작을 겸용컷이라기보다 새 시스템으로」. A sync stands
  /// in a timeline once: a cut whose sync has a cut here already is made a
  /// 겸용 of that one.
  void pasteLinked() {
    final cuts = _cutsToLink;
    final landing = _landing;
    if (cuts.isEmpty || landing == null) {
      return;
    }
    _project.historyManager.runAsOneStep('Paste cuts linked', () {
      for (final (at, cut) in cuts.indexed) {
        final coordinator = _project.cutCommandCoordinator;
        switch (_standingHere(cut.source.id)) {
          case final here?:
            coordinator.createLinkedCutAsItStands(
              cut.source,
              sourceCutId: here,
              landing: _nth(landing, at),
              carry: (landed, replaced) => _copies.carry(
                shown: cut.pictures.withoutCels({
                  for (final MapEntry(key: cel, value: copy)
                      in landed.minted.entries)
                    if (replaced.contains(copy)) cel,
                }),
                copy: landed.cutId,
                rows: landed.rows,
                cels: landed.minted,
              ),
            );
          case null:
            coordinator.createSyncedCut(
              sourceCutId: cut.source.id,
              landing: _nth(landing, at),
            );
        }
      }
    });
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  /// [cutId] when it stands in the timeline open, else the cut of its sync
  /// that does — null when neither does.
  CutId? _standingHere(CutId cutId) {
    final project = _project.repository.requireProject();
    final here = {
      for (final track in project.tracks)
        for (final cut in track.cuts) cut.id,
    };
    if (here.contains(cutId)) {
      return cutId;
    }
    final sync = project.linkRegistry.syncOf(cutId)?.cuts ?? const [];
    return sync.where(here.contains).firstOrNull;
  }

  /// [cut] with its rows' terms spelled as [respell] says ([Arrival]). A
  /// row whose spans ride its blocks is respelled by its blocks.
  static Cut _respelled(Cut cut, Map<String, String> respell) {
    if (respell.isEmpty) {
      return cut;
    }
    Layer respelledRow(Layer row) => row.copyWith(
      timeline: row.timeline.map(
        (index, exposure) =>
            MapEntry(index, respelledExposure(exposure, respell)),
      ),
      instructions: row.kind.spansRideBlocks
          ? null
          : row.instructions.map(
              (index, span) => MapEntry(index, respelledSpan(span, respell)),
            ),
    );
    return cut.copyWith(
      layers: [for (final row in cut.layers) respelledRow(row)],
    );
  }
}

/// What the app holds from the last CUT copy — one board for every open
/// project (I-7), the layer board's twin (`LayerBoard`). The next copy the
/// pill takes replaces it, of cuts or of anything else ([onTake]).
class CutBoard {
  _CopiedCuts? _copy;

  /// What this board taking a copy lets go of: the pill's other boards
  /// (`AppClipboard`).
  void Function()? onTake;

  void _take(_CopiedCuts copy) {
    _copy = copy;
    onTake?.call();
  }

  /// Lets go of what it holds: the hand took a copy of another kind.
  void letGo() => _copy = null;

  /// The pictures the copy holds — the memory census's to weigh.
  Iterable<BitmapSurface> get heldPictures => [
    for (final cut in _copy?.cuts ?? const <_CopiedCut>[])
      ...cut.pictures.all,
  ];
}

/// The cuts on the board.
class _CopiedCuts implements BoardCopy {
  const _CopiedCuts({
    required this.from,
    required this.cuts,
    required this.names,
  });

  /// The clipboard that banked them — the PROJECT their ids are. A linked
  /// paste serves only that project ([CutClipboard.canPasteLinked]).
  final CutClipboard from;

  /// In track order, as the hand held them.
  final List<_CopiedCut> cuts;

  /// What their rows name in their project besides their ids — the media
  /// they show, the terms they spell — for a paste elsewhere.
  @override
  final CopiedNames names;
}

/// One cut on the board: as it stood when it was copied, and what it
/// showed then.
class _CopiedCut {
  const _CopiedCut({required this.source, required this.pictures});

  final Cut source;
  final CutPictures pictures;
}
