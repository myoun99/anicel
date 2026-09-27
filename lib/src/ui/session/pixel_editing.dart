import '../../services/brush_frame_editing_coordinator.dart';

/// Where the canvas leaves the live editing coordinator, and where the
/// pixel verbs pick it up.
///
/// 🚨★★★A SIBLING, NOT A NAME ON THE SESSION — what [LiveStrokeLanding]
/// already is, and filled in from the same build. It was the session's
/// field and a member of the interface the audit counted down to nothing
/// (the nineteenth family, 2026-09-28): 「a host name a collaborator needs is
/// either a ROLE, a SIBLING it takes by constructor, or code that moves INTO
/// the collaborator」. `CellVerbs` takes it, the canvas fills it in.
///
/// 🚨Null before the canvas has built one — a fresh project, a gap parking,
/// a test that mounts the timeline alone. Every pixel verb asks, and the
/// buttons dim rather than the press throwing.
class PixelEditing {
  /// The live editing coordinator, published by the canvas host.
  BrushFrameEditingCoordinator? coordinator;
}
