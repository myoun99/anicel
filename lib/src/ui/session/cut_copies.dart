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
import 'independent_clip_mint.dart' show carryBakedPictures, carrySurfaces;
import 'render_caches.dart';
import 'session_roles.dart';

/// WHAT A CUT'S COPY TAKES ALONG: the pictures its cels show, and the
/// sheets' handwriting. A copy mints every row and cel afresh, and a picture
/// lives under its cel's key, so each one follows its cel over (F-62's law
/// at the cut's scale). ↩️Nothing did until 2026-09-26 — a duplicated cut
/// came out with every drawing blank (measured; card
/// `duplicates-lose-their-pictures`).
///
/// A duplicated cut (`CutVerbs`) and every cut of a copied timeline (I-150,
/// `TimelineVerbs`) take theirs here.
class CutCopies {
  CutCopies({
    required ProjectAccess project,
    required RenderCaches renderCaches,
  }) : _project = project,
       _renderCaches = renderCaches;

  final ProjectAccess _project;
  final RenderCaches _renderCaches;

  /// [source]'s pictures and handwriting, onto its copy [copy] — whose rows
  /// [rows] and whose cels [cels] name, by the ones they copy.
  void carry({
    required Cut source,
    required CutId copy,
    required Map<LayerId, LayerId> rows,
    required Map<FrameId, FrameId> cels,
  }) {
    final into = _project.cutById(copy)!;
    final store = _renderCaches.brushFrameStore;
    for (final row in source.layers) {
      carryBakedPictures(
        project: _project,
        store: store,
        cut: into,
        to: rows[row.id]!,
        minted: {for (final cel in row.frames) cel.id: cels[cel.id]!},
        pictureOf: (cel) => store.bakedSurfaceOrNull(
          _project.brushFrameKeyForCut(source, row.id, cel),
        ),
      );
    }
    _carrySheetInk(from: source.id, to: copy);
  }

  /// The sheets' handwriting of a copied cut, onto its copy: the conte
  /// cells' block by block — each copied block keeps its handwriting id, on
  /// the copy's cut — the envelope's and the timesheet's box by box and band
  /// by band. From there the copy's is its own.
  ///
  /// 🗣️유저 2026-09-26 (cut-duplicate-sheet-ink-Q1): 「따라간다 — 복제는
  /// 전부 복사」. Each sheet's ink is owned the way the load prunes it
  /// (`_InkOwners`): a conte cell by its block, the others by their cut —
  /// the envelope's by the cut that OWNS the envelope, the representative
  /// when [from] shares one ([cutEnvelopeInkOwner]). A duplicated cut is no
  /// sibling, so it owns its own; a copied timeline's 겸용 cuts are each
  /// other's, and read theirs from the representative's copy.
  void _carrySheetInk({required CutId from, required CutId to}) {
    void carry(
      BrushFrameStore store,
      CutId owner,
      BrushFrameKey? Function(BrushFrameKey key) inCopy,
    ) => carrySurfaces(
      sources: store.bakedSurfacesForCut(owner).entries,
      surfaceOf: (written) => written.value,
      keyOfCopy: (written) => inCopy(written.key),
      keep: (key, surface, _) => store.storeBakedSurface(key, surface),
    );

    carry(_renderCaches.conteInkRowStore, from, (key) {
      final block = conteInkRowIdOf(key);
      return block == null ? null : conteInkRowKey(to, block);
    });
    carry(
      _renderCaches.envelopeInkStore,
      cutEnvelopeInkOwner(_project.repository.requireProject(), from),
      (key) => envelopeInkKeyOfCut(key, to),
    );
    carry(
      _renderCaches.timesheetInkStore,
      from,
      (key) => timesheetInkKeyOfCut(key, to),
    );
  }
}
