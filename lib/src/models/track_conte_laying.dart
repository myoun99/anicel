import '../core/mapped_or_same.dart';
import 'attached_layer_resolve.dart' show attachedGroupMembers;
import 'attached_placement.dart';
import 'conte_group.dart' show conteGroupOf;
import 'cut.dart';
import 'cut_id.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'layer_link_registry.dart';
import 'project.dart';
import 'track.dart';
import 'track_conte.dart';

/// [project] with every track's conte laid ([trackWithItsConteLaid]) — and
/// the rows that laying gave the cuts of a 겸용 pair made ONE LAYER.
///
/// 🗣️A 겸용 pair's cuts hold their rows as one layer, the rows of a
/// track's conte among them (I-73: 「A planted row's 겸용 siblings still
/// take it AS the same layer」). So the rows the structure gives, in one
/// write, to cuts whose contes are one layer — for one row of it — are one
/// link group. ↩️F-343 gave each cut its own, and what was drawn on one
/// was not on the other.
///
/// Those link groups are the laying's to keep: a row of one that is gone —
/// taken back with the step that gave it (`dropConteFills`), or a folder
/// the structure forgot — goes from it, and a group left linking nothing
/// goes too.
Project projectWithItsContesLaid(
  Project project, {
  required Cut? Function(CutId cutId) settledCut,
}) {
  final tracks = mappedOrSame(
    project.tracks,
    (track) => trackWithItsConteLaid(track, settledCut: settledCut),
  );
  final laid = identical(tracks, project.tracks)
      ? project
      : project.copyWith(tracks: tracks);
  final registry = laid.linkRegistry;
  final kept = _withoutGoneFills(laid, registry.groups);
  final made = _groupsOfRowsGiven(laid, conteFillsGiven(project, laid));
  if (identical(kept, registry.groups) && made.isEmpty) {
    return laid;
  }
  return laid.copyWith(
    linkRegistry: registry.copyWith(groups: [...kept, ...made]),
  );
}

/// The rows the structure gave the cuts between [before] and [after]: each
/// one [after] holds that the same cut of [before] did not ([isConteFill]).
Set<LayerId> conteFillsGiven(Project? before, Project? after) {
  if (after == null || identical(before, after)) {
    return const {};
  }
  final was = {
    for (final track in before?.tracks ?? const <Track>[])
      for (final cut in track.cuts) cut.id: cut,
  };
  final given = <LayerId>{};
  for (final track in after.tracks) {
    for (final cut in track.cuts) {
      final old = was[cut.id];
      if (identical(old, cut)) {
        continue;
      }
      final had = {
        for (final layer in old?.layers ?? const <Layer>[])
          if (isConteFill(layer)) layer.id,
      };
      for (final layer in cut.layers) {
        if (isConteFill(layer) && !had.contains(layer.id)) {
          given.add(layer.id);
        }
      }
    }
  }
  return given;
}

/// A head the structure PUT ON a row that joined its cut's conte in a
/// write ([conteHeadsPut]): the row as laid, and the head it wore of its
/// own.
typedef ConteHeadPut = ({CutId cutId, Layer laid, ConteHead own});

/// The heads laying [written] into [laid] put on rows [before] held in no
/// conte — a row made a cut's conte wears its track's head
/// (I-73), and the undo of the write that made it takes that head off
/// again (`ConteStepScope`).
///
/// 🗣️F-424 (유저 2026-10-21): 「기존 레이어 콘티레이어 변경하고 언두하면
/// 색라벨도 돌아오도록」 — the undo gave the kind back, and the row went on
/// wearing the conte's label and name: no laying takes a head off a row
/// that has left the conte.
List<ConteHeadPut> conteHeadsPut(
  Project? before,
  Project written,
  Project laid,
) {
  if (identical(written, laid)) {
    return const [];
  }
  final was = {
    for (final track in before?.tracks ?? const <Track>[])
      for (final cut in track.cuts) cut.id: cut,
  };
  final wrote = {
    for (final track in written.tracks)
      for (final cut in track.cuts) cut.id: cut,
  };
  final put = <ConteHeadPut>[];
  for (final track in laid.tracks) {
    for (final cut in track.cuts) {
      final own = wrote[cut.id];
      final old = was[cut.id];
      if (own == null || old == null || identical(own, cut)) {
        continue;
      }
      final rode = {for (final row in _conteRowsOf(old)) row.id};
      for (final row in _conteRowsOf(cut)) {
        final mine = own.layers.byId(row.id);
        // A row the write made goes with its undo, head and all.
        if (mine == null ||
            rode.contains(row.id) ||
            old.layers.byId(row.id) == null) {
          continue;
        }
        final head = ConteHead.of(mine);
        if (!head.isWornBy(row)) {
          put.add((cutId: cut.id, laid: row, own: head));
        }
      }
    }
  }
  return put;
}

