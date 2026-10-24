import '../core/collection_equality.dart';
import '../core/copy_with_sentinel.dart';
import 'attached_mode.dart';
import 'conte_key.dart';
import 'layer.dart';
import 'layer_blend_mode.dart';
import 'layer_effect.dart';
import 'layer_kind.dart';
import 'layer_mark.dart';

export 'conte_key.dart';

/// 🚨★★★A TRACK'S CONTE HAS ONE STRUCTURE, AND EVERY CUT'S CONTE WEARS IT
/// (F-343).
///
/// 🗣️유저 2026-10-12: 「콘티레이어 좀 더 글로벌트랙으로서 존재하도록 … 그런
/// 구조나 이름 글로벌에 존재하도록해서 모든 컷에서 콘티레이어에서 만든 어태나
/// 레이어구조 동일하게 보이도록」 · 「다만 프레임 이름 링크. 즉 프레임 블록
/// 기준은 로컬」 · 「비슷한 버튼의 로직을 바꾸란게아니라 구조적으로 결과적으로
/// 그렇게 되도록」; 10-14: 「콘티행을 확실하게 글로벌행으로 … 구조 자체는
/// 글로벌기준으로 해서 컷마다 구조 동일하게 되는거」.
///
/// So what the conte groups of a track's cuts have as ONE — the rows and
/// 공정 folders riding the conte, their order, their side of it, the folder
/// each is filed in, and the head each one wears ([ConteHead]) — is the
/// track's, written here once. What a cut's conte keeps of its own is what
/// its rows HOLD: their panels and pictures, the values and keys of their
/// fx. A row says which row of this it is by its [Layer.conteKey].
///
/// ↩️Whether a row prints on its cut's timesheet was each cut's own too,
/// until the conte panel's head took the sheet switch: 🗣️I-89-Q22 (유저
/// 2026-10-16): 「공통으로 안되는건 애초에 콘티패널에 버튼두지않음 … 콘티행은
/// 그런부분 글로벌이니까 아니면 글로벌시키고 넣고 머리로 하나」 — the head
/// wears it ([ConteHead.onTimesheet]).
///
/// Every write of the project lays each cut's conte group from this
/// (`trackWithItsConteLaid`), so two cuts cannot show two shapes — whatever
/// verb made the change, and whichever verb comes next.
///
/// 🗣️F-343-Q1 (→ 「콘티가 있는 컷만 — 지금처럼」): it is worn by the cuts
/// that HAVE a conte. A cut without one has none, and a conte born into a
/// cut is born wearing all of it.
final class TrackConte {
  TrackConte({
    this.base,
    List<ConteEntry> below = const [],
    List<ConteEntry> above = const [],
  }) : below = List.unmodifiable(below),
       above = List.unmodifiable(above);

  /// A track no conte has stood on.
  static final TrackConte none = TrackConte();

  /// The head of the conte itself — null while no conte has stood on the
  /// track.
  final ConteHead? base;

  /// The entries under the conte, in the cut's STACK order: bottom first,
  /// so the last is the nearest.
  final List<ConteEntry> below;

  /// The entries over the conte, in the cut's STACK order: the nearest
  /// first.
  final List<ConteEntry> above;

  bool get isEmpty => base == null && below.isEmpty && above.isEmpty;

  /// Every entry, in stack order: [below], then [above].
  Iterable<ConteEntry> get entries => [...below, ...above];

  Map<String, dynamic> toJson() => {
    if (base case final base?) 'base': base.toJson(),
    if (below.isNotEmpty) 'below': [for (final entry in below) entry.toJson()],
    if (above.isNotEmpty) 'above': [for (final entry in above) entry.toJson()],
  };

