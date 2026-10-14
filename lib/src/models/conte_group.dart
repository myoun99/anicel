import 'attached_layer_resolve.dart'
    show attachedGroupEndIndex, attachedGroupStartIndex;
import 'cut.dart';
import 'layer.dart';
import 'layer_effect.dart' show effectChainWithSharedShape;
import 'layer_id.dart';
import 'layer_kind.dart';

/// A CUT'S CONTE GROUP, AND THE SEATS IN IT (I-73).
///
/// A cut's conte is a GROUP: its BASE — the cut's storyboard row that rides
/// no other — and the attach rows riding it, above and below. The
/// storyboard panel lays every cut's group out as one set of rows on the
/// track's axis, and each of those rows wears ONE head for all the cuts
/// (유저 2026-10-08: 「콘티레이어 권고한대로 머리만 한벌 ok. 맘에드는
/// 생각이야. 겸용컷이랑 같은 느낌이네」 · 「이거만 눈이랑 불투명도조차
/// 링크하도록. 그거마저 머리로서 하나로되도록 통일」).
///
/// So a row of the group needs a name that is the same in every cut, and
/// no layer id is one — each cut keeps its own layers. That name is its
/// SEAT: 0 for the base, +k for the k-th attach row above it and −k for
/// the k-th below, counted from the base outward in the cut's stack.

/// Whether [layer] is a cut's conte BASE: a storyboard row that rides no
/// other.
///
/// 🚨NOT 「a storyboard row」. An attach row made from the conte row is a
/// storyboard row too — it takes its base's kind
/// (`FoldersAndAttachments.addAttachedLayer`) — and one attached BELOW sits
/// before its base in the cut's list. Measured 2026-10-08: after 「어태치
/// 추가 — 아래」 on a conte row, 「the first storyboard row」 named the
/// attach row, and everything that asks for the cut's conte — the strip,
/// the conte sheet, the trims — followed it there.
bool isConteBase(Layer layer) =>
    layer.kind == LayerKind.storyboard && !isAttachedLayer(layer);

/// Whether [layer] rides the CONTE of [stack] — a row of its conte group
/// other than the conte itself.
///
/// 🗣️I-73-one-head-Q1 (유저 2026-10-09 → `refuse`): 「콘티의 어태치 행은
/// 떼지 못하게 한다」. Such a row is never let go — neither by the menu's
/// 어태치 해제 nor by dragging it out of its group: an attach row takes its
/// base's kind, so a let-go one would be a second conte in its cut, and the
/// same seat of the track's other cuts would keep theirs.
bool ridesTheConte(Layer layer, Iterable<Layer> stack) {
  final baseId = layer.attachedToLayerId;
  if (baseId == null) {
    return false;
  }
  for (final other in stack) {
    if (other.id == baseId) {
      return isConteBase(other);
    }
  }
  return false;
}

/// The cut's storyboard row — its conte BASE ([isConteBase]) — or null
/// when it has none.
///
/// A cut may hold at most ONE (the conte has one strip per cut, and the
/// coverage rule has one row to tile it). The verbs that could make a
/// second refuse — see [cutAcceptsAnotherStoryboardLayer] — but this does
/// NOT throw when it finds one anyway: it is read from painters and row
/// builds, and a throw there took the whole frame down with a red screen
/// (user, 2026-07-28). A file written by an older build, or a path nobody
/// guarded yet, must degrade to "the first one is the row" rather than to
/// no editor at all. [storyboardLayersOfCut] is how a caller that wants to
/// SAY something about the duplicate finds it.
Layer? storyboardLayerForCut(Cut cut) {
  for (final layer in cut.layers) {
    if (isConteBase(layer)) {
      return layer;
    }
  }
  return null;
}

/// Every conte base on [cut] — one in every reachable state, more only
/// where something already went wrong.
List<Layer> storyboardLayersOfCut(Cut cut) => [
  for (final layer in cut.layers)
    if (isConteBase(layer)) layer,
];

/// Whether [cut] may take another storyboard row — false once it has one.
///
/// [exceptLayerId] is the layer being CONVERTED, which does not count
/// against itself: re-applying the kind to the row that already is one is
/// a no-op, not a second row.
bool cutAcceptsAnotherStoryboardLayer(Cut cut, {LayerId? exceptLayerId}) {
  for (final layer in cut.layers) {
    if (isConteBase(layer) && layer.id != exceptLayerId) {
      return false;
    }
  }
  return true;
}

/// One row of a cut's conte group: where it sits, and the layer there.
typedef ConteSeat = ({int seat, Layer row});

