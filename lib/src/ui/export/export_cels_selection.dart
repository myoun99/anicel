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
/// cut's manual DELTA last (v10 ⑥ "규칙 적용 후 델타만") — so changing a
/// filter re-evaluates the rules while the hand exceptions survive, and
/// Reset just drops the delta.
class ExportCelsSelection {
  const ExportCelsSelection({
    required this.celLayers,
    required this.paperLayers,
  });

  /// The rows whose pictures export — bases, attach rows and direction rows
  /// alike, in cut stack order. Which of them become a FILE (the bundle) is
  /// the planner's question, not this one's.
  ///
  /// ↩️The direction rows stood in a list of their own, exported by a
  /// second path that drew their WRITING (F-289).
  final List<Layer> celLayers;

  /// 용지: the paper-labelled rows whose drawing is composited into EVERY
  /// output cel. Never cels of their own, never in [celLayers].
  final List<Layer> paperLayers;

  bool includes(Layer layer) =>
      celLayers.any((candidate) => candidate.id == layer.id);
}

/// Whether [mark] wears [label] — process and revise as ONE item (유저
/// 2026-09-09: 「색라벨은 하나야. 공정이랑 수정 나누지않고」). The take is a
/// separate question ([CelsExportSpec.take]), so it is not compared here.
bool markWearsLabel(LayerMark mark, LayerMark label) =>
    mark.process == label.process && mark.revise == label.revise;

/// The kind [layer] exports as ([ExportCelKind]), or null for a row that
/// exports nothing of its own: the camera, an SE row, a folder — and a
/// paper row, which is APPLIED ([isExportPaperRow]).
///
/// An attach row is of its BASE's kind: it goes out in its base's cels, and
/// the window lists it under its base — so a kind that is off takes a base
/// and what rides it out of the list together.
ExportCelKind? exportCelKindOf(Layer layer, List<Layer> layers) {
  if (!layer.kind.exportsCels || isExportPaperRow(layer)) {
    return null;
  }
  final owner = isAttachedLayer(layer) ? attachedBaseOf(layer, layers) : layer;
  return switch (owner?.kind) {
    LayerKind.instruction => ExportCelKind.direction,
    LayerKind.storyboard => ExportCelKind.conte,
    LayerKind.animation || LayerKind.image =>
      owner!.mark.process == LayerProcess.art
          ? ExportCelKind.art
          : ExportCelKind.cel,
    _ => null,
  };
}

/// Whether the export window LISTS [layer] under [spec]: a row of a kind
/// the export writes, and a folder holding one. A row of a kind that is off
/// is not in the list at all — 유저 2026-10-06: 「여기서 사라진것들은 오른쪽
/// 행 리스트에서 안보이도록」 — and neither is a row that exports nothing of
/// its own (the camera, an SE row, the paper).
bool exportCelsListsRow(Layer layer, List<Layer> layers, CelsExportSpec spec) {
  if (layer.kind.groupsLayers) {
    return layers
        .subtreeMembersOf(layer.id)
        .any(
          (member) =>
              !member.kind.groupsLayers &&
              exportCelsListsRow(member, layers, spec),
        );
  }
  final kind = exportCelKindOf(layer, layers);
  return kind != null && spec.kinds.contains(kind);
}

