import '../active_cut_controllers.dart';
import '../session_roles.dart';

/// What an in-flight EDGE drag is handed: the session roles it needs for the
/// whole of its life, as ONE argument.
///
/// Not tidiness. `ExposureEdgeDrag` and `CutTrimDrag` have four factories
/// and four constructors between them, so spelling the handles out is eight
/// copies of the same wiring — the shape the clone gate measures (it caught
/// exactly that on the frame-range move, 2026-09-10).
///
/// ⛔The BEGIN-only roles do not travel here: the folders (does this row own
/// its timing), the live selection and the span rows (which blocks the bulk
/// covers) are asked once, before the object exists. They stay on
/// `EdgeDragVerbs` and are passed to the factories that ask them, so a drag
/// in flight cannot re-read a map of the project that has moved under it.
typedef EdgeDragRoles = ({
  ProjectAccess project,
  ChangeSink changes,
  ActiveCutControllers controllers,
  SessionInternals internals,
});
