import '../core/collection_equality.dart';
import 'cut_id.dart';
import 'layer_id.dart';

/// The Cels tab's per-cut MANUAL EXCEPTIONS (v10 ⑥ "규칙 적용 후 델타"):
/// what the user hand-flipped away from the preset rules' outcome for one
/// cut. Reset = clearing the delta.
class ExportCelsCutDelta {
  ExportCelsCutDelta({
    Map<LayerId, bool> layerOverrides = const {},
    Set<LayerId> skippedBases = const {},
  }) : layerOverrides = Map.unmodifiable(layerOverrides),
       skippedBases = Set.unmodifiable(skippedBases);

  /// Per-layer forced include(true)/exclude(false), keyed by id — layer
  /// NAMES are not unique, ids are. A non-empty map is what makes the
  /// 선택 pills read 「커스텀」.
  final Map<LayerId, bool> layerOverrides;

  /// Output cels the user unticked in the cel list (v3.2, 유저 2026-09-09:
  /// 「출력 셀쪽에 최종적으로 출력할 셀 고를수있게 … 기본값은 on」), keyed
  /// by the bundle's axis layer. Separate from [layerOverrides] on
  /// purpose: unticking a CEL says "do not write this file" and leaves the
  /// row selection alone, so the two questions never share a flag.
  final Set<LayerId> skippedBases;

  bool get isEmpty => layerOverrides.isEmpty && skippedBases.isEmpty;

  ExportCelsCutDelta withLayerOverride(LayerId id, bool? include) {
    final next = Map<LayerId, bool>.from(layerOverrides);
    if (include == null) {
      next.remove(id);
    } else {
      next[id] = include;
    }
    return ExportCelsCutDelta(layerOverrides: next, skippedBases: skippedBases);
  }

  ExportCelsCutDelta withBaseSkipped(LayerId id, bool skipped) {
    final next = Set<LayerId>.from(skippedBases);
    if (skipped) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return ExportCelsCutDelta(layerOverrides: layerOverrides, skippedBases: next);
  }

  /// The row exceptions dropped, the cel ticks kept — pressing a 선택
  /// preset re-applies the rule without touching which files are written.
  ExportCelsCutDelta withoutLayerOverrides() =>
      ExportCelsCutDelta(skippedBases: skippedBases);

  Map<String, dynamic> toJson() => {
    'layerOverrides': {
      for (final entry in layerOverrides.entries)
        entry.key.value: entry.value,
    },
    if (skippedBases.isNotEmpty)
      'skippedBases': [for (final id in skippedBases) id.value]..sort(),
  };

  static ExportCelsCutDelta fromJson(Map<String, dynamic> json) {
    final raw = json['layerOverrides'] as Map<String, dynamic>? ?? const {};
    final skipped = json['skippedBases'] as List<dynamic>? ?? const [];
    return ExportCelsCutDelta(
      layerOverrides: {
        for (final entry in raw.entries)
          LayerId(entry.key): entry.value as bool,
      },
      skippedBases: {for (final id in skipped) LayerId(id as String)},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportCelsCutDelta &&
          mapEquals(other.layerOverrides, layerOverrides) &&
          setEquals(other.skippedBases, skippedBases);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered([
      for (final entry in layerOverrides.entries)
        Object.hash(entry.key, entry.value),
    ]),
    Object.hashAllUnordered(skippedBases),
  );
}

/// PROJECT-side export state (v10: 컷 체크=프로젝트 저장): which cuts the
/// Cels/Timesheet project scope excludes, and each cut's Cels delta.
/// Project data — it travels with the film — but not a document edit:
/// writes go through the repository directly with no history entry
/// (the visibility-toggle precedent).
class ExportProjectOverrides {
  ExportProjectOverrides({
    Set<CutId> excludedCutIds = const {},
    Map<CutId, ExportCelsCutDelta> celsCutDeltas = const {},
  }) : excludedCutIds = Set.unmodifiable(excludedCutIds),
       celsCutDeltas = Map.unmodifiable({
         for (final entry in celsCutDeltas.entries)
           if (!entry.value.isEmpty) entry.key: entry.value,
       });

  static final ExportProjectOverrides empty = ExportProjectOverrides();

  final Set<CutId> excludedCutIds;
  final Map<CutId, ExportCelsCutDelta> celsCutDeltas;

  bool get isEmpty => excludedCutIds.isEmpty && celsCutDeltas.isEmpty;
  bool get isNotEmpty => !isEmpty;

  bool cutIncluded(CutId id) => !excludedCutIds.contains(id);

  ExportCelsCutDelta? deltaFor(CutId id) => celsCutDeltas[id];

  ExportProjectOverrides withCutIncluded(CutId id, bool included) {
    final next = Set<CutId>.from(excludedCutIds);
    if (included) {
      next.remove(id);
    } else {
      next.add(id);
    }
    return ExportProjectOverrides(
      excludedCutIds: next,
      celsCutDeltas: celsCutDeltas,
    );
  }

  /// All cuts back in scope (the All button's reset semantics).
  ExportProjectOverrides withAllCutsIncluded() =>
      ExportProjectOverrides(celsCutDeltas: celsCutDeltas);

  ExportProjectOverrides withCelsDelta(CutId id, ExportCelsCutDelta? delta) {
    final next = Map<CutId, ExportCelsCutDelta>.from(celsCutDeltas);
    if (delta == null || delta.isEmpty) {
      next.remove(id);
    } else {
      next[id] = delta;
    }
    return ExportProjectOverrides(
      excludedCutIds: excludedCutIds,
      celsCutDeltas: next,
    );
  }

  Map<String, dynamic> toJson() => {
    if (excludedCutIds.isNotEmpty)
      'excludedCuts': [for (final id in excludedCutIds) id.value]..sort(),
    if (celsCutDeltas.isNotEmpty)
      'celsCutDeltas': {
        for (final entry in celsCutDeltas.entries)
          entry.key.value: entry.value.toJson(),
      },
  };

  static ExportProjectOverrides fromJson(Map<String, dynamic> json) {
    final excluded = json['excludedCuts'] as List<dynamic>? ?? const [];
    final deltas = json['celsCutDeltas'] as Map<String, dynamic>? ?? const {};
    return ExportProjectOverrides(
      excludedCutIds: {for (final id in excluded) CutId(id as String)},
      celsCutDeltas: {
        for (final entry in deltas.entries)
          CutId(entry.key): ExportCelsCutDelta.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportProjectOverrides &&
          setEquals(other.excludedCutIds, excludedCutIds) &&
          mapEquals(other.celsCutDeltas, celsCutDeltas);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(excludedCutIds),
    Object.hashAllUnordered([
      for (final entry in celsCutDeltas.entries)
        Object.hash(entry.key, entry.value),
    ]),
  );
}