/// [row] with the head [put] laid on it taken off: each field it still
/// wears as laid goes back to its own, and one changed since stays.
Layer withConteHeadTakenOff(Layer row, ConteHeadPut put) =>
    put.own.editedBy(put.laid, row).wornBy(row);

/// The rows of [cut]'s conte as the laying reads them — its base and the
/// rows of the base's group — or none when it has no conte.
List<Layer> _conteRowsOf(Cut? cut) {
  if (cut == null) {
    return const [];
  }
  final base = conteBaseOf(cut);
  return base == null ? const [] : attachedGroupMembers(base.id, cut.layers);
}

/// [groups] without their members that are rows the structure gave a cut
/// which the cut no longer holds — a group left linking nothing going with
/// them — or [groups] itself when none is gone.
List<LayerLinkGroup> _withoutGoneFills(
  Project project,
  List<LayerLinkGroup> groups,
) {
  bool given(LayerLinkMember member) =>
      member.layerId.value.startsWith(_fillPrefix);
  if (!groups.any((group) => group.members.any(given))) {
    return groups;
  }
  final held = {
    for (final track in project.tracks)
      for (final cut in track.cuts)
        for (final layer in cut.layers)
          if (isConteFill(layer)) (cut.id, layer.id),
  };
  bool gone(LayerLinkMember member) =>
      given(member) && !held.contains((member.cutId, member.layerId));
  if (!groups.any((group) => group.members.any(gone))) {
    return groups;
  }
  return [
    for (final group in groups)
      if (!group.members.any(gone))
        group
      else if (group.members.where((member) => !gone(member)).toList()
          case final left when left.length > 1)
        group.copyWith(members: left),
  ];
}

/// The link groups the rows [given] make: the ones given for one row of
/// the structure to cuts whose contes are one link group, the first cut's
/// first — the group's canonical member.
List<LayerLinkGroup> _groupsOfRowsGiven(Project project, Set<LayerId> given) {
  if (given.isEmpty) {
    return const [];
  }
  final registry = project.linkRegistry;
  final byRow = <String, List<LayerLinkMember>>{};
  for (final track in project.tracks) {
    for (final cut in track.cuts) {
      final base = conteBaseOf(cut);
      final contes = base == null
          ? null
          : registry.groupOf(cutId: cut.id, layerId: base.id);
      if (contes == null) {
        continue;
      }
      for (final layer in cut.layers) {
        if (layer.conteKey case final key? when given.contains(layer.id)) {
          (byRow['${contes.id}~${key.value}'] ??= []).add(
            LayerLinkMember(
              trackId: track.id,
              cutId: cut.id,
              layerId: layer.id,
            ),
          );
        }
      }
    }
  }
  return [
    for (final MapEntry(key: id, value: members) in byRow.entries)
      if (members.length > 1) LayerLinkGroup(id: id, members: members),
  ];
}

