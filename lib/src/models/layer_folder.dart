import 'layer.dart';
import 'layer_blend_mode.dart';
import 'layer_id.dart';
import 'layer_kind.dart';

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
      if (layer.id == id && layerKindGroupsLayers(layer.kind)) {
        return layer;
      }
    }
    return null;
  }

  /// Every folder row in the stack, bottom → top.
  Iterable<Layer> get folderLayers =>
      where((layer) => layerKindGroupsLayers(layer.kind));

  /// [folderId]'s chain up to the top level, NEAREST FIRST. Safe on
  /// malformed stacks: stops if a parent is missing or a cycle appears.
  List<Layer> ancestryOf(LayerId? folderId) {
    final chain = <Layer>[];
    final seen = <LayerId>{};
    var current = folderById(folderId);
    while (current != null && seen.add(current.id)) {
      chain.add(current);
      current = folderById(current.folderId);
    }
    return chain;
  }

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
      if (layerKindGroupsLayers(layer.kind)) {
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
  List<Layer> ancestryOf(LayerId? folderId) {
    final cached = _ancestry[folderId];
    if (cached != null) {
      return cached;
    }
    final chain = <Layer>[];
    final seen = <LayerId>{};
    var current = folderById(folderId);
    while (current != null && seen.add(current.id)) {
      chain.add(current);
      current = folderById(current.folderId);
    }
    _ancestry[folderId] = chain;
    return chain;
  }

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

/// Validates the folder structure over a cut's stack order: every
/// [Layer.folderId] names a real folder row, each folder's subtree is one
/// contiguous run with the folder row directly above it, and the parent
/// chain is acyclic. Returns a human-readable problem description, or null
/// when the structure is sound.
String? folderStructureProblem(List<Layer> layers) {
  final folderIds = <LayerId>{};
  for (final folder in layers.folderLayers) {
    if (!folderIds.add(folder.id)) {
      return 'Duplicate folder row ${folder.id}.';
    }
  }
  for (final folder in layers.folderLayers) {
    final seen = <LayerId>{folder.id};
    var parent = layers.folderById(folder.folderId);
    while (parent != null) {
      if (!seen.add(parent.id)) {
        return 'Folder ${folder.id} has a cyclic parent chain.';
      }
      parent = layers.folderById(parent.folderId);
    }
    if (folder.folderId != null && layers.folderById(folder.folderId) == null) {
      return 'Folder ${folder.id} has a missing parent ${folder.folderId}.';
    }
  }
  for (final layer in layers) {
    if (layer.folderId != null && layers.folderById(layer.folderId) == null) {
      return 'Layer ${layer.id} references missing folder ${layer.folderId}.';
    }
  }
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
  // A folder holding attach rows is either the group's shared OUTER
  // folder (the base lives in it too) or an ATTACH-ORGANIZER
  // ([연출]/[작감]…) holding NOTHING BUT one base's attaches. Anything
  // else — attaches of two bases, an attach mixed with unrelated rows, a
  // folder nested inside an organizer — breaks the group-span derivation
  // and would split the attach group across a folder boundary. (This is
  // also what keeps organizers FLAT: a nested folder is a non-attach
  // member.)
  for (final folder in layers.folderLayers) {
    final members = layers.directMembersOf(folder.id);
    final attachBases = <LayerId>{
      for (final member in members)
        if (member.attachedToLayerId != null) member.attachedToLayerId!,
    };
    if (attachBases.isEmpty) {
      continue;
    }
    final holdsBase = members.any((member) => attachBases.contains(member.id));
    final pureOrganizer =
        attachBases.length == 1 &&
        members.every((member) => member.attachedToLayerId != null);
    if (!holdsBase && !pureOrganizer) {
      return 'Folder ${folder.id} mixes attach rows with other rows — it '
          'must be the group\'s shared folder or a flat attach organizer.';
    }
  }
  return null;
}
