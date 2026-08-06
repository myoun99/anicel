import '../cut.dart';
import '../layer.dart';
import '../layer_kind.dart';

/// One 担当 row of a cut envelope: a cel's name and how many drawings it
/// holds.
class CutEnvelopeCelCount {
  const CutEnvelopeCelCount({
    required this.name,
    required this.genga,
    required this.dougaEstimate,
  });

  /// The cel's letter — the LAYER's name (A, B, ABH…), which is exactly
  /// what the envelope's left column prints.
  final String name;

  /// 原画: drawings that actually exist. In-between dots are not drawings
  /// and repeat ghosts are not new ones, so neither is counted.
  final int genga;

  /// 動画 (予想): the same drawings plus one per in-between dot — what the
  /// cel WILL be once the inbetweens are drawn. An estimate on purpose:
  /// the CELL column that would carry the real number is not authored yet.
  final int dougaEstimate;
}

/// The envelope's 担当 rows for [cut], top to bottom.
///
/// The row set is the timesheet's ACTION block: animation rows that are on
/// the sheet. That gate is the one place this question is answered, so
/// attach rows, hidden rows and BG/BOOK picture rows follow the sheet
/// rather than a second rule — a BG is not a cel and never appears.
///
/// The timesheet lays the same rows left to right; an envelope runs them
/// down its left column. Same list, turned.
List<CutEnvelopeCelCount> cutEnvelopeCelCounts(Cut cut) {
  return [
    for (final layer in cut.layers)
      if (layer.kind == LayerKind.animation && layer.onTimesheet)
        CutEnvelopeCelCount(
          name: layer.name,
          genga: layer.frames.length,
          dougaEstimate: layer.frames.length + _breakdownCount(layer),
        ),
  ];
}

/// The envelope's 計 row: every cel's drawings added up.
CutEnvelopeCelCount cutEnvelopeCelTotal(
  List<CutEnvelopeCelCount> rows, {
  String name = '計',
}) {
  var genga = 0;
  var douga = 0;
  for (final row in rows) {
    genga += row.genga;
    douga += row.dougaEstimate;
  }
  return CutEnvelopeCelCount(
    name: name,
    genga: genga,
    dougaEstimate: douga,
  );
}

/// In-between dots the row's AUTHORED blocks own.
///
/// Ghost exposures are skipped: a repeat chain re-exposes drawings that
/// already exist, and counting the dots it carries would bill the same
/// inbetweens twice.
int _breakdownCount(Layer layer) {
  var total = 0;
  for (final exposure in layer.timeline.values) {
    if (exposure.ghost) {
      continue;
    }
    total += exposure.breakdownOffsets.length;
  }
  return total;
}