/// [track] with every cut's conte laid from the track's conte STRUCTURE —
/// the structure first taking what this write did to the conte of a cut
/// (F-343, [TrackConte]).
///
/// 🗣️유저 2026-10-12: 「비슷한 버튼의 로직을 바꾸란게아니라 구조적으로
/// 결과적으로 그렇게 되도록」. So no verb plants rows in the other cuts or
/// writes a head into them: a verb changes the cut it changes, the way it
/// always did, and this — run on EVERY write of the project, the one place
/// every verb, undo and open goes through — makes that change the track's:
///
/// 1. A row riding a cut's conte names its row of the structure by its
///    [Layer.conteKey]. One that names none the structure holds — a row a
///    verb just made, or one from a file written before the track kept a
///    structure — is the structure's row at ITS SEAT, when this cut does
///    not hold that one already; otherwise it is a new row of the
///    structure, standing where it stands in its cut ([_Structure.place]).
///    That one rule lays a file whose cuts' contes diverged: every seat any
///    cut has, worn as the first cut that has it wears it.
/// 2. What a write changed of a row — its head, its place, its folder — is
///    read against the cut as the last write left it ([settledCut]), and
///    becomes the structure's. Where two cuts changed one thing in one
///    write, the first cut of the track speaks.
/// 3. A row of the structure no cut's conte holds any more is gone — what a
///    delete of it in every cut leaves — and so is a 공정 folder left with
///    no row to file: an empty folder organizes nothing (the attach group's
///    own rule, `attachOrganizerBaseOf`).
/// 4. Every cut's conte is laid from what the structure then is: its rows
///    in the structure's order, each wearing its head, and a row the cut
///    has none of given to it empty ([_fillFor]).
///
/// 🚨IT NEVER DELETES A ROW THAT CAN HOLD A PICTURE. A row the structure
/// gave a cut is the cut's the moment it is laid — the user draws on it —
/// and nothing here can tell a drawn one from an empty one: a picture is
/// not in the model. What goes, goes by a verb the user can take back (a
/// delete takes a row from every cut at once, `existenceMirrorTargets`),
/// or with the step that made it (`ConteStepScope`). A folder the
/// structure forgot holds no picture, so the one the structure gave goes,
/// and the cut's own steps out of the group.
///
/// ⚠️A cut without a conte is left alone (F-343-Q1): the structure is worn
/// by the cuts that have one.
///
/// Identity-preserving: a cut whose conte wears the structure already is
/// handed back as the very instance it came in as (the strip and the rail
/// tell 「nothing moved」 by that instance — the I-57 memo).
Track trackWithItsConteLaid(
  Track track, {
  required Cut? Function(CutId cutId) settledCut,
}) {
  if (track.cuts.every((cut) => identical(_laidFrom[cut], track.conte))) {
    return track;
  }
  final contes = [
    for (final cut in track.cuts)
      if (conteBaseOf(cut) case final base?) (cut: cut, base: base),
  ];
  if (contes.isEmpty) {
    return _withNoConteLeft(track);
  }
  final structure = _Structure(track.conte);
  final groups = [
    for (final conte in contes) structure.resolve(conte.cut, conte.base),
  ];
  // The first cut speaks: the later cuts' edits go in first, so an earlier
  // cut's edit of the same thing is the one that stays.
  for (final group in groups.reversed) {
    final settled = settledCut(group.cut.id);
    if (settled == null || identical(settled, group.cut)) {
      continue;
    }
    final was = _GroupOf.settled(settled);
    // A conte the last write did not see on this cut is new to it, as a
    // new cut's is: it has changed nothing of the structure yet.
    if (was.base?.id == group.base!.id) {
      structure.takeEditsOf(group, was);
    }
  }
  structure.forgetWhatNoCutHolds(groups);
  structure.forgetFoldersFilingNothing();
  structure.baseHead ??= ConteHead.of(contes.first.base);
  final laid = structure.build(track.conte);
  final byId = {for (final group in groups) group.cut.id: group};
  final cuts = [
    for (final cut in track.cuts)
      if (byId[cut.id] case final group?)
        _keyedInItsConte(_laidCut(group, structure), group.base)
      // A cut with no conte read against this structure already holds no
      // key outside one.
      else if (identical(_laidFrom[cut], track.conte))
        cut
      else
        _keyedInItsConte(cut, null),
  ];
  for (final cut in cuts) {
    _laidFrom[cut] = laid;
  }
  final changed =
      !identical(laid, track.conte) ||
      cuts.indexed.any((entry) => !identical(entry.$2, track.cuts[entry.$1]));
  return changed ? track.copyWith(conte: laid, cuts: cuts) : track;
}

