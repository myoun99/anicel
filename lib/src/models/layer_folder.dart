import 'layer.dart';
import 'layer_blend_mode.dart';
import 'layer_id.dart';
import 'layer_kind.dart';

/// The folder chain above [folderId], NEAREST FIRST, resolved through
/// [folderById].
///
/// ⛔THE `seen` SET IS NOT DEFENSIVE PROGRAMMING. A folder chain that
/// loops back on itself — a bad file, a half-applied move — would spin
/// here forever, and this walk runs inside the composite plan's per-layer
/// resolve. The plain queries and the cached index both walked it; a copy
/// that lost the set is a HANG, not a wrong answer.
List<Layer> folderChainAbove(
  LayerId? folderId,
  Layer? Function(LayerId? id) folderById,
) {
  final chain = <Layer>[];
  final seen = <LayerId>{};
  var current = folderById(folderId);
  while (current != null && seen.add(current.id)) {
    chain.add(current);
    current = folderById(current.folderId);
  }
  return chain;
}

/// Folder queries over a cut's flat layer stack.
///
/// A folder is a LAYER ([LayerKind.folder]) — "그림만 못 그릴 뿐인 레이어"
/// (user, 2026-07-23). It carries the eye, static opacity, blend mode and
/// FX lanes every layer carries; what it does not carry is cels. Membership
/// is the members' [Layer.folderId] pointer into the folder layer's id, so
/// the stack list keeps being the single truth of render/timeline order and
/// nesting never has to be re-derived from order alone.
///
/// Structural invariants (kept by the commands, checked by
/// [folderStructureProblem]):
/// - A folder's members occupy a CONTIGUOUS run of the stack and the folder
///   row sits DIRECTLY ABOVE it (at `lastMemberIndex + 1`) — so a
///   bottom-to-top walk has already seen every member when it reaches the
///   folder, which is exactly what the group buffer needs.
/// - Attach groups never split across a folder boundary.
/// - Nesting is allowed; cycles are not.
extension LayerFolderQueries on List<Layer> {
  /// The FOLDER layer with [id], or null (also null when [id] names a
  /// layer that is not a folder — a stale pointer reads as top level).
  Layer? folderById(LayerId? id) {
    if (id == null) {
      return null;
    }
    for (final layer in this) {
      if (layer.id == id && layer.kind.groupsLayers) {
        return layer;
      }
    }
    return null;
  }

  /// Every folder row in the stack, bottom → top.
  Iterable<Layer> get folderLayers =>
      where((layer) => layer.kind.groupsLayers);

  /// [folderId]'s chain up to the top level, NEAREST FIRST. Safe on
  /// malformed stacks: stops if a parent is missing or a cycle appears.
  List<Layer> ancestryOf(LayerId? folderId) =>
      folderChainAbove(folderId, folderById);

  /// Whether [folderId] is [ancestorId] or sits anywhere under it.
  bool isInsideFolder(LayerId? folderId, LayerId ancestorId) =>
      ancestryOf(folderId).any((folder) => folder.id == ancestorId);

  /// The rows anywhere under [folderId] (the SUBTREE, folder rows
  /// included), in stack order.
  List<Layer> subtreeMembersOf(LayerId folderId) => [
    for (final layer in this)
      if (isInsideFolder(layer.folderId, folderId)) layer,
  ];

  /// The rows pointing DIRECTLY at [folderId], in stack order.
  List<Layer> directMembersOf(LayerId folderId) => [
    for (final layer in this)
      if (layer.folderId == folderId) layer,
  ];

  /// The folders left EMPTY by removing [removed], INNERMOST FIRST.
  ///
  /// A nest empties from the inside out: the folder that held the removed
  /// row goes, and then ITS folder if that was all it held, and so on. It
  /// is a walk rather than a parent lookup because a parent lookup is a
  /// one-level answer, and one level was exactly right only while folders
  /// could not nest (유저 2026-08-29 lifted that — see
  /// [attachOrganizerBaseOf]).
  ///
  /// ⛔A folder that was ALREADY empty before the removal is not swept:
  /// this answers "what did this delete empty", not "what is empty".
  ///
  /// [canRemove] is the caller's veto, and a vetoed folder BLOCKS its
  /// ancestors — it is still there, so its parent is not empty either.
  /// The attach path uses it for linked folder rows, whose membership in
  /// this cut says nothing about a diverged counterpart's.
  List<Layer> foldersEmptiedByRemoving(
    Set<LayerId> removed, {
    bool Function(Layer folder)? canRemove,
  }) {
    final gone = {...removed};
    final emptied = <Layer>[];
    var found = true;
    while (found) {
      found = false;
      for (final folder in folderLayers) {
        if (gone.contains(folder.id) || (canRemove?.call(folder) == false)) {
          continue;
        }
        final members = directMembersOf(folder.id);
        if (members.isEmpty || members.any((m) => !gone.contains(m.id))) {
          continue;
        }
        gone.add(folder.id);
        emptied.add(folder);
        found = true;
      }
    }
    return emptied;
  }

