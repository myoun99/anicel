import '../core/collection_equality.dart';
import 'cut_id.dart';
import 'frame_id.dart';
import 'layer_id.dart';

/// One drawing of a cut, named by the row it stands on and the cel it is —
/// what the Cels tab's list switches, and what a direction is laid over.
typedef ExportCelRef = ({LayerId row, FrameId cel});

/// One direction drawing laid over one drawing ([ExportCelRef] each).
typedef ExportDirectionOver = ({ExportCelRef cel, ExportCelRef direction});

/// The Cels tab's per-cut MANUAL EXCEPTIONS (v10 ⑥ "규칙 적용 후 델타"):
/// what the user hand-flipped away from the preset rules' outcome for one
/// cut. Reset = back on the rules ([backOnTheRules]).
class ExportCelsCutDelta {
  ExportCelsCutDelta({
    Map<LayerId, bool> layerOverrides = const {},
    Set<ExportCelRef> skippedCels = const {},
    Set<ExportDirectionOver> directionOver = const {},
  }) : layerOverrides = Map.unmodifiable(layerOverrides),
       skippedCels = Set.unmodifiable(skippedCels),
       directionOver = Set.unmodifiable(directionOver);

  /// Per-layer forced include(true)/exclude(false), keyed by id — layer
  /// NAMES are not unique, ids are. A non-empty map is what makes the
  /// label button read 「커스텀」.
  final Map<LayerId, bool> layerOverrides;

  /// The drawings the user turned off in the list, each by the row its
  /// block stands on (F-289, 유저 2026-10-06: 「셀의 프레임버튼 누르면
  /// 내보내기 적용/미적용」). Separate from [layerOverrides] on purpose: a
  /// drawing turned off says "do not write this file" and leaves the row
  /// selection alone, so the two questions never share a flag.
  ///
  /// ↩️It was a set of BUNDLES (`skippedBases`, one tick for every cel of a
  /// row) while the window listed bundles; the list shows drawings now.
  final Set<ExportCelRef> skippedCels;

  /// The direction drawings laid over a drawing when it is written — 유저
  /// 2026-10-06: 「디렉션 레이어는 해당 셀에(레이어의 해당 프레임 그림)
  /// 넣고싶은거라, 예를들어 BG의 1번 그림에 디렉션레이어의 1번을
  /// 얹고싶다거나」. Each direction is the direction row and its drawing in
  /// this cut.
  final Set<ExportDirectionOver> directionOver;

  bool get isEmpty =>
      layerOverrides.isEmpty && skippedCels.isEmpty && directionOver.isEmpty;

  /// Whether this cut has left its rules: a row answered by hand, or a
  /// drawing turned off — what [backOnTheRules] undoes.
  bool get leavesTheRules =>
      layerOverrides.isNotEmpty || skippedCels.isNotEmpty;

  ExportCelsCutDelta _with({
    Map<LayerId, bool>? layerOverrides,
    Set<ExportCelRef>? skippedCels,
    Set<ExportDirectionOver>? directionOver,
  }) => ExportCelsCutDelta(
    layerOverrides: layerOverrides ?? this.layerOverrides,
    skippedCels: skippedCels ?? this.skippedCels,
    directionOver: directionOver ?? this.directionOver,
  );

  ExportCelsCutDelta withLayerOverride(LayerId id, bool? include) {
    final next = Map<LayerId, bool>.from(layerOverrides);
    if (include == null) {
      next.remove(id);
    } else {
      next[id] = include;
    }
    return _with(layerOverrides: next);
  }

  /// This delta with [cel] turned off, or back on.
  ExportCelsCutDelta withCelSkipped(ExportCelRef cel, bool skipped) =>
      _with(skippedCels: _held(skippedCels, cel, skipped));

  /// The directions laid over [cel].
  Set<ExportCelRef> directionsOver(ExportCelRef cel) => {
    for (final laid in directionOver)
      if (laid.cel == cel) laid.direction,
  };

  /// This delta with [direction] laid over [cel], or taken off it.
  ExportCelsCutDelta withDirectionOver(
    ExportCelRef cel,
    ExportCelRef direction,
    bool laid,
  ) => _with(
    directionOver: _held(directionOver, (cel: cel, direction: direction), laid),
  );

  /// [set] holding [member], or not.
  static Set<T> _held<T>(Set<T> set, T member, bool held) {
    final next = Set<T>.from(set);
    if (held) {
      next.add(member);
    } else {
      next.remove(member);
    }
    return next;
  }

  /// The row exceptions dropped, the rest kept — a filter press re-applies
  /// the rule without touching which drawings are written.
  ExportCelsCutDelta withoutLayerOverrides() =>
      _with(layerOverrides: const {});

  /// Reset: every row back on the rule and every drawing on. What is laid
  /// over a drawing is no answer to a rule, and stays.
  ExportCelsCutDelta backOnTheRules() =>
      ExportCelsCutDelta(directionOver: directionOver);

  static Map<String, dynamic> _refJson(ExportCelRef ref) => {
    'row': ref.row.value,
    'cel': ref.cel.value,
  };

  static ExportCelRef _refFromJson(Map<String, dynamic> json) => (
    row: LayerId(json['row'] as String),
    cel: FrameId(json['cel'] as String),
  );

  /// One spelling whatever order the hand worked in, so a saved file does
  /// not change when nothing did.
  static String _order(ExportCelRef ref) =>
      '${ref.row.value}\u0000${ref.cel.value}';

  Map<String, dynamic> toJson() => {
    'layerOverrides': {
      for (final entry in layerOverrides.entries)
        entry.key.value: entry.value,
    },
    if (skippedCels.isNotEmpty)
      'skippedCels': [
        for (final cel
            in skippedCels.toList()
              ..sort((a, b) => _order(a).compareTo(_order(b))))
          _refJson(cel),
      ],
    if (directionOver.isNotEmpty)
      'directionOver': [
        for (final laid
            in directionOver.toList()..sort(
              (a, b) => '${_order(a.cel)}\u0000${_order(a.direction)}'
                  .compareTo('${_order(b.cel)}\u0000${_order(b.direction)}'),
            ))
          {'on': _refJson(laid.cel), 'lay': _refJson(laid.direction)},
      ],
  };

  static ExportCelsCutDelta fromJson(Map<String, dynamic> json) {
    final raw = json['layerOverrides'] as Map<String, dynamic>? ?? const {};
    final skipped = json['skippedCels'] as List<dynamic>? ?? const [];
    final over = json['directionOver'] as List<dynamic>? ?? const [];
    return ExportCelsCutDelta(
      layerOverrides: {
        for (final entry in raw.entries)
          LayerId(entry.key): entry.value as bool,
      },
      skippedCels: {
        for (final cel in skipped) _refFromJson(cel as Map<String, dynamic>),
      },
      directionOver: {
        for (final laid in over.cast<Map<String, dynamic>>())
          (
            cel: _refFromJson(laid['on'] as Map<String, dynamic>),
            direction: _refFromJson(laid['lay'] as Map<String, dynamic>),
          ),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportCelsCutDelta &&
          mapEquals(other.layerOverrides, layerOverrides) &&
          setEquals(other.skippedCels, skippedCels) &&
          setEquals(other.directionOver, directionOver);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered([
      for (final entry in layerOverrides.entries)
        Object.hash(entry.key, entry.value),
    ]),
    Object.hashAllUnordered(skippedCels),
    Object.hashAllUnordered(directionOver),
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
