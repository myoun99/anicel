/// One in-flight drag, as its own object — begun by CONSTRUCTING it, driven
/// by [update], closed by exactly one of [commit] or [cancel], then discarded.
///
/// This is the shape mature editors converge on (pro-tool survey,
/// 2026-08-16): OpenToonz's EditTool news a DragTool per gesture and deletes
/// it at button-up; Blender allocates a TransInfo per operator invocation and
/// frees it at confirm. The app-lifetime session keeps at most "which drag is
/// live" — one nullable field — while the gesture's own state lives HERE and
/// dies with the gesture. Before this type, every family kept its mid-drag
/// fields on the session forever, which is how 86 drag fields accumulated on
/// one class.
///
/// The laws a session subtype signs up for:
///
/// * The constructor captures the BEFORE state. A begin that must refuse
///   (nothing under the grip, wrong row) is a factory returning null — the
///   session's begin verb maps that to false, and no object means no drag.
/// * [update] recomputes the AFTER state from cumulative input and publishes
///   a preview. The preview channel is DISPLAY: shared, clearable by any
///   consumer, never read back.
/// * [commit] lands AT MOST ONE undo step, built from the object's OWN
///   stored after-state — never from a preview channel (the invariant the
///   exposure-edge family documents, which movie-end and cut-move violated
///   until 2026-08-16).
/// * [cancel] drops the preview and touches no history. Both closers leave
///   the preview channel null; the session forgets the object right after
///   calling either, so neither is ever called twice.
abstract class EditorDragSession {
  /// Recomputes the after-state for the drag's cumulative delta and
  /// publishes the preview. A no-op when the delta lands on "no change".
  void update(int cumulativeDelta);

  /// Lands the drag's one undo step from stored after-state, or nothing
  /// when the drag never left "no change". Clears the preview either way.
  void commit();

  /// Drops the preview; history is untouched.
  void cancel();
}
