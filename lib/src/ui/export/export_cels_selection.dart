import '../../models/attached_layer_resolve.dart';
import '../../models/cut.dart';
import '../../models/export_overrides.dart';
import '../../models/export_spec.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';

/// The Cels tab's resolved row set for one cut: the AUTO RULES first, the
/// cut's manual DELTA last (v10 ⑥ "규칙 적용 후 델타만") — so switching
/// presets re-evaluates the rules while the hand exceptions survive, and
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
/// Rule order:
/// 1. Kind gate — camera never; SE never (SE cels are timing data, not
///    pictures); instruction rows iff the preset is 디렉션; paper rows never
///    (they are APPLIED, see [ExportCelsSelection.paperLayers]).
/// 2. The label — a drawing row exports only when its OWN mark wears
///    [CelsExportSpec.label]. Attach rows too: 「LO 작감만」 is a row filter,
///    so a 作監 correction riding a 上がり base is in for 작감 and out for
///    上がり, whatever its base wears. 미술 rows pass instead when
///    [CelsExportSpec.addArt].
/// 3. The take — [CelsExportSpec.take], or 「최신」: the highest take among
///    rows sharing a name and the label.
/// 4. The preset — 기준: every row that passed · 부속: attach rows only ·
///    시트: rows whose base is on the timesheet · 디렉션: no drawing rows.
/// 5. [delta] wins last, per layer id — a forced include overrides even
///    visibility (hidden ≠ empty; the user asked for that cel).
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
          if (isExportPaperRow(layer) && layers.rowVisible(layer)) layer,
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
      return spec.selection == CelsSelectionPreset.direction;
    case LayerKind.animation:
    case LayerKind.storyboard:
    case LayerKind.image:
    case LayerKind.text:
      // The FOLDER's eye counts too. Asking only the row's own eye wrote
      // cel files for rows the user had switched off by hiding the folder
      // they live in — the eye said "not in this render" everywhere else.
      if (!layers.rowVisible(layer) || isExportPaperRow(layer)) {
        return false;
      }
      final wearsLabel =
          markWearsLabel(layer.mark, spec.label) ||
          (spec.addArt && layer.mark.process == LayerProcess.art);
      if (!wearsLabel) {
        return false;
      }
      if (spec.take != null && layer.mark.take != spec.take) {
        return false;
      }
      return _presetAdmits(layer, layers, spec.selection);
  }
}

bool _presetAdmits(Layer layer, List<Layer> layers, CelsSelectionPreset preset) {
  switch (preset) {
    case CelsSelectionPreset.base:
      return true;
    case CelsSelectionPreset.attach:
      return isAttachedLayer(layer);
    case CelsSelectionPreset.sheet:
      // An attach row never takes a sheet column of its own; it is on the
      // sheet when its base is.
      final base = isAttachedLayer(layer)
          ? attachedBaseOf(layer, layers)
          : layer;
      return base != null && base.onTimesheet;
    case CelsSelectionPreset.direction:
      return false;
  }
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