/// [track] once no cut of it has a conte: rule 3 with no conte left to hold
/// a row of the structure — it goes, and no row keeps a key outside a
/// conte ([_keyedInItsConte]).
Track _withNoConteLeft(Track track) {
  final cuts = [for (final cut in track.cuts) _keyedInItsConte(cut, null)];
  for (final cut in cuts) {
    _laidFrom[cut] = TrackConte.none;
  }
  return track.conte.isEmpty &&
          cuts.indexed.every((at) => identical(at.$2, track.cuts[at.$1]))
      ? track
      : track.copyWith(conte: TrackConte.none, cuts: cuts);
}

/// The structure each cut instance was laid from, held weakly — a cut laid
/// from the structure its track holds is not read again.
final Expando<TrackConte> _laidFrom = Expando('F-343 laid from');

/// [cut] with no row outside its conte naming a row of the structure — the
/// key a row keeps only while it rides the conte ([Layer.conteKey]). A row
/// a step mounted on the conte, a cut whose conte a step made of a row: the
/// undo that takes them out leaves the cut as it was before, key and all.
/// [cut] itself when no such row is in it; [base] is its conte, or null.
Cut _keyedInItsConte(Cut cut, Layer? base) {
  final riding = base == null
      ? const <LayerId>{}
      : {for (final row in attachedGroupMembers(base.id, cut.layers)) row.id};
  bool stale(Layer layer) =>
      layer.conteKey != null && !riding.contains(layer.id);
  if (!cut.layers.any(stale)) {
    return cut;
  }
  return cut.copyWith(
    layers: [
      for (final layer in cut.layers)
        if (stale(layer)) layer.copyWith(conteKey: null) else layer,
    ],
  );
}

/// [cut]'s conte, read off its group ([conteGroupOf] — once per cut
/// instance, which every write of the project asks of every cut).
Layer? conteBaseOf(Cut cut) {
  for (final entry in conteGroupOf(cut)) {
    if (entry.seat == 0) {
      return entry.row;
    }
  }
  return null;
}

/// The id a cut's empty copy of the structure's row [key] is given — the
/// same every time, so a write that lays it again lays the same row, and a
/// redo finds the row its step's next write was made on.
LayerId conteFillId(ConteKey key, CutId cutId) =>
    LayerId('$_fillPrefix${key.value}@${cutId.value}');

/// Whether [layer] is a row the structure GAVE its cut ([conteFillId]).
bool isConteFill(Layer layer) => layer.id.value.startsWith(_fillPrefix);

const _fillPrefix = 'conte-fill:';

/// [cut] without those of [fills] it holds — a row filed in one of them
/// filed where that one was — or [cut] itself when it holds none.
///
/// ⛔The re-filing is 폴더 해산's law (`DissolveFolderCommand`), kept apart
/// as its SECOND (the rule of three): the command walks one folder through
/// the repository for its undo, this a set of them in one pure pass.
Cut cutWithoutConteFills(Cut cut, Set<LayerId> fills) {
  final gone = {
    for (final layer in cut.layers)
      if (fills.contains(layer.id)) layer.id: layer.folderId,
  };
  if (gone.isEmpty) {
    return cut;
  }
  LayerId? filedIn(LayerId? folderId) {
    var at = folderId;
    while (gone.containsKey(at)) {
      at = gone[at];
    }
    return at;
  }

  return cut.copyWith(
    layers: [
      for (final layer in cut.layers)
        if (!gone.containsKey(layer.id))
          if (gone.containsKey(layer.folderId))
            layer.copyWith(folderId: filedIn(layer.folderId))
          else
            layer,
    ],
  );
}

/// One cut's conte group as this write resolves it: its base, its members
/// wherever they stand in the stack ([attachedGroupMembers]) and the key of
/// the structure's row each member is.
final class _GroupOf {
  _GroupOf(this.cut, this.base, this.members, this.keyOf);

  /// A settled cut's group: every member names its row by its own key —
  /// the last write laid it so.
  factory _GroupOf.settled(Cut cut) {
    final base = conteBaseOf(cut);
    if (base == null) {
      return _GroupOf(cut, null, const [], const {});
    }
    final members = attachedGroupMembers(base.id, cut.layers);
    return _GroupOf(cut, base, members, {
      for (final member in members)
        if (member.conteKey case final key? when !identical(member, base))
          member.id: key,
    });
  }

