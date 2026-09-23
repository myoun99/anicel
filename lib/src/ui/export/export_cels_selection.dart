import '../../models/attached_layer_resolve.dart';
import '../../models/cut.dart';
import '../../models/export_overrides.dart';
import '../../models/export_spec.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';

/// The Cels tab's resolved row set for one cut: the AUTO RULES first, the
/// cut's manual DELTA last (v10 ⑥ "규칙 적용 후 델타만") — so changing a
/// filter re-evaluates the rules while the hand exceptions survive, and
/// Reset just drops the delta.
class ExportCelsSelection {
  const ExportCelsSelection({
    required this.celLayers,
    required this.instructionLayers,
    required this.paperLayers,
  });

  /// Drawing rows whose pictures export — bases and attach rows alike, in
  /// cut stack order. Which of them become a FILE (the bundle) is the
  /// planner's question, not this one's.
  final List<Layer> celLayers;

  /// Instruction layers (지시 레이어 — PAN etc.) exporting as image cels,
  /// in cut stack order.
  final List<Layer> instructionLayers;

  /// 용지: the paper-labelled rows whose drawing is composited into EVERY
  /// output cel. Never cels of their own, never in [celLayers].
  final List<Layer> paperLayers;

  bool includes(Layer layer) =>
      celLayers.any((candidate) => candidate.id == layer.id) ||
      instructionLayers.any((candidate) => candidate.id == layer.id);
}

/// Whether [mark] wears [label] — process and revise as ONE item (유저
/// 2026-09-09: 「색라벨은 하나야. 공정이랑 수정 나누지않고」). The take is a
/// separate question ([CelsExportSpec.take]), so it is not compared here.
bool markWearsLabel(LayerMark mark, LayerMark label) =>
    mark.process == label.process && mark.revise == label.revise;

/// Resolves which of [cut]'s layers the Cels export covers under [spec]'s
/// rules and the cut's manual [delta].
///
/// The rules are FILTERS that stack (유저 2026-09-09: 「단일선택이 아니라
/// 중첩가능이야 … 진짜 여러 항목이 필터로 작동하는거지」), in this order:
/// 1. Kind gate — camera never; SE never (SE cels are timing data, not
///    pictures); paper rows never (they are APPLIED, see
///    [ExportCelsSelection.paperLayers]); instruction rows iff 디렉션 is
///    ADDED ([CelsExportSpec.addDirection]).
/// 2. 기준 / 부속 — a base row stays while [CelsExportSpec.base], an attach
///    row while [CelsExportSpec.attach]. Attach alone is the parts without
///    their base (the base still numbers the cels — the planner's axis).
/// 3. 시트 — with [CelsExportSpec.sheetOnly], only the rows on the timesheet
///    stay; an attach row never takes a sheet column of its own, so it is
///    on the sheet when its base is.
/// 4. The label — a drawing row stays only when its OWN mark wears
///    [CelsExportSpec.label]. Attach rows too: 「LO 작감만」 is a row filter,
///    so a 作監 correction riding a 上がり base is in for 작감 and out for
///    上がり, whatever its base wears. 미술 rows pass instead when
///    [CelsExportSpec.addArt].
/// 5. The take — [CelsExportSpec.take], or 「최신」: the highest take among
///    rows sharing a name that passed the label.
/// 6. [delta] wins last, per layer id — the user asked for that row.
///
/// ⛔THE TIMELINE'S EYE IS NOT CONSULTED. Until 2026-09-09 a hidden row (or
/// a row in a hidden folder) exported nothing; 유저: 「타임라인에서 비지블
/// off면 출력에 off인채로 있는데, 그게아니라 상태에 따라 안바뀌도록」. The
/// eye is view state; what exports is what the filters say.
ExportCelsSelection resolveExportCelsSelection({
  required Cut cut,
  required CelsExportSpec spec,
  ExportCelsCutDelta? delta,
}) {
  final layers = cut.layers;
  final included = [
    for (final layer in layers) _exportsByRule(layer, layers, spec),
  ];
  if (spec.take == null) {
    _keepLatestTakes(included, layers);
  }
  _applyLayerOverrides(included, layers, delta?.layerOverrides ?? const {});

  final celLayers = <Layer>[];
  final instructionLayers = <Layer>[];
  for (var i = 0; i < layers.length; i += 1) {
    if (!included[i]) {
      continue;
    }
    (layers[i].kind == LayerKind.instruction ? instructionLayers : celLayers)
        .add(layers[i]);
  }
  return ExportCelsSelection(
    celLayers: celLayers,
    instructionLayers: instructionLayers,
    paperLayers: [
      if (spec.applyPaper)
        for (final layer in layers)
          if (isExportPaperRow(layer)) layer,
    ],
  );
}