  factory TrackConte.fromJson(Map<String, dynamic> json) {
    List<ConteEntry> entriesOf(Object? list) => [
      for (final entry in list as List<dynamic>? ?? const [])
        ConteEntry.fromJson(entry as Map<String, dynamic>),
    ];
    final base = json['base'];
    return TrackConte(
      base: base is Map<String, dynamic> ? ConteHead.fromJson(base) : null,
      below: entriesOf(json['below']),
      above: entriesOf(json['above']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackConte &&
          other.base == base &&
          listEquals(other.below, below) &&
          listEquals(other.above, above);

  @override
  int get hashCode =>
      Object.hash(base, Object.hashAll(below), Object.hashAll(above));

  @override
  String toString() => 'TrackConte(base: $base, below: $below, above: $above)';
}

/// One row or 공정 folder riding a track's conte: which it is ([key]), what
/// it wears in every cut ([head]), the folder of the structure it is filed
/// in ([parent] — null at the top of the group), and what a cut that holds
/// none of it is given ([kind], [attachedMode]).
final class ConteEntry {
  const ConteEntry({
    required this.key,
    required this.head,
    this.parent,
    this.kind = LayerKind.storyboard,
    this.attachedMode = AttachedMode.synced,
  });

  final ConteKey key;
  final ConteHead head;
  final ConteKey? parent;

  /// The kind the row it gives a cut is born as — a folder entry's is a
  /// folder kind.
  ///
  /// ⛔Not worn: a cut's row may be turned into another kind on its own,
  /// as a cut's conte itself may (I-73: 「the storyboard toggle turns ONE
  /// cut's conte back into a drawing row, and the others keep theirs」).
  final LayerKind kind;

  /// The attach timing the row it gives a cut is born with — not worn
  /// either: whether a row follows the conte's timing is its content's.
  final AttachedMode attachedMode;

  bool get isFolder => kind.groupsLayers;

  ConteEntry copyWith({
    ConteHead? head,
    Object? parent = copyWithSentinel,
  }) => ConteEntry(
    key: key,
    head: head ?? this.head,
    parent: identical(parent, copyWithSentinel)
        ? this.parent
        : parent as ConteKey?,
    kind: kind,
    attachedMode: attachedMode,
  );

  Map<String, dynamic> toJson() => {
    'key': key.value,
    'head': head.toJson(),
    if (parent case final parent?) 'parent': parent.value,
    if (kind != LayerKind.storyboard) 'kind': kind.toJson(),
    if (attachedMode != AttachedMode.synced)
      'attachedMode': attachedMode.toJson(),
  };

  factory ConteEntry.fromJson(Map<String, dynamic> json) {
    final parent = json['parent'] as String?;
    return ConteEntry(
      key: ConteKey(json['key'] as String),
      head: ConteHead.fromJson(json['head'] as Map<String, dynamic>),
      parent: parent == null ? null : ConteKey(parent),
      kind: json.containsKey('kind')
          ? LayerKind.fromJson(json['kind'])
          : LayerKind.storyboard,
      attachedMode: AttachedMode.fromJson(json['attachedMode']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConteEntry &&
          other.key == key &&
          other.head == head &&
          other.parent == parent &&
          other.kind == kind &&
          other.attachedMode == attachedMode;

  @override
  int get hashCode => Object.hash(key, head, parent, kind, attachedMode);

  @override
  String toString() => 'ConteEntry($key, ${head.name}, parent: $parent)';
}

/// What a row of a track's conte wears in every cut of the track — what the
/// rail draws once for all of them.
///
/// 🗣️The list is I-73's drawn proposal (2026-10-08): 「머리 — 이름 · 라벨 ·
/// 블렌드 · 불투명도 · 눈 · 어태치 구성 · fx 구성 — 트랙의 모든 컷이 하나」,
/// with the fold and the twirls its rail turns (「어태치 접기펼치기버튼등
/// 동일하게 할수있는거 다 넣는거 잊지말고」) — the row's own since F-360: its
/// group's fold, its lanes' twirl and the lane groups open in them. The fx
/// are worn as a SHAPE — which effects, in what order, each on or off
/// ([effectChainWithSharedShape]); their numbers stay each row's own
/// (「칸 — 칸의 자리와 길이, fx 의 값과 키 — 컷마다」). And whether the row
/// prints on the timesheet ([onTimesheet], I-89-Q22).
final class ConteHead {
  const ConteHead({
    required this.name,
    this.mark = LayerMark.none,
    this.blendMode = LayerBlendMode.normal,
    this.opacity = 1.0,
    this.isVisible = true,
    this.onTimesheet = true,
    this.transformEnabled = true,
    this.effects = const [],
    this.collapsed = false,
    this.lanesExpanded = false,
    this.expandedLaneGroups = const {},
  });

  /// The head [layer] wears.
  factory ConteHead.of(Layer layer) => ConteHead(
    name: layer.name,
    mark: layer.mark,
    blendMode: layer.blendMode,
    opacity: layer.opacity,
    isVisible: layer.isVisible,
    onTimesheet: layer.onTimesheet,
    transformEnabled: layer.transformEnabled,
    effects: layer.effects,
    collapsed: layer.collapsed,
    lanesExpanded: layer.lanesExpanded,
    expandedLaneGroups: layer.expandedLaneGroups,
  );

  final String name;
  final LayerMark mark;
  final LayerBlendMode blendMode;
  final double opacity;
  final bool isVisible;

  /// Whether the row prints on its cut's timesheet — ONE for every cut of
  /// the track, as the conte panel's head draws it once (🗣️I-89-Q22, 유저
  /// 2026-10-16: 「콘티행은 그런부분 글로벌이니까 아니면 글로벌시키고 넣고
  /// 머리로 하나」). ↩️Each cut's own until then.
  final bool onTimesheet;
  final bool transformEnabled;

  /// The chain whose SHAPE is worn — its numbers are whichever row's gave
  /// it, and a row that has numbers of its own keeps them.
  final List<LayerEffect> effects;
  final bool collapsed;
  final bool lanesExpanded;
  final Set<String> expandedLaneGroups;

  /// Whether [row] wears this head already.
  bool isWornBy(Layer row) =>
      row.name == name &&
      row.mark == mark &&
      row.blendMode == blendMode &&
      row.opacity == opacity &&
      row.isVisible == isVisible &&
      row.onTimesheet == onTimesheet &&
      row.transformEnabled == transformEnabled &&
      row.collapsed == collapsed &&
      row.lanesExpanded == lanesExpanded &&
      setEquals(row.expandedLaneGroups, expandedLaneGroups) &&
      sameEffectChainShape(row.effects, effects);

  /// [row] wearing this head — [row] itself when it does already, so a cut
  /// that wore it keeps its instance.
  Layer wornBy(Layer row) => isWornBy(row)
      ? row
      : row.copyWith(
          name: name,
          mark: mark,
          blendMode: blendMode,
          opacity: opacity,
          isVisible: isVisible,
          onTimesheet: onTimesheet,
          transformEnabled: transformEnabled,
          effects: effectChainWithSharedShape(effects, onto: row.effects),
          collapsed: collapsed,
          lanesExpanded: lanesExpanded,
          expandedLaneGroups: expandedLaneGroups,
        );

  /// This head with what [after] changed of [before] — a row of the conte
  /// edited in its cut: each field the edit changed, and only those.
  ConteHead editedBy(Layer before, Layer after) {
    T changed<T>(T Function(Layer layer) field, T kept) =>
        field(after) == field(before) ? kept : field(after);
    return ConteHead(
      name: changed((layer) => layer.name, name),
      mark: changed((layer) => layer.mark, mark),
      blendMode: changed((layer) => layer.blendMode, blendMode),
      opacity: changed((layer) => layer.opacity, opacity),
      isVisible: changed((layer) => layer.isVisible, isVisible),
      onTimesheet: changed((layer) => layer.onTimesheet, onTimesheet),
      transformEnabled: changed(
        (layer) => layer.transformEnabled,
        transformEnabled,
      ),
      effects: sameEffectChainShape(after.effects, before.effects)
          ? effects
          : after.effects,
      collapsed: changed((layer) => layer.collapsed, collapsed),
      lanesExpanded: changed((layer) => layer.lanesExpanded, lanesExpanded),
      expandedLaneGroups:
          setEquals(after.expandedLaneGroups, before.expandedLaneGroups)
          ? expandedLaneGroups
          : after.expandedLaneGroups,
    );
  }

  // R8's rule: a default is silence.
  Map<String, dynamic> toJson() => {
    'name': name,
    if (mark != LayerMark.none) 'mark': mark.toJson(),
    if (blendMode != LayerBlendMode.normal) 'blendMode': blendMode.toJson(),
    if (opacity != 1.0) 'opacity': opacity,
    if (!isVisible) 'isVisible': false,
    if (!onTimesheet) 'onTimesheet': false,
    if (!transformEnabled) 'transformEnabled': false,
    if (effects.isNotEmpty)
      'effects': [for (final effect in effects) effect.toJson()],
    if (collapsed) 'collapsed': true,
    if (lanesExpanded) 'lanesExpanded': true,
    if (expandedLaneGroups.isNotEmpty)
      'expandedLaneGroups': [...expandedLaneGroups],
  };

  factory ConteHead.fromJson(Map<String, dynamic> json) => ConteHead(
    name: json['name'] as String,
    mark: json.containsKey('mark')
        ? LayerMark.fromJson(json['mark'])
        : LayerMark.none,
    blendMode: LayerBlendMode.fromJson(json['blendMode']),
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    isVisible: json['isVisible'] as bool? ?? true,
    onTimesheet: json['onTimesheet'] as bool? ?? true,
    transformEnabled: json['transformEnabled'] as bool? ?? true,
    effects: [
      for (final effect in json['effects'] as List<dynamic>? ?? const [])
        LayerEffect.fromJson(effect as Map<String, dynamic>),
    ],
    collapsed: json['collapsed'] as bool? ?? false,
    lanesExpanded: json['lanesExpanded'] as bool? ?? false,
    expandedLaneGroups: {
      for (final laneId
          in json['expandedLaneGroups'] as List<dynamic>? ?? const [])
        laneId as String,
    },
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConteHead &&
          other.name == name &&
          other.mark == mark &&
          other.blendMode == blendMode &&
          other.opacity == opacity &&
          other.isVisible == isVisible &&
          other.onTimesheet == onTimesheet &&
          other.transformEnabled == transformEnabled &&
          listEquals(other.effects, effects) &&
          other.collapsed == collapsed &&
          other.lanesExpanded == lanesExpanded &&
          setEquals(other.expandedLaneGroups, expandedLaneGroups);

  @override
  int get hashCode => Object.hash(
    name,
    mark,
    blendMode,
    opacity,
    isVisible,
    onTimesheet,
    transformEnabled,
    Object.hashAll(effects),
    collapsed,
    lanesExpanded,
    Object.hashAllUnordered(expandedLaneGroups),
  );

  @override
  String toString() => 'ConteHead($name)';
}
