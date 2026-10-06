import 'package:flutter/foundation.dart';

import '../canvas/text/cel_text_tool.dart';

/// THE TEXT TOOL'S CHANNEL (R9-rest): how the rest of the app reaches the
/// text the canvas is holding — the tool settings, which show and change
/// it (유저 2026-10-02: 「선택해서 그 상태에서 도구설정에서 폰트바꾸면 해당
/// 텍스트박스 설정 자동으로 바꿈」), the keys that let go of it or delete
/// it, and whoever has to see it landed before they act: a step of history
/// about to be taken, a project going off screen, a save.
///
/// The app's, like the selection's channel (`CanvasSelectionCommands`):
/// the main canvas binds the hand it holds texts with while it is mounted,
/// and with nothing bound every question answers 「nothing」 and every verb
/// does nothing.
class CelTextCommands extends ChangeNotifier {
  CelTextTool? _tool;

  /// The hand of the canvas on screen — null with none bound.
  CelTextTool? get tool => _tool;

  /// Binds [tool]: its changes are this channel's from now on.
  void bind(CelTextTool tool) {
    if (identical(_tool, tool)) {
      return;
    }
    _tool?.removeListener(notifyListeners);
    _tool = tool..addListener(notifyListeners);
    notifyListeners();
  }

  /// Lets go of [tool] — a no-op for one that is not bound, so a canvas
  /// going away cannot unbind the one that replaced it.
  void unbind(CelTextTool tool) {
    if (!identical(_tool, tool)) {
      return;
    }
    tool.removeListener(notifyListeners);
    _tool = null;
    notifyListeners();
  }

  /// Whether a text is in hand.
  bool get holdsText => _tool?.session != null;

  /// Whether the text in hand is held by its letters — the keyboard is
  /// then typing into it.
  bool get typing => _tool?.letters != null;

  /// Whether anything is in hand or still owed a landing.
  bool get holdsAnything => _tool?.holdsAnything ?? false;

  /// Lands what is in hand and lets go of it — Esc with a text held by its
  /// box, and what a project going off screen asks.
  void confirm() => _tool?.confirm();

  /// Lands everything as it is shown, now — what a step of history asks
  /// before it is taken.
  void landNow() => _tool?.landNow();

  /// Takes the text in hand off its cel.
  void deleteText() => _tool?.deleteText();

  /// Whether the letters being typed have a step to take back — and to put
  /// back ([CelTextEditingController]).
  bool get canUndoLetters => _tool?.letters?.canUndo ?? false;
  bool get canRedoLetters => _tool?.letters?.canRedo ?? false;

  void undoLetters() => _tool?.letters?.undo();
  void redoLetters() => _tool?.letters?.redo();

  @override
  void dispose() {
    _tool?.removeListener(notifyListeners);
    _tool = null;
    super.dispose();
  }
}
