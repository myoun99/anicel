import '../canvas/interactive_brush_edit_canvas_view.dart' show StrokeLander;

/// Where the canvas leaves the one verb a save needs: land the stroke the
/// pen is in the middle of.
///
/// 🚨★★★**A SIBLING, NOT A NAME ON THE SESSION.** `SessionInternals` only
/// shrinks (`the_session_collaborators_are_libraries_test`), and its rule
/// says what to do instead: 「a host name a collaborator needs is either a
/// ROLE, a SIBLING it takes by constructor, or code that moves INTO the
/// collaborator」. This is the sibling — `ProjectFileDoor` takes it, the
/// canvas fills it in, and nothing else has to know either of them exists.
///
/// 🚨★★★**WHY A SAVE WANTS IT AT ALL.** The store's save snapshot records
/// each cel's edit tick, and `BrushFrameStore.adoptSavedFile` refuses to
/// mark clean anything whose tick moved past it — so a stroke that lands
/// after the snapshot is correctly kept dirty for the NEXT save, and
/// correctly missing from the file the user just asked for. Pressing Ctrl+S
/// with the pen down did exactly that. 유저 2026-09-10: 「그냥 스트로크
/// 커밋시키고 저장로직 발동시키면 되는거아닌가?」
///
/// ⚠️Null whenever no canvas is mounted, which a headless save, a test, and
/// the moments between layer switches all really are. [landNow] answers
/// false there rather than making every caller ask first.
class LiveStrokeLanding {
  /// Set by the mounted canvas view and cleared when it goes — see
  /// [InteractiveBrushEditCanvasView.onStrokeLanderChanged], which explains
  /// why clearing it is not optional.
  StrokeLander? lander;

  /// Lands the stroke in flight, if any. Answers whether anything landed.
  bool landNow() => lander?.call() ?? false;
}
