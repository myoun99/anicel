import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/conte/conte_ink_keys.dart'
    show conteInkRowIdOf, conteInkRowKey;
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart'
    show envelopeInkKeyOfCut;
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/timesheet_ink_keys.dart' show timesheetInkKeyOfCut;
import '../../services/brush_frame_store.dart' show BrushFrameStore;
import '../envelope/cut_envelope_builder.dart' show cutEnvelopeInkOwner;
import 'independent_clip_mint.dart'
    show
        carryBakedPictures,
        carrySurfaces,
        copyBakedPictures,
        picturesShownBy;
import 'render_caches.dart';
import 'session_roles.dart';

/// WHAT A CUT'S COPY TAKES ALONG: the pictures its cels show, and the
/// sheets' handwriting. A copy mints every row and cel afresh, and a picture
/// lives under its cel's key, so each one follows its cel over (F-62's law
/// at the cut's scale). ↩️Nothing did until 2026-09-26 — a duplicated cut
/// came out with every drawing blank (measured; card
/// `duplicates-lose-their-pictures`).
///
/// A duplicated cut (`CutVerbs`), every cut of a copied timeline (I-150,
/// `TimelineVerbs`) and a cut put down from the board (I-150, `CutClipboard`)
/// take theirs here. A duplicate copies at once, its source beside it
/// ([duplicate]); the board holds what the cut showed ([shownBy]) until a
/// paste puts it onto the copy ([carry]).
///
/// 🗣️유저 2026-09-26 (cut-duplicate-sheet-ink-Q1): 「따라간다 — 복제는
/// 전부 복사」 — the sheets' handwriting too: the conte cells' block by
/// block — each copied block keeps its handwriting id, on the copy's cut —
/// the envelope's and the timesheet's box by box and band by band. From
/// there the copy's is its own. A duplicated cut is no sibling, so it owns
/// its envelope; a copied timeline's 겸용 cuts are each other's, and read
/// theirs from the representative's copy.
class CutCopies {
  CutCopies({
    required ProjectAccess project,
    required RenderCaches renderCaches,
  }) : _project = project,
       _renderCaches = renderCaches;

  final ProjectAccess _project;
  final RenderCaches _renderCaches;

  /// What [source] shows NOW — BY VALUE, for [picturesShownBy]'s reason: a
  /// paste may land after the source was drawn over or cut away, or in
  /// another project, whose stores have nothing under its keys.
  CutPictures shownBy(Cut source) {
    final project = _project.repository.requireProject();
    Map<BrushFrameKey, BitmapSurface> written(_Sheet sheet) => sheet
        .storeIn(_renderCaches)
        .bakedSurfacesForCut(sheet.paperOf(project, source.id));
    return CutPictures(
      cels: {
        for (final row in source.layers)
          row.id: picturesShownBy(
            store: _renderCaches.brushFrameStore,
            cels: row.frames,
            keyOf: (cel) => _project.brushFrameKeyForCut(source, row.id, cel),
          ),
      },
      conte: written(_Sheet.conte),
      envelope: written(_Sheet.envelope),
      timesheet: written(_Sheet.timesheet),
    );
  }

  /// [source] onto its copy [copy] at once, its source standing beside it —
  /// whose rows [rows] and whose cels [cels] name, by the ones they copy.
  /// Each picture and each sheet's handwriting goes through its store
  /// ([BrushFrameStore.copyCel], [copyBakedPictures]), so nothing kept
  /// thaws (card `timeline-copy-thaws-every-cel`).
  void duplicate(
    Cut source, {
    required CutId copy,
    required Map<LayerId, LayerId> rows,
    required Map<FrameId, FrameId> cels,
  }) {
    final into = _project.cutById(copy)!;
    for (final row in source.layers) {
      copyBakedPictures(
        project: _project,
        store: _renderCaches.brushFrameStore,
        minted: {for (final cel in row.frames) cel.id: cels[cel.id]!},
        from: (cut: source, row: row.id),
        to: (cut: into, row: rows[row.id]!),
      );
    }
    final project = _project.repository.requireProject();
    for (final sheet in _Sheet.values) {
      final store = sheet.storeIn(_renderCaches);
      for (final key in store.celKeysOfCut(sheet.paperOf(project, source.id))) {
        if (sheet.onCopy(key, copy) case final onCopy?) {
          store.copyCel(key, onCopy);
        }
      }
    }
  }