  final Cut cut;
  final Layer? base;

  /// The base and its members in stack order.
  final List<Layer> members;
  final Map<LayerId, ConteKey> keyOf;

  /// The group's LAYOUT: each member's key in stack order with null for
  /// the base, and the folder each is filed in.
  _Layout get layout => (
    order: [
      for (final member in members)
        if (identical(member, base)) null else ?keyOf[member.id],
    ],
    parents: {
      for (final member in members)
        ?keyOf[member.id]: _keyOfFolder(members, keyOf, member.folderId),
    },
  );
}

/// Where a group's rows stand: their keys in stack order, the conte as
/// null, and the folder each is filed in.
typedef _Layout = ({List<ConteKey?> order, Map<ConteKey, ConteKey?> parents});

/// The structure as this write works it out — a working copy of a
/// [TrackConte], its entries in one stack order with the base as null.
final class _Structure {
  _Structure(TrackConte conte)
    : baseHead = conte.base,
      order = [
        for (final entry in conte.below) entry.key,
        null,
        for (final entry in conte.above) entry.key,
      ],
      entries = {for (final entry in conte.entries) entry.key: entry};

  ConteHead? baseHead;
  final List<ConteKey?> order;
  final Map<ConteKey, ConteEntry> entries;

  /// [cut]'s conte group with each member resolved to the structure's row
  /// it is (rule 1) — and a member that is none of them made one.
  ///
  /// ⛔Nothing is dropped: a member that names a row another member here
  /// holds — a row copied, or pasted — is a row of its own, as a member
  /// that names none is.
  _GroupOf resolve(Cut cut, Layer base) {
    final members = attachedGroupMembers(base.id, cut.layers);
    final baseIndex = members.indexWhere((member) => identical(member, base));
    // Who holds each row of the structure here: a row of the cut's own
    // before one the structure gave it, the lower one before the upper.
    final holder = <ConteKey, Layer>{};
    for (final member in members) {
      final key = member.conteKey;
      if (identical(member, base) || key == null || !entries.containsKey(key)) {
        continue;
      }
      final other = holder[key];
      if (other == null || (isConteFill(other) && !isConteFill(member))) {
        holder[key] = member;
      }
    }
    final keyOf = {
      for (final MapEntry(:key, value: member) in holder.entries)
        member.id: key,
    };
    final born = <Layer>[];
    for (final (index, member) in members.indexed) {
      if (index == baseIndex || keyOf.containsKey(member.id)) {
        continue;
      }
      final atItsPlace = _placeOf(members, baseIndex, index);
      if (atItsPlace != null && !holder.containsKey(atItsPlace)) {
        holder[atItsPlace] = member;
        keyOf[member.id] = atItsPlace;
        continue;
      }
      final key = place(
        member,
        after: _keyBefore(members, keyOf, baseIndex, index),
      );
      holder[key] = member;
      keyOf[member.id] = key;
      born.add(member);
    }
    // A row the structure made of a member wears what the member wears and
    // is filed where the member is filed — read once every member has its
    // key, the folder over it among them.
    for (final member in born) {
      final key = keyOf[member.id]!;
      entries[key] = entries[key]!.copyWith(
        head: ConteHead.of(member),
        parent: _keyOfFolder(members, keyOf, member.folderId),
      );
    }
    return _GroupOf(cut, base, members, keyOf);
  }

  /// The structure's row at the place [members]' member at [index] stands
  /// in its cut: an attach row's seat ([_seatIn]), a folder's turn among
  /// the folders on its side.
  ConteKey? _placeOf(List<Layer> members, int baseIndex, int index) {
    final folder = members[index].kind.groupsLayers;
    final place = _seatIn(
      [for (final member in members) member.kind.groupsLayers == folder],
      baseIndex,
      index,
    );
    final mine = [
      for (final key in order)
        key == null || entries[key]!.isFolder == folder,
    ];
    final base = order.indexOf(null);
    for (final (at, key) in order.indexed) {
      if (key != null &&
          entries[key]!.isFolder == folder &&
          _seatIn(mine, base, at) == place) {
        return key;
      }
    }
    return null;
  }

