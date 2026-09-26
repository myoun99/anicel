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
FrameId mintFrameId(LayerId layerId) {
  _minted += 1;
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return FrameId('ui-frame-${layerId.value}-$timestamp-$_minted');
}

int _minted = 0;
