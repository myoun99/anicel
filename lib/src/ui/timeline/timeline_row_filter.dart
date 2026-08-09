import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';

/// The timeline rail's row FILTER (R-toolbar round 2): a VIEW state that
/// hides layer rows failing its predicate — like [hiddenSections] but
/// per-layer. Project state is never touched; export/save ignore it.
///
/// All active facets combine with AND (user rule): a mark-color set, a
/// layer-kind set and the sheet/fx/fill-reference flags must ALL pass. An
/// empty filter passes everything. The active layer is exempt (the host
/// keeps the layer you're working on visible so a filter can't hide your
/// own strokes).
class TimelineRowFilter {
  const TimelineRowFilter({
    this.markColors = const {},
    this.kinds = const {},
    this.onTimesheetOnly = false,
    this.fxOnly = false,
    this.fillReferenceOnly = false,
  });

  static const TimelineRowFilter none = TimelineRowFilter();

  /// When non-empty, a layer passes only if its mark is in this set.
  final Set<LayerMark> markColors;

  /// When non-empty, a layer passes only if its kind is in this set (the
  /// legend's kind-icon solo, R4 #8).
  final Set<LayerKind> kinds;

  /// When true, only timesheet-on layers pass.
  final bool onTimesheetOnly;

  /// When true, only fx-enabled layers pass. FX enablement is session view
  /// state, so the predicate takes it as a parameter.
  final bool fxOnly;

  /// When true, only fill-reference layers pass.
  final bool fillReferenceOnly;

  bool get isActive =>
      markColors.isNotEmpty ||
      kinds.isNotEmpty ||
      onTimesheetOnly ||
      fxOnly ||
      fillReferenceOnly;

  /// Whether [layer] passes every active facet (AND). [fxEnabled] resolves
  /// the layer's session-level fx state for the [fxOnly] facet.
  bool allows(Layer layer, {required bool fxEnabled}) => allowsFacets(
    mark: layer.mark,
    kind: layer.kind,
    onTimesheet: layer.onTimesheet,
    fxEnabled: fxEnabled,
    isFillReference: layer.isFillReference,
  );

  /// Whether a row passes, judged ONLY on the facets it actually carries
  /// (R5 #9, the user's rule: "차이두지마").
  ///
  /// A null field means the row HAS no such facet, and a chip never hides a
  /// row it cannot judge. One rule, applied to whatever the row is: a
  /// storyboard V row carries `fxEnabled` and nothing else, so the fx chip
  /// filters it exactly like a layer while the mark chip leaves it alone —
  /// not because it is a track, but because a track has no mark.
  ///
  /// Judging the missing ones as FAILURES was the alternative, and it is
  /// not a filter: turning on any mark would empty the storyboard whatever
  /// the mark was.
  ///
  /// When a row kind later gains a facet — the user means to give tracks a
  /// mark — the call site passes it and the chip starts working there with
  /// no change to this rule.
  bool allowsFacets({
    LayerMark? mark,
    LayerKind? kind,
    bool? onTimesheet,
    required bool fxEnabled,
    bool? isFillReference,
  }) {
    if (mark != null && markColors.isNotEmpty && !markColors.contains(mark)) {
      return false;
    }
    if (kind != null && kinds.isNotEmpty && !kinds.contains(kind)) {
      return false;
    }
    if (onTimesheet == false && onTimesheetOnly) {
      return false;
    }
    if (fxOnly && !fxEnabled) {
      return false;
    }
    if (isFillReference == false && fillReferenceOnly) {
      return false;
    }
    return true;
  }

  TimelineRowFilter copyWith({
    Set<LayerMark>? markColors,
    Set<LayerKind>? kinds,
    bool? onTimesheetOnly,
    bool? fxOnly,
    bool? fillReferenceOnly,
  }) {
    return TimelineRowFilter(
      markColors: markColors ?? this.markColors,
      kinds: kinds ?? this.kinds,
      onTimesheetOnly: onTimesheetOnly ?? this.onTimesheetOnly,
      fxOnly: fxOnly ?? this.fxOnly,
      fillReferenceOnly: fillReferenceOnly ?? this.fillReferenceOnly,
    );
  }

  /// Toggles [mark] in the color set.
  TimelineRowFilter toggledMark(LayerMark mark) {
    final next = Set<LayerMark>.of(markColors);
    if (!next.remove(mark)) {
      next.add(mark);
    }
    return copyWith(markColors: next);
  }

  /// Toggles [kind] in the kind set.
  TimelineRowFilter toggledKind(LayerKind kind) {
    final next = Set<LayerKind>.of(kinds);
    if (!next.remove(kind)) {
      next.add(kind);
    }
    return copyWith(kinds: next);
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineRowFilter &&
        _setEquals(other.markColors, markColors) &&
        _setEquals(other.kinds, kinds) &&
        other.onTimesheetOnly == onTimesheetOnly &&
        other.fxOnly == fxOnly &&
        other.fillReferenceOnly == fillReferenceOnly;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(markColors),
    Object.hashAllUnordered(kinds),
    onTimesheetOnly,
    fxOnly,
    fillReferenceOnly,
  );
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final value in a) {
    if (!b.contains(value)) {
      return false;
    }
  }
  return true;
}
