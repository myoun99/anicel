import '../cut.dart';
import '../layer.dart';
import '../layer_process.dart';

/// One 担当 row of a cut envelope: a cel's name and how many drawings each
/// stage holds of it.
class CutEnvelopeCelCount {
  const CutEnvelopeCelCount({
    required this.name,
    required this.genga,
    required this.douga,
    required this.shiage,
  });

  /// The cel's letter — the LAYER's name (A, B, ABH…), which is exactly
  /// what the envelope's left column prints.
  final String name;

  /// 原画: the drawings of the cel's ACTION-block rows. Repeat ghosts
  /// re-expose drawings that exist, so they are not counted.
  final int genga;

  /// 動画: the drawings of the cel's 動画-labelled rows.
  final int douga;

  /// 仕上げ: the drawings of the cel's 仕上げ-labelled rows — トレス・
  /// ペイント on the paper form.
  final int shiage;
}

/// The envelope's 担当 rows for [cut], top to bottom: one per cel name, in
/// the order the timesheet's cel rows first name it.
///
/// The rows counted are the timesheet's cel rows ([layerTakesSheetCelColumn]
/// — ONE gate with the sheet and the XDTS export, D24), so attach rows,
/// hidden rows and BG/BOOK picture rows follow the sheet rather than a
/// second rule — a BG is not a cel and never appears. Each row's drawings
/// count under its stage ([celStageOf]) — the sheet's ACTION block is
/// 原画, its CELL block 動画 and 仕上げ — so a cel whose 原画 and 動画 are
/// two rows of one name is one envelope row (F-498).
///
/// ↩️Every cel row counted as 原画, and 動画 was an estimate of the same
/// drawings plus one per in-between dot.
List<CutEnvelopeCelCount> cutEnvelopeCelCounts(Cut cut) {
  final byName = <String, Map<LayerProcess, int>>{};
  for (final layer in cut.layers) {
    if (layerTakesSheetCelColumn(layer)) {
      final stages = byName.putIfAbsent(layer.name, () => {});
      final stage = celStageOf(layer);
      stages[stage] = (stages[stage] ?? 0) + layer.frames.length;
    }
  }
  return [
    for (final MapEntry(key: name, value: stages) in byName.entries)
      CutEnvelopeCelCount(
        name: name,
        genga: stages[LayerProcess.key] ?? 0,
        douga: stages[LayerProcess.inbetween] ?? 0,
        shiage: stages[LayerProcess.finish] ?? 0,
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
  var shiage = 0;
  for (final row in rows) {
    genga += row.genga;
    douga += row.douga;
    shiage += row.shiage;
  }
  return CutEnvelopeCelCount(
    name: name,
    genga: genga,
    douga: douga,
    shiage: shiage,
  );
}
