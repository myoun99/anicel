import 'package:flutter/foundation.dart' show ChangeNotifier;

/// Tells of one thing, and holds nothing: what listens to it asks the
/// owner what changed.
///
/// 🚨Written once (a-view-change-rebuilds-the-whole-canvas-panel,
/// 2026-11-20). It was written out by hand four times before — the engine's
/// refusals (`_Told`), the text tool's cross (`_Telling`), the letter faces
/// (`_FaceChanges`) and the picture store's news (`_News`) — and the canvas
/// panel's view was the fifth.
final class Telling extends ChangeNotifier {
  void tell() => notifyListeners();
}