/// Resolves which of [cut]'s layers the Cels export covers under [spec]'s
/// rules and the cut's manual [delta].
///
/// The KIND comes first ([ExportCelKind], F-289): camera never; SE never (SE
/// cels are timing data, not pictures); paper rows never (they are APPLIED,
/// see [ExportCelsSelection.paperLayers]); and every other row only while
/// its kind is one the export writes ([exportCelKindOf]).
///
/// Then the rules are FILTERS that stack (유저 2026-09-09: 「단일선택이 아니라
/// 중첩가능이야 … 진짜 여러 항목이 필터로 작동하는거지」), in this order:
/// 1. 시트 — with [CelsExportSpec.sheetOnly], only the rows on the timesheet
///    stay; an attach row never takes a sheet column of its own, so it is
///    on the sheet when its base is.
/// 2. 기준 / 어태치 — a base row stays while [CelsExportSpec.base], an attach
///    row while [CelsExportSpec.attach]. Attach alone is the parts without
///    their base (the base still numbers the cels — the planner's axis). A
///    direction row is neither, and passes.
/// 3. The label — a CEL row stays only when its OWN mark wears
///    [CelsExportSpec.label]. Attach rows too: 「LO 작감만」 is a row filter,
///    so a 作監 correction riding a 上がり base is in for 작감 and out for
///    上がり, whatever its base wears. The other kinds do not answer to the
///    label — an art row is art whatever it wears (drawn so in the F-289
///    mock and confirmed, 유저 2026-10-06: 「확인 넷 다 그대로 ok」; the
///    other kinds' rows are on while their kind is).
/// 4. The take — [CelsExportSpec.take], or 「최신」: the highest take among
///    rows sharing a name that passed the label.
/// 5. [delta] wins last, per layer id — the user asked for that row.
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
  _applyLayerOverrides(included, layers, spec, delta?.layerOverrides ?? const {});

  return ExportCelsSelection(
    celLayers: [
      for (var i = 0; i < layers.length; i += 1)
        if (included[i]) layers[i],
    ],
    paperLayers: exportPaperRowsOf(cut, spec),
  );
}

/// The 용지 rows [spec] applies to [cut]'s cels: every paper row of the cut
/// while 용지 적용 is on, none while it is off. Asked of the cut a cel is
/// COMPOSITED in — the one that shows it, which in a 겸용 group is not
/// always the cut the selection was resolved for (F-300).
List<Layer> exportPaperRowsOf(Cut cut, CelsExportSpec spec) => [
  if (spec.applyPaper)
    for (final layer in cut.layers)
      if (isExportPaperRow(layer)) layer,
];

/// A 용지 row: applied to every cel, never a cel and never the user's to
/// tick in the list — the dialog and the resolver ask this one predicate.
bool isExportPaperRow(Layer layer) =>
    layer.kind.isDrawingCel && layer.mark.process == LayerProcess.paper;

/// Whether [layer] exports before any override: its KIND first, then the
/// filter stack — 시트 · 기준/어태치 ·
/// 색라벨 · 테이크. Every filter only takes rows away — 유저 2026-09-09:
/// 「진짜 여러 항목이 필터로 작동하는거지」.
///
/// WHICH ROWS can export a cel at all is one fact, and it lives with the
/// kind (LayerKind.exportsCels, through [exportCelKindOf]): the camera has
/// no artwork, SE cels are timing data, a folder holds its members' cels
/// rather than one of its own, and a paper row is the sheet the others are
/// composited onto ([isExportPaperRow], 적용 항목).
bool _exportsByRule(Layer layer, List<Layer> layers, CelsExportSpec spec) {
  final kind = exportCelKindOf(layer, layers);
  if (kind == null || !spec.kinds.contains(kind)) {
    return false;
  }
  if (!_sheetAdmits(layer, layers, spec)) {
    return false;
  }
  if (kind == ExportCelKind.direction) {
    return true;
  }
  if (!(isAttachedLayer(layer) ? spec.attach : spec.base)) {
    return false;
  }
  if (kind == ExportCelKind.cel && !markWearsLabel(layer.mark, spec.label)) {
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

/// The user's per-row answers, which win last — over the FILTERS.
///
/// ⛔The KIND stays hard: a row that holds no cel never exports one, however
/// the checkbox was left; a paper row stays applied, never a cel, because
/// that is a different question than "is this row in"; and a row of a kind
/// the export does not write stays out — it is not in the list to be
/// answered for ([exportCelsListsRow]). The answer is kept all the same, for
/// when the kind is written again.
void _applyLayerOverrides(
  List<bool> included,
  List<Layer> layers,
  CelsExportSpec spec,
  Map<LayerId, bool> overrides,
) {
  for (var i = 0; i < layers.length; i += 1) {
    final forced = overrides[layers[i].id];
    if (forced != null && exportCelsListsRow(layers[i], layers, spec)) {
      included[i] = forced;
    }
  }
}
