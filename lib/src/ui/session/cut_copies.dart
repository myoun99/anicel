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
import '../../models/timesheet_ink_keys.dart' show timesheetInkKeyOfCut;
import '../../services/brush_frame_store.dart' show BrushFrameStore;
import '../envelope/cut_envelope_builder.dart' show cutEnvelopeInkOwner;
import 'independent_clip_mint.dart'
    show carryBakedPictures, carrySurfaces, picturesShownBy;
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
/// take theirs here — what the cut showed ([shownBy]), then onto its copy
/// ([carry]). A duplicate does both at once; the board holds the first
/// until a paste.
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
  ///
  /// The sheets' ink is owned the way the load prunes it (`_InkOwners`): a
  /// conte cell by its block, the others by their cut — the envelope's by
  /// the cut that OWNS the envelope, the representative when [source]
  /// shares one ([cutEnvelopeInkOwner]) — and a 동기컷's conte and timesheet
  /// by its sync's canonical, the paper its cuts all write on
  /// (`syncedSheetInkKey`).
  CutPictures shownBy(Cut source) {
    final store = _renderCaches.brushFrameStore;
    final project = _project.repository.requireProject();
    final paper = project.linkRegistry.syncCanonicalOf(source.id);
    return CutPictures(
      cels: {
        for (final row in source.layers)
          row.id: picturesShownBy(
            store: store,
            cels: row.frames,
            keyOf: (cel) => _project.brushFrameKeyForCut(source, row.id, cel),
          ),
      },
      conte: _renderCaches.conteInkRowStore.bakedSurfacesForCut(paper),
      envelope: _renderCaches.envelopeInkStore.bakedSurfacesForCut(
        cutEnvelopeInkOwner(project, source.id),
      ),
      timesheet: _renderCaches.timesheetInkStore.bakedSurfacesForCut(paper),
    );
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
    _carrySheetInk(shown, to: copy);
  }

  /// The sheets' handwriting of a copied cut, onto its copy: the conte
  /// cells' block by block — each copied block keeps its handwriting id, on
  /// the copy's cut — the envelope's and the timesheet's box by box and band
  /// by band. From there the copy's is its own.
  ///
  /// 🗣️유저 2026-09-26 (cut-duplicate-sheet-ink-Q1): 「따라간다 — 복제는
  /// 전부 복사」. A duplicated cut is no sibling, so it owns its envelope; a
  /// copied timeline's 겸용 cuts are each other's, and read theirs from the
  /// representative's copy.
  void _carrySheetInk(CutPictures shown, {required CutId to}) {
    void carry(
      BrushFrameStore store,
      Map<BrushFrameKey, BitmapSurface> written,
      BrushFrameKey? Function(BrushFrameKey key) inCopy,
    ) => carrySurfaces(
      sources: written.entries,
      surfaceOf: (written) => written.value,
      keyOfCopy: (written) => inCopy(written.key),
      keep: (key, surface, _) => store.storeBakedSurface(key, surface),
    );

    carry(_renderCaches.conteInkRowStore, shown.conte, (key) {
      final block = conteInkRowIdOf(key);
      return block == null ? null : conteInkRowKey(to, block);
    });
    carry(
      _renderCaches.envelopeInkStore,
      shown.envelope,
      (key) => envelopeInkKeyOfCut(key, to),
    );
    carry(
      _renderCaches.timesheetInkStore,
      shown.timesheet,
      (key) => timesheetInkKeyOfCut(key, to),
    );
  }
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

  /// Every one of them — the memory census's to weigh, while a board holds
  /// them.
  Iterable<BitmapSurface> get all => [
    for (final pictures in cels.values) ...pictures.values,
    ...conte.values,
    ...envelope.values,
    ...timesheet.values,
  ];
}