/// [cut]'s conte group, TOP ROW FIRST — the order a rail draws it: the
/// attach rows above the base from the farthest (+N) down to the nearest
/// (+1), the base (0), then the rows below it from the nearest (−1) to the
/// farthest (−N). Empty when the cut has no conte.
///
/// A seat counts the base's attach ROWS in the cut's own stack — the list
/// keeps a group as `[below…, base, above…]` — and passes over the
/// organizer folders among them: a folder files rows, it is not one.
///
/// 🚨ONE GROUP PER CUT (I-57, 10-14): a cut is immutable, so its group is
/// what it was the first time it was asked, and every later ask is handed
/// that list ([_conteGroups]). Read off the cut per ask, every ask of the
/// storyboard rail's seat list read the group of every cut of the track
/// again — and that list was 18% of a cut crossing's layout on the AMMI OP
/// (🔬CPU samples, 10-14).
List<ConteSeat> conteGroupOf(Cut cut) =>
    _conteGroups[cut] ??= _conteGroupReadOff(cut);

/// [conteGroupOf]'s answer for each cut instance, held weakly — it goes
/// when the cut does.
final Expando<List<ConteSeat>> _conteGroups = Expando('conte group');

List<ConteSeat> _conteGroupReadOff(Cut cut) {
  final layers = cut.layers;
  final baseIndex = layers.indexWhere(isConteBase);
  if (baseIndex < 0) {
    return const [];
  }
  final base = layers[baseIndex];
  final above = <Layer>[
    for (var index = baseIndex + 1; index < layers.length; index += 1)
      if (layers[index].attachedToLayerId == base.id) layers[index],
  ];
  final below = <Layer>[
    for (var index = baseIndex - 1; index >= 0; index -= 1)
      if (layers[index].attachedToLayerId == base.id) layers[index],
  ];
  return List.unmodifiable([
    for (var k = above.length; k >= 1; k -= 1) (seat: k, row: above[k - 1]),
    (seat: 0, row: base),
    for (var k = 1; k <= below.length; k += 1) (seat: -k, row: below[k - 1]),
  ]);
}

/// Where [layerId] sits in [cut]'s conte group; null when it is not in it.
int? conteSeatOf(Cut cut, LayerId layerId) {
  for (final entry in conteGroupOf(cut)) {
    if (entry.row.id == layerId) {
      return entry.seat;
    }
  }
  return null;
}

/// The row at [seat] of [cut]'s conte group; null where the cut holds none
/// there.
Layer? conteRowAtSeat(Cut cut, int seat) {
  for (final entry in conteGroupOf(cut)) {
    if (entry.seat == seat) {
      return entry.row;
    }
  }
  return null;
}

/// [cut]'s conte group when its slice of the stack holds the conte and its
/// attach rows alone — no organizer folder, no row filed in one; else null,
/// a cut with no conte included.
///
/// The groups a STRUCTURE edit is carried between (I-73-one-head-Q2): a
/// folder files rows, so its members' seats and its own place are two
/// answers a seat alone cannot carry, and a group holding one stands down
/// as `folder_mirror` does where structures diverged.
List<ConteSeat>? plainConteGroupOf(Cut cut) {
  final group = conteGroupOf(cut);
  if (group.isEmpty) {
    return null;
  }
  final base = group.firstWhere((entry) => entry.seat == 0).row;
  final slice = cut.layers.sublist(
    attachedGroupStartIndex(base.id, cut.layers),
    attachedGroupEndIndex(base.id, cut.layers),
  );
  final plain = slice.every(
    (layer) =>
        layer.id == base.id ||
        (layer.attachedToLayerId == base.id &&
            layer.folderId == base.folderId),
  );
  return plain && slice.length == group.length ? group : null;
}

/// Where a row BORN at [seat] of [cut]'s conte group goes in the stack —
/// on that seat, the rows from it outward each one seat farther — while
/// the group is plain ([plainConteGroupOf]) and holds, on [seat]'s side of
/// the conte, exactly the seats of [seats] — the group it was born in,
/// before it; null otherwise: a group shaped differently there would put
/// it on another seat. The other side numbers its seats from the conte on
/// its own, so it is not asked.
int? conteSeatInsertIndex(Cut cut, int seat, {required List<int> seats}) {
  final group = plainConteGroupOf(cut);
  final side = [
    for (final held in seats)
      if (held.sign == seat.sign) held,
  ];
  final there = group == null
      ? null
      : [
          for (final entry in group)
            if (entry.seat.sign == seat.sign) entry.seat,
        ];
  if (there == null ||
      there.length != side.length ||
      !there.indexed.every((entry) => entry.$2 == side[entry.$1])) {
    return null;
  }
  // The row it sits beside on the conte's side: the seat one nearer.
  final nearer = conteRowAtSeat(cut, seat > 0 ? seat - 1 : seat + 1);
  if (nearer == null) {
    return null;
  }
  final at = cut.layers.indexWhere((layer) => layer.id == nearer.id);
  // Above, it goes over the nearer row; below, under it.
  return seat > 0 ? at + 1 : at;
}