  /// Whether every folder in the chain is visible (a hidden ancestor hides
  /// the whole subtree).
  bool subtreeVisible(LayerId? folderId) {
    for (final folder in ancestryOf(folderId)) {
      if (!folder.isVisible) {
        return false;
      }
    }
    return true;
  }

  /// 🚨WHETHER [layer] IS SHOWN AT ALL — its own eye AND every folder it
  /// lives in. This is the question, and callers must ask it here.
  ///
  /// [subtreeVisible] answers only half of it (the ancestors), which is why
  /// it sat in this file with zero callers while seven places re-derived the
  /// other half as a bare `layer.isVisible` and got the folders wrong:
  /// artwork went on being drawn into a hidden folder, onion ghosts kept
  /// showing, and cel export kept writing files for rows the user had
  /// switched off. A predicate nobody can reach is not a law.
  bool rowVisible(Layer layer) =>
      layer.isVisible && subtreeVisible(layer.folderId);

  /// Whether any ancestor is collapsed (the row hides in the list).
  bool subtreeCollapsed(LayerId? folderId) {
    for (final folder in ancestryOf(folderId)) {
      if (folder.collapsed) {
        return true;
      }
    }
    return false;
  }
}

/// The same folder questions, asked MANY times over one unchanging stack.
///
/// [LayerFolderQueries] is written for a one-off ask and pays for it every
/// time: `folderById` is a linear scan, so `ancestryOf` allocates a list and
/// a set and scans per hop, and `subtreeMembersOf` runs `isInsideFolder`
/// once per layer — a full walk each. Building the timeline's row model
/// asked all three inside a per-layer loop, which made it O(n²·depth) with
/// two allocations per probe, and it ran in `build()` with no memo while
/// every session notify rebuilt the chrome.
///
/// Same answers, one pass: the folder lookup is a map, each ancestry chain
/// is computed once and shared, and every subtree list is filled by a
/// single walk over the stack. Build one per row-model pass and throw it
/// away — it is a cache of a value, so it must not outlive the stack it
/// indexed.
class LayerFolderIndex {
  LayerFolderIndex(this._layers) {
    for (final layer in _layers) {
      if (layer.kind.groupsLayers) {
        // First wins, matching folderById's scan order (a stack with
        // duplicate folder ids is already rejected by
        // folderStructureProblem).
        _folderById.putIfAbsent(layer.id, () => layer);
      }
    }
  }

  final List<Layer> _layers;
  final Map<LayerId, Layer> _folderById = <LayerId, Layer>{};
  final Map<LayerId?, List<Layer>> _ancestry = <LayerId?, List<Layer>>{};
  Map<LayerId, List<Layer>>? _subtrees;

  /// See [LayerFolderQueries.folderById].
  Layer? folderById(LayerId? id) => id == null ? null : _folderById[id];

  /// See [LayerFolderQueries.ancestryOf]. The returned list is SHARED and
  /// must not be mutated.
  List<Layer> ancestryOf(LayerId? folderId) =>
      _ancestry[folderId] ??= folderChainAbove(folderId, folderById);

  /// How deep [folderId] sits — the chain length, without building one.
  int depthOf(LayerId? folderId) => ancestryOf(folderId).length;

  /// See [LayerFolderQueries.subtreeCollapsed].
  bool subtreeCollapsed(LayerId? folderId) {
    for (final folder in ancestryOf(folderId)) {
      if (folder.collapsed) {
        return true;
      }
    }
    return false;
  }

  /// See [LayerFolderQueries.subtreeVisible].
  bool subtreeVisible(LayerId? folderId) {
    for (final folder in ancestryOf(folderId)) {
      if (!folder.isVisible) {
        return false;
      }
    }
    return true;
  }

  /// See [LayerFolderQueries.rowVisible].
  bool rowVisible(Layer layer) =>
      layer.isVisible && subtreeVisible(layer.folderId);

  /// See [LayerFolderQueries.subtreeMembersOf]. Every folder's list is
  /// filled by ONE walk of the stack, the first time any of them is asked
  /// for; the lists are SHARED and must not be mutated.
  List<Layer> subtreeMembersOf(LayerId folderId) {
    final subtrees = _subtrees ??= () {
      final built = <LayerId, List<Layer>>{};
      for (final layer in _layers) {
        for (final folder in ancestryOf(layer.folderId)) {
          (built[folder.id] ??= <Layer>[]).add(layer);
        }
      }
      return built;
    }();
    return subtrees[folderId] ?? const <Layer>[];
  }
}