  /// A NEW row of the structure for [member] — wearing what it wears,
  /// standing [after] the key it stands after in its cut — and its key:
  /// the one it names, when no row of the structure is that one (a row a
  /// delete took and its undo brought back), else its own layer's id,
  /// which no other row of the project has.
  ConteKey place(Layer member, {required _After after}) {
    final named = member.conteKey;
    var key = named != null && !entries.containsKey(named)
        ? named
        : ConteKey(member.id.value);
    for (var suffix = 2; entries.containsKey(key); suffix += 1) {
      key = ConteKey('${member.id.value}~$suffix');
    }
    // Its head and its folder are read once its cut is resolved
    // ([resolve]); what it is, now — the next member's place is counted
    // among its kind.
    entries[key] = ConteEntry(
      key: key,
      head: ConteHead.of(member),
      kind: member.kind,
      attachedMode: member.attachedMode,
    );
    final at = switch (after) {
      _AtTheBottom() => 0,
      _AfterKey(:final key) => order.indexOf(key) + 1,
    };
    order.insert(at, key);
    return key;
  }

  /// What [group] changed of [settled] — its rows' heads, and where its
  /// rows stand and are filed — made the structure's (rule 2).
  void takeEditsOf(_GroupOf group, _GroupOf settled) {
    final before = {for (final member in settled.members) member.id: member};
    baseHead = baseHead?.editedBy(settled.base!, group.base!);
    for (final member in group.members) {
      final key = group.keyOf[member.id];
      final was = before[member.id];
      final entry = key == null ? null : entries[key];
      if (entry != null && was != null && was.conteKey == key) {
        entries[key!] = entry.copyWith(head: entry.head.editedBy(was, member));
      }
    }
    final now = group.layout;
    if (_moved(now, settled.layout)) {
      _takeLayout(now);
    }
  }

  /// [now] as the structure's layout: its order for the rows it holds —
  /// each row it does not hold staying over the row it stood over — and
  /// its folder for each of them.
  void _takeLayout(_Layout now) {
    final held = now.order.toSet();
    final merged = [...now.order];
    for (final (index, key) in order.indexed) {
      if (held.contains(key)) {
        continue;
      }
      var at = 0;
      for (var under = index - 1; under >= 0; under -= 1) {
        final there = merged.indexOf(order[under]);
        if (there >= 0) {
          at = there + 1;
          break;
        }
      }
      merged.insert(at, key);
    }
    order
      ..clear()
      ..addAll(merged);
    for (final MapEntry(:key, :value) in now.parents.entries) {
      entries[key] = entries[key]!.copyWith(parent: value);
    }
  }

  /// Rule 3: the rows of the structure no cut's conte holds.
  void forgetWhatNoCutHolds(List<_GroupOf> groups) {
    final held = {for (final group in groups) ...group.keyOf.values};
    _forget([
      for (final key in entries.keys)
        if (!held.contains(key)) key,
    ]);
  }

  /// Rule 3's folders: the 공정 folders of the structure with no row filed
  /// anywhere under them.
  void forgetFoldersFilingNothing() {
    final filing = <ConteKey>{};
    for (final entry in entries.values) {
      if (entry.isFolder) {
        continue;
      }
      for (var up = entry.parent; up != null; up = entries[up]?.parent) {
        if (!filing.add(up)) {
          break;
        }
      }
    }
    _forget([
      for (final entry in entries.values)
        if (entry.isFolder && !filing.contains(entry.key)) entry.key,
    ]);
  }

  void _forget(List<ConteKey> gone) {
    for (final key in gone) {
      final parent = entries.remove(key)!.parent;
      order.remove(key);
      // What it filed stays where it was filed — in the folder over it.
      for (final MapEntry<ConteKey, ConteEntry>(key: child, value: entry)
          in [...entries.entries]) {
        if (entry.parent == key) {
          entries[child] = entry.copyWith(parent: parent);
        }
      }
    }
  }