/// The seats the conte groups of [cuts] hold between them, TOP ROW FIRST:
/// from the highest attach row any cut has, through the base, to the lowest.
/// The base's seat is always there — a track whose cuts have no conte yet
/// still shows the row its first one will stand on.
List<int> conteSeatsOf(Iterable<Cut> cuts) {
  var top = 0;
  var bottom = 0;
  for (final cut in cuts) {
    final group = conteGroupOf(cut);
    if (group.isEmpty) {
      continue;
    }
    if (group.first.seat > top) {
      top = group.first.seat;
    }
    if (group.last.seat < bottom) {
      bottom = group.last.seat;
    }
  }
  return [for (var seat = top; seat >= bottom; seat -= 1) seat];
}

/// The row that SPEAKS for [seat] on a track, and the cut it stands in: the
/// first of [cuts], in their order, that holds one there — the head the
/// storyboard's rail draws for the seat. Null while no cut has a row there.
({Cut cut, Layer row})? conteHeadAt(Iterable<Cut> cuts, int seat) {
  for (final cut in cuts) {
    final row = conteRowAtSeat(cut, seat);
    if (row != null) {
      return (cut: cut, row: row);
    }
  }
  return null;
}

/// [conteHeadAt]'s row alone.
Layer? conteHeadRowAt(Iterable<Cut> cuts, int seat) =>
    conteHeadAt(cuts, seat)?.row;

/// The rows of [cuts] that wear ONE head, family by family: the rows that
/// sit at one seat of their cuts' conte groups — top seat first.
List<List<LayerId>> conteHeadFamiliesOf(Iterable<Cut> cuts) => [
  for (final seat in conteSeatsOf(cuts)) conteHeadFamilyAt(cuts, seat),
];

/// The family of [conteHeadFamiliesOf] at [seat]: the rows of [cuts] that
/// sit there, in the cuts' order.
List<LayerId> conteHeadFamilyAt(Iterable<Cut> cuts, int seat) => [
  for (final cut in cuts)
    if (conteRowAtSeat(cut, seat) case final row?) row.id,
];

/// [row] wearing [head]'s HEAD — everything a track's conte rows have as
/// one: the name, the label, the blend, the static opacity, the eye, the
/// transform switch, and the SHAPE of the fx chain laid over [row]'s own
/// values ([effectChainWithSharedShape]).
///
/// 🗣️The list is the drawn proposal's (I-73, 2026-10-08): 「머리 — 이름 ·
/// 라벨 · 블렌드 · 불투명도 · 눈 · 어태치 구성 · fx 구성 — 트랙의 모든 컷이
/// 하나」 · 「칸 — 칸의 자리와 길이, fx 의 값과 키 — 컷마다」. What a row
/// HOLDS stays its own: its kind, its pictures and panels, its fx values —
/// and whether it prints on its cut's timesheet, which that list does not
/// name.
///
/// A row is BORN wearing it (`plannedAddLayerCommand`); after that every
/// head field is written to all the rows at the seat at once
/// (`headMirrorTargets`, and `conteHeadTargets` for the eye).
///
/// Its folds and twirls too (I-73 「콘티행도 동일하게 … 어태치
/// 접기펼치기버튼등 동일하게 할수있는거 다 넣는거 잊지말고」): they are the
/// row's since F-360, and a row born open beside a folded family is the
/// row `RailView.followHeads` was there to fold.
Layer layerWearingHeadOf(Layer head, Layer row) => row.copyWith(
  name: head.name,
  mark: head.mark,
  blendMode: head.blendMode,
  opacity: head.opacity,
  isVisible: head.isVisible,
  transformEnabled: head.transformEnabled,
  effects: effectChainWithSharedShape(head.effects, onto: row.effects),
  collapsed: head.collapsed,
  lanesExpanded: head.lanesExpanded,
  expandedLaneGroups: head.expandedLaneGroups,
);
