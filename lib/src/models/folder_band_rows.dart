import '../core/frozen_collections.dart';
import 'layer.dart';

/// The rows [band] is made of — what a drag in flight re-reads it from
/// (`rowShownWhileMoved`), and what its cells are as much as its own
/// timeline ([firstCellThatMayDiffer]); null for every layer that is no
/// band.
///
/// 🐛folder-band-lags-a-comma-drag (10-27): a folder's row is what its rows
/// hold (F-311), so it follows the hand as they do — and it did for a block
/// MOVE alone, whose drag laid the bands in its own preview. A comma drag
/// and a file held over a row put their one row there, and the folder stood
/// where it was until the release. So the band says what it stands for,
/// as a mirror says its base (`attachedDisplayBaseOf`), and whatever reads
/// a row as a drag shows it reads a folder's from its rows.
List<Layer>? folderBandRowsOf(Layer band) => _bandRows[band];

/// Notes that [band] stands for [rows] — as it is made, and again whenever
/// it is kept for rows that hold as its did (`FolderBands`).
void folderBandStandsFor(Layer band, Iterable<Layer> rows) =>
    _bandRows[band] = frozenList(rows);

/// The rows each band stands for, held weakly like the bands themselves.
final Expando<List<Layer>> _bandRows = Expando('folder band rows');
