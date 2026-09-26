import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';

/// A drawing id no other in this run has — for every project open in it
/// (I-7), and for a project being MADE before any session holds it (a
/// .tvpp becoming one: its session is born after its drawings are named).
///
/// ⚠️THE COUNT IS THE IDENTITY; the wall clock in here is decoration. Its
/// resolution on Windows is coarser than a tight mint loop, so two ids made
/// in the same tick differ only by the count — and equal frame ids are ONE
/// drawing. So nothing formats an id without advancing the count: a
/// formatter that read it without advancing (`nextFrameId`, until
/// 2026-09-26) left every caller to remember the increment first, and the
/// ones that forgot were an import's whole layer coming out as one drawing.
///
/// ONE count for the process rather than one per session: a session born
/// for a project that was named before it existed goes on counting past
/// every drawing already in it, instead of starting again from one.
FrameId mintFrameId(LayerId layerId) =>
    FrameId('ui-frame-${layerId.value}-${_nextInRun()}');

/// A cut id no other in this run has, from the same count.
///
/// 🚨AN ID FREE IN THE PROJECT IS NOT FREE IN THE SESSION. A cut that is
/// undone or deleted gives its id up while the session still holds what
/// was written under it — its envelope's and its timesheet's handwriting —
/// for the redo that hands the id back. A new cut that took the first
/// number the project had free took that handwriting too (card
/// `undone-paste-reuses-ids`, 2026-09-26). The same lesson made the
/// drawings' ids the run's ([mintFrameId]) and the conte's handwriting ids
/// (`StoryboardCursor.conteInkIdFor`).
CutId mintCutId() => CutId('cut-${_nextInRun()}');

/// The count advanced, as the tail of an id: the wall clock, then the
/// count ([mintFrameId]'s warning says which of the two is the identity).
String _nextInRun() {
  _minted += 1;
  return '${DateTime.now().microsecondsSinceEpoch}-$_minted';
}

int _minted = 0;