/// A 용지 row: applied to every cel, never a cel and never the user's to
/// tick in the list — the dialog and the resolver ask this one predicate.
bool isExportPaperRow(Layer layer) =>
    layer.kind.isDrawingCel && layer.mark.process == LayerProcess.paper;

/// Whether [layer] exports before any override.
///
/// WHICH KINDS can export a cel is one fact, and it lives with the kind
/// (LayerKind.exportsCels): the camera has no artwork, SE cels are timing
/// data, and a folder holds its members' cels rather than one of its own.
/// What stays here is this EXPORT's policy on top of that gate.
bool _exportsByRule(Layer layer, List<Layer> layers, CelsExportSpec spec) {
  if (!layer.kind.exportsCels) {
    return false;
  }
  switch (layer.kind) {
    case LayerKind.camera:
    case LayerKind.se:
    case LayerKind.transition:
    case LayerKind.folder:
    case LayerKind.adjustment:
      return false; // Gated above; the switch stays exhaustive on purpose.
    case LayerKind.instruction:
      return spec.addDirection && _sheetAdmits(layer, layers, spec);
    case LayerKind.animation:
    case LayerKind.storyboard:
    case LayerKind.image:
      return _drawingCelExports(layer, layers, spec);
  }
}

/// The FILTER STACK on a drawing row, in the order the window shows it:
/// 기준/부속 · 시트 · 색라벨(+미술) · 테이크. Every one of them only takes
/// rows away — 유저 2026-09-09: 「진짜 여러 항목이 필터로 작동하는거지」.
///
/// A paper row is not one of the exported cels at all: it is the sheet the
/// others are composited onto ([isExportPaperRow], 적용 항목).
bool _drawingCelExports(Layer layer, List<Layer> layers, CelsExportSpec spec) {
  if (isExportPaperRow(layer)) {
    return false;
  }
  if (!(isAttachedLayer(layer) ? spec.attach : spec.base)) {
    return false;
  }
  if (!_sheetAdmits(layer, layers, spec)) {
    return false;
  }
  final wearsLabel =
      markWearsLabel(layer.mark, spec.label) ||
      (spec.addArt && layer.mark.process == LayerProcess.art);
  if (!wearsLabel) {
    return false;
  }
  return spec.take == null || layer.mark.take == spec.take;
}

/// The 시트 filter: off, everything passes; on, a row passes when it — or,
/// for an attach row, its base — is on the timesheet.
bool _sheetAdmits(Layer layer, List<Layer> layers, CelsExportSpec spec) {
  if (!spec.sheetOnly) {
    return true;
  }
  final base = isAttachedLayer(layer) ? attachedBaseOf(layer, layers) : layer;
  return base != null && base.onTimesheet;
}

/// 「최신」: among rows that share a NAME and passed the label, only the
/// highest take stays (A T1 + A T2 → T2; A T1 + B T2 → both).
///
/// Grouped by name rather than by label alone because a retake is drawn
/// as a new row under the same name — grouping by label would let one
/// character's T2 silence every other character's T1.
void _keepLatestTakes(List<bool> included, List<Layer> layers) {
  final latestByName = <String, int>{};
  for (var i = 0; i < layers.length; i += 1) {
    if (!included[i] || layers[i].kind == LayerKind.instruction) {
      continue;
    }
    final take = layers[i].mark.take;
    final seen = latestByName[layers[i].name];
    if (seen == null || take > seen) {
      latestByName[layers[i].name] = take;
    }
  }
  for (var i = 0; i < layers.length; i += 1) {
    if (included[i] &&
        layers[i].kind != LayerKind.instruction &&
        layers[i].mark.take != latestByName[layers[i].name]) {
      included[i] = false;
    }
  }
}

/// The user's per-row answers, which win last.
///
/// ⛔The KIND gates stay hard: rows that hold no cel never export one,
/// however the checkbox was left — and a paper row stays applied, never a
/// cel, because that is a different question than "is this row in".
void _applyLayerOverrides(
  List<bool> included,
  List<Layer> layers,
  Map<LayerId, bool> overrides,
) {
  for (var i = 0; i < layers.length; i += 1) {
    final forced = overrides[layers[i].id];
    if (forced != null &&
        layers[i].kind.exportsCels &&
        !isExportPaperRow(layers[i])) {
      included[i] = forced;
    }
  }
}
