import 'cut.dart';
import 'layer.dart';
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
List<ConteSeat> conteGroupOf(Cut cut) {
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
  return [
    for (var k = above.length; k >= 1; k -= 1) (seat: k, row: above[k - 1]),
    (seat: 0, row: base),
    for (var k = 1; k <= below.length; k += 1) (seat: -k, row: below[k - 1]),
  ];
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

/// The row that SPEAKS for [seat] on a track: the first of [cuts], in their
/// order, that holds one there — the head the storyboard's rail draws for
/// the seat. Null while no cut has a row there.
Layer? conteHeadRowAt(Iterable<Cut> cuts, int seat) {
  for (final cut in cuts) {
    final row = conteRowAtSeat(cut, seat);
    if (row != null) {
      return row;
    }
  }
  return null;
}