  /// [shown] onto the copy [copy] — whose rows [rows] and whose cels [cels]
  /// name, by the ones they copy.
  void carry({
    required CutPictures shown,
    required CutId copy,
    required Map<LayerId, LayerId> rows,
    required Map<FrameId, FrameId> cels,
  }) {
    final into = _project.cutById(copy)!;
    final store = _renderCaches.brushFrameStore;
    for (final MapEntry(key: row, value: pictures) in shown.cels.entries) {
      carryBakedPictures(
        project: _project,
        store: store,
        cut: into,
        to: rows[row]!,
        minted: {for (final cel in pictures.keys) cel: cels[cel]!},
        pictureOf: (cel) => pictures[cel],
      );
    }
    for (final sheet in _Sheet.values) {
      final store = sheet.storeIn(_renderCaches);
      carrySurfaces(
        sources: shown._writtenOn(sheet).entries,
        surfaceOf: (written) => written.value,
        keyOfCopy: (written) => sheet.onCopy(written.key, copy),
        keep: (key, surface, _) => store.storeBakedSurface(key, surface),
      );
    }
  }
}

/// The sheets a cut writes on — each read, held and copied by one table.
enum _Sheet {
  conte,
  envelope,
  timesheet;

  BrushFrameStore storeIn(RenderCaches caches) => switch (this) {
    conte => caches.conteInkRowStore,
    envelope => caches.envelopeInkStore,
    timesheet => caches.timesheetInkStore,
  };

  /// The cut [source]'s writing on this sheet is kept under — owned the way
  /// the load prunes it (`_InkOwners`): a conte cell by its block, the
  /// others by their cut — the envelope's by the cut that OWNS the
  /// envelope, the representative when [source] shares one
  /// ([cutEnvelopeInkOwner]) — and a 동기컷's sheets, that owner's envelope
  /// among them, by its sync's canonical, the paper its cuts all write on
  /// (`syncedSheetInkKey`).
  CutId paperOf(Project project, CutId source) =>
      project.linkRegistry.syncCanonicalOf(switch (this) {
        envelope => cutEnvelopeInkOwner(project, source),
        conte || timesheet => source,
      });

  /// Where [key] of this sheet goes on the copy [to]: a conte cell under
  /// its block's handwriting id, a box and a band as they are.
  BrushFrameKey? onCopy(BrushFrameKey key, CutId to) => switch (this) {
    conte => switch (conteInkRowIdOf(key)) {
      final block? => conteInkRowKey(to, block),
      null => null,
    },
    envelope => envelopeInkKeyOfCut(key, to),
    timesheet => timesheetInkKeyOfCut(key, to),
  };
}

/// What a cut showed when [CutCopies.shownBy] read it: its cels' pictures,
/// by row and cel, and its sheets' handwriting, each under the key it was
/// written by.
class CutPictures {
  const CutPictures({
    required this.cels,
    required this.conte,
    required this.envelope,
    required this.timesheet,
  });

  final Map<LayerId, Map<FrameId, BitmapSurface>> cels;
  final Map<BrushFrameKey, BitmapSurface> conte;
  final Map<BrushFrameKey, BitmapSurface> envelope;
  final Map<BrushFrameKey, BitmapSurface> timesheet;

  Map<BrushFrameKey, BitmapSurface> _writtenOn(_Sheet sheet) =>
      switch (sheet) {
        _Sheet.conte => conte,
        _Sheet.envelope => envelope,
        _Sheet.timesheet => timesheet,
      };

  /// These without the pictures of the cels [gone] names — what a copy
  /// takes along that lets those cels go as it lands (a linked paste's,
  /// whose namesakes the source's replace — `createLinkedCutAsItStands`).
  CutPictures withoutCels(Set<FrameId> gone) => CutPictures(
    cels: {
      for (final MapEntry(key: row, value: pictures) in cels.entries)
        row: {
          for (final MapEntry(key: cel, value: picture) in pictures.entries)
            if (!gone.contains(cel)) cel: picture,
        },
    },
    conte: conte,
    envelope: envelope,
    timesheet: timesheet,
  );

  /// Every one of them — the memory census's to weigh, while a board holds
  /// them.
  Iterable<BitmapSurface> get all => [
    for (final pictures in cels.values) ...pictures.values,
    ...conte.values,
    ...envelope.values,
    ...timesheet.values,
  ];
}