  /// The structure worked out, as [TrackConte] — [was] itself when nothing
  /// of it moved.
  TrackConte build(TrackConte was) {
    final base = order.indexOf(null);
    final built = TrackConte(
      base: baseHead,
      below: [for (final key in order.sublist(0, base)) entries[key!]!],
      above: [for (final key in order.sublist(base + 1)) entries[key!]!],
    );
    return built == was ? was : built;
  }
}

/// Whether a group's layout [now] moved a row against [was] — the order of
/// the rows both hold, or the folder of one.
bool _moved(_Layout now, _Layout was) {
  final both = now.order.toSet().intersection(was.order.toSet());
  List<ConteKey?> shared(List<ConteKey?> order) => [
    for (final key in order)
      if (both.contains(key)) key,
  ];
  return !_sameOrder(shared(now.order), shared(was.order)) ||
      now.parents.entries.any(
        (entry) =>
            was.parents.containsKey(entry.key) &&
            was.parents[entry.key] != entry.value,
      );
}

/// Where a new row of the structure stands in its order.
sealed class _After {
  const _After();
}

final class _AtTheBottom extends _After {
  const _AtTheBottom();
}

final class _AfterKey extends _After {
  const _AfterKey(this.key);

  /// The key it stands over — null for the conte itself.
  final ConteKey? key;
}

/// What the member at [index] of [members] stands after in its cut: the
/// nearest member under it that has a key, or the conte; or the bottom of
/// the group.
_After _keyBefore(
  List<Layer> members,
  Map<LayerId, ConteKey> keyOf,
  int baseIndex,
  int index,
) {
  for (var under = index - 1; under >= 0; under -= 1) {
    if (under == baseIndex) {
      return const _AfterKey(null);
    }
    if (keyOf[members[under].id] case final key?) {
      return _AfterKey(key);
    }
  }
  return const _AtTheBottom();
}

/// The key of the folder [folderId] names when it is one of [members];
/// null for one outside the group — the folder the conte itself is in.
ConteKey? _keyOfFolder(
  List<Layer> members,
  Map<LayerId, ConteKey> keyOf,
  LayerId? folderId,
) {
  for (final member in members) {
    if (member.id == folderId) {
      return keyOf[member.id];
    }
  }
  return null;
}

/// The SEAT of the member at [index] among the ones [counts] marks, the
/// conte standing at [baseIndex]: +k for the k-th counted one over it, −k
/// for the k-th under it, counted from the conte outward — the seat
/// `conteGroupOf` gives an attach row, which passes over the folders.
int _seatIn(List<bool> counts, int baseIndex, int index) {
  var seat = 0;
  if (index > baseIndex) {
    for (var at = baseIndex + 1; at <= index; at += 1) {
      if (counts[at]) {
        seat += 1;
      }
    }
  } else {
    for (var at = baseIndex - 1; at >= index; at -= 1) {
      if (counts[at]) {
        seat -= 1;
      }
    }
  }
  return seat;
}

bool _sameOrder(List<ConteKey?> a, List<ConteKey?> b) =>
    a.length == b.length &&
    a.indexed.every((entry) => entry.$2 == b[entry.$1]);