/// A fresh folder row. Folders hold no cels, so the timeline fields stay
/// empty; everything else is ordinary layer state.
Layer createFolderLayer({
  required LayerId id,
  required String name,
  LayerId? parentId,
}) {
  return Layer(
    id: id,
    name: name,
    frames: const [],
    timeline: const {},
    kind: LayerKind.folder,
    // PASS THROUGH by default, like Photoshop and CSP: a folder you made
    // to tidy the stack must not change one pixel. Buffering is what you
    // opt into by giving the folder a real mode.
    blendMode: LayerBlendMode.passThrough,
    // Folders print nothing on the sheet — the toggle would be a dead
    // control on the row.
    onTimesheet: false,
    folderId: parentId,
  );
}

/// Two folder rows with one id.
String? _duplicateFolderProblem(List<Layer> layers) {
  final folderIds = <LayerId>{};
  for (final folder in layers.folderLayers) {
    if (!folderIds.add(folder.id)) {
      return 'Duplicate folder row ${folder.id}.';
    }
  }
  return null;
}

/// A folder whose parent chain loops.
String? _parentChainProblem(List<Layer> layers) {
  for (final folder in layers.folderLayers) {
    final seen = <LayerId>{folder.id};
    var parent = layers.folderById(folder.folderId);
    while (parent != null) {
      if (!seen.add(parent.id)) {
        return 'Folder ${folder.id} has a cyclic parent chain.';
      }
      parent = layers.folderById(parent.folderId);
    }
  }
  return null;
}

/// A layer whose folder is not there — a folder row included, since it is
/// a layer row too ([folderLayers] filters this same list).
String? _missingFolderProblem(List<Layer> layers) {
  for (final layer in layers) {
    if (layer.folderId != null && layers.folderById(layer.folderId) == null) {
      return 'Layer ${layer.id} references missing folder ${layer.folderId}.';
    }
  }
  return null;
}

/// A folder whose subtree is not one contiguous run with the folder row
/// directly above it.
String? _contiguityProblem(List<Layer> layers) {
  for (final folder in layers.folderLayers) {
    var runStart = -1;
    var runEnd = -1;
    for (var index = 0; index < layers.length; index += 1) {
      if (!layers.isInsideFolder(layers[index].folderId, folder.id)) {
        continue;
      }
      if (runStart == -1) {
        runStart = index;
      } else if (index != runEnd + 1) {
        return 'Folder ${folder.id} members are not contiguous in the '
            'layer stack.';
      }
      runEnd = index;
    }
    final folderIndex = layers.indexWhere((layer) => layer.id == folder.id);
    if (runStart != -1 && folderIndex != runEnd + 1) {
      return 'Folder ${folder.id} does not sit directly above its members.';
    }
  }
  return null;
}

/// A folder that mixes attach rows with rows they do not belong to.
String? _attachMixProblem(List<Layer> layers) {
  // A folder holding attach rows is either the group's shared OUTER
  // folder (the base lives in it too) or an ATTACH-ORGANIZER
  // ([연출]/[작감]…) holding NOTHING BUT one base's attaches. Anything
  // else — attaches of two bases, an attach mixed with unrelated rows —
  // breaks the group-span derivation and would split the attach group
  // across a folder boundary. 🪦A folder nested inside an organizer used
  // to be on that list, which is what kept organizers FLAT; 유저
  // 2026-08-29 lifted it and the walk below descends instead.
  for (final folder in layers.folderLayers) {
    // 🚨THE SUBTREE'S LEAVES. A nested folder is structure, not a member with
    // an opinion about whose attach this is — reading direct members made one
    // nested folder turn an organizer «impure», which was the whole ban
    // (유저 2026-08-29 lifted it: nothing about drawing required it, and
    // PLAIN folders already nest).
    final leaves = [
      for (final layer in layers.subtreeMembersOf(folder.id))
        if (!layer.kind.groupsLayers) layer,
    ];
    final attachBases = <LayerId>{
      for (final leaf in leaves)
        if (leaf.attachedToLayerId != null) leaf.attachedToLayerId!,
    };
    if (attachBases.isEmpty) {
      continue;
    }
    final holdsBase = leaves.any((leaf) => attachBases.contains(leaf.id));
    // ⛔ASKED, not re-derived. `attachOrganizerBaseOf` already answers
    // 「is this one base's organizer」 and this used to compute it again —
    // two spellings of one question, which is how they drift apart.
    final organizer = attachOrganizerBaseOf(folder, layers) != null;
    if (!holdsBase && !organizer) {
      return 'Folder ${folder.id} mixes attach rows with other rows — it '
          'must be the group\'s shared folder or an attach organizer.';
    }
  }
  return null;
}

