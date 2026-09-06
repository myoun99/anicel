import '../../models/cut_id.dart';
import 'session_roles.dart';

/// The envelope an edit against the ACTIVE cut runs inside.
///
/// One method today, and it is deliberately named for the QUIET half rather
/// than taking a `refresh: bool`: a per-layer PROPERTY write and a
/// structural cut edit are two laws, and a flag answering both is how they
/// drift into one.
class ActiveCutEdits {
  ActiveCutEdits({required TimelineAccess timeline, required ChangeSink changes})
    : _timeline = timeline,
      _changes = changes;

  final TimelineAccess _timeline;
  final ChangeSink _changes;

  /// Runs [command] against the active cut, then does a BARE notify.
  ///
  /// Nothing happens without an active cut. The bare notify is the law,
  /// stated where the fx switches state it: "a bare notify, like every
  /// sibling row write (opacity, blend, the transform track, the effect
  /// chain): a switch flip is not a structural cut edit, and refreshing as
  /// one threw away the frame-range selection the user keeps while A/B-ing
  /// the switch."
  void onActiveCutQuietly(void Function(CutId cutId) command) {
    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    command(cutId);
    _changes.notifyChanged();
  }
}