/// [group]'s cut with its conte laid from [structure] (rule 4) — the cut
/// itself when it wears it already.
///
/// The group is laid as ONE RUN where its conte stands, every other row of
/// the cut keeping its order around it: a row that stood inside the group
/// steps out on its side of the conte — nothing stands inside an attach
/// group (R26 #36, `newRowPlacement`).
///
/// A member whose row the structure forgot is a 공정 folder left filing
/// nothing (rule 3): the one the structure gave the cut goes, and one of
/// the cut's own stands over the group, out of it — an empty folder is not
/// one of its rows.
Cut _laidCut(_GroupOf group, _Structure structure) {
  final cut = group.cut;
  final base = group.base!;
  final layers = cut.layers;
  final mine = {
    for (final MapEntry(key: id, value: key) in group.keyOf.entries)
      if (structure.entries.containsKey(key)) key: id,
  };
  final byId = {for (final member in group.members) member.id: member};
  final others = [
    for (final layer in layers)
      if (!byId.containsKey(layer.id)) layer,
  ];
  final outside = {for (final layer in others) layer.id};
  final idOf = {
    for (final key in structure.order.nonNulls)
      key: mine[key] ?? _freeFillId(key, cut.id, outside),
  };
  final baseIndex = structure.order.indexOf(null);
  final run = [
    for (final (index, key) in structure.order.indexed)
      if (key == null)
        structure.baseHead!.wornBy(base)
      else
        _worn(
          byId[mine[key]] ??
              _fillFor(structure.entries[key]!, idOf[key]!, base),
          structure.entries[key]!,
          (
            base: base,
            side: index < baseIndex
                ? AttachedPlacement.below
                : AttachedPlacement.above,
            folderId: switch (structure.entries[key]!.parent) {
              final parent? => idOf[parent],
              null => base.folderId,
            },
          ),
        ),
  ];
  final under = layers
      .take(layers.indexOf(base))
      .where((layer) => !byId.containsKey(layer.id))
      .length;
  final laid = [
    ...others.take(under),
    ...run,
    ..._foldersSteppingOut(group, mine, base),
    ...others.skip(under),
  ];
  final same =
      laid.length == layers.length &&
      laid.indexed.every((entry) => identical(entry.$2, layers[entry.$1]));
  return same ? cut : cut.copyWith(layers: laid);
}

/// [group]'s own folders whose rows the structure forgot, stepping out of
/// the group — each still filed in another of them, or else where the
/// conte is.
List<Layer> _foldersSteppingOut(
  _GroupOf group,
  Map<ConteKey, LayerId> mine,
  Layer base,
) {
  final kept = mine.values.toSet();
  final out = [
    for (final member in group.members)
      if (!identical(member, base) &&
          !kept.contains(member.id) &&
          !isConteFill(member))
        member,
  ];
  final outIds = {for (final member in out) member.id};
  return [
    for (final member in out)
      if (outIds.contains(member.folderId) || member.folderId == base.folderId)
        member
      else
        member.copyWith(folderId: base.folderId),
  ];
}

/// [conteFillId], or — where a row of [cutId] outside its conte has that
/// id already — the first of it with a turn after it that none has.
LayerId _freeFillId(ConteKey key, CutId cutId, Set<LayerId> taken) {
  final id = conteFillId(key, cutId);
  if (!taken.contains(id)) {
    return id;
  }
  for (var turn = 2; ; turn += 1) {
    final next = LayerId('${id.value}~$turn');
    if (!taken.contains(next)) {
      return next;
    }
  }
}

/// Where a row of the structure stands in a cut's conte: riding [base] on
/// its [side] of it, filed in [folderId].
typedef _Stand = ({Layer base, AttachedPlacement side, LayerId? folderId});

/// [row] standing as [entry]'s row of a cut's conte, where [stand] puts it:
/// its key, its head, its side of the conte and its folder — [row] itself
/// when it stands so already.
Layer _worn(Layer row, ConteEntry entry, _Stand stand) {
  final (:base, :side, :folderId) = stand;
  final rides = !entry.isFolder;
  final stands =
      row.conteKey == entry.key &&
      row.folderId == folderId &&
      (!rides ||
          (row.attachedToLayerId == base.id && row.attachedPlacement == side));
  final placed = stands
      ? row
      : row.copyWith(
          conteKey: entry.key,
          folderId: folderId,
          attachedToLayerId: rides ? base.id : row.attachedToLayerId,
          attachedPlacement: rides ? side : row.attachedPlacement,
        );
  return entry.head.wornBy(placed);
}

/// The row [entry] gives a cut whose conte has none of it, as [id]:
/// holding nothing, born as the entry says ([ConteEntry.kind],
/// [ConteEntry.attachedMode]) — and off the timesheet, as the ＋ makes an
/// attach row (which rows a cut's sheet prints is the cut's).
Layer _fillFor(ConteEntry entry, LayerId id, Layer base) => Layer(
  id: id,
  name: entry.head.name,
  frames: const [],
  kind: entry.kind,
  onTimesheet: false,
  attachedToLayerId: entry.isFolder ? null : base.id,
  attachedMode: entry.attachedMode,
  folderId: base.folderId,
  conteKey: entry.key,
);