/// Validates the folder structure over a cut's stack order: every
/// [Layer.folderId] names a real folder row, each folder's subtree is one
/// contiguous run with the folder row directly above it, and the parent
/// chain is acyclic. Returns a human-readable problem description, or null
/// when the structure is sound.
String? folderStructureProblem(List<Layer> layers) {
  return _duplicateFolderProblem(layers) ??
      _parentChainProblem(layers) ??
      _missingFolderProblem(layers) ??
      _contiguityProblem(layers) ??
      _attachMixProblem(layers);
}
/// The base whose attaches [folder] ORGANIZES, or null when [folder] is
/// not an attach-organizer folder.
///
/// An attach-organizer folder is the 공정 folder inside an attach group
/// ([연출]/[작감]…): a folder row whose SUBTREE leaves are all attach rows
/// of ONE base. The attach relation stays direct to the base — the folder
/// only organizes and display-controls — so the group's resolution never
/// chains.
///
/// 🪦It used to read DIRECT members and organizers were deliberately FLAT
/// (no folder inside one; the brush groups' precedent), with the commands
/// refusing to create nesting there. 유저 2026-08-29 lifted the ban —
/// 「어태치 폴더 중첩도 허용하는 방향으로 가자」 — so the walk descends and
/// the commands create what it can now read.
///
/// R9: what "display-controls" covers narrowed to the EYE, the static
/// opacity, the BLEND and the fold. It used to include FX, which was wrong
/// for the same reason an attach ROW has no fx of its own: this folder
/// follows its base ("주인 레이어를 따라가야 하니까", user 2026-07-31), so a
/// transform or effect chain here would be a second, competing answer to
/// what the group looks like. See [attachRowWearsBaseComposite].
///
/// 🚨★★★THE WHOLE SUBTREE, NOT THE DIRECT MEMBERS. 유저 2026-08-29 asked for
/// nested attach folders, and this loop was the ban: a folder member has no
/// `attachedToLayerId`, so one nested folder made the organizer «impure» and
/// the model rejected it. Nothing about drawing required that — a folder
/// composites into one offscreen either way, and PLAIN folders already nest.
///
/// ⇒ Walk the subtree and read the LEAVES. A nested folder is not an answer
/// to 「whose attach is this」; the rows inside it are.
LayerId? attachOrganizerBaseOf(Layer folder, List<Layer> layers) {
  if (!folder.kind.groupsLayers) {
    return null;
  }
  LayerId? baseId;
  var sawLeaf = false;
  for (final layer in layers.subtreeMembersOf(folder.id)) {
    // The folders on the way down are structure, not members with an
    // opinion — the leaves under them carry the answer.
    if (layer.kind.groupsLayers) {
      continue;
    }
    final memberBase = layer.attachedToLayerId;
    if (memberBase == null || (baseId != null && memberBase != baseId)) {
      return null;
    }
    baseId = memberBase;
    sawLeaf = true;
  }
  // ⛔An empty folder (or one holding nothing but folders) is not an
  // organizer: there is no attach in it to name a base.
  return sawLeaf ? baseId : null;
}

/// The base whose attach GROUP [layer] is a row of — the row the group's fold
/// takes off the screen and whose indent hangs off that base: an attach row
/// names its base directly, an organizer folder (a nested one included)
/// names it through its leaves. Null for a row outside every attach group.
///
/// 🚨F-81: the display rows asked this inline, and the group fold asked a
/// narrower question of its own — attach rows alone — so folding while
/// standing on the organizer folder left you on a row that was gone
/// (유저 2026-09-11: 「어태치폴더에 서있는 채로 기준레이어의 접기버튼 누르면
/// 폴더에 서있는채임」).
LayerId? attachGroupBaseOf(Layer layer, List<Layer> layers) =>
    layer.attachedToLayerId ?? attachOrganizerBaseOf(layer, layers);

/// How many attach FOLDERS hold [layer] — how deep it sits inside its group's
/// organizers: 0 for an organizer at the group's top and for an attach row
/// outside every organizer.
int attachFolderLevelsAbove(Layer layer, List<Layer> layers) => [
  for (final folder in layers.ancestryOf(layer.folderId))
    if (attachOrganizerBaseOf(folder, layers) != null) folder,
].length;
