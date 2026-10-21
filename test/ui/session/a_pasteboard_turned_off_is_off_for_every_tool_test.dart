import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-109 (유저 2026-10-18): 「페이스트보드 사용안함시 근본/구조적으로 사용
/// 안하도록 … 진짜 근본/구조적으로」 — one wall for the whole session: the
/// project's size and use set it, the cels' store stands behind it, and
/// the wall the canvas hands its tools (the selection's inverse, the
/// boxes, the text) is that same wall. One undo walks all of it back.
void main() {
  EditorSessionManager session() {
    final session = EditorSessionManager(
      initialProject: newUntitledProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  void expectWallAt(EditorSessionManager session, PasteboardReach reach) {
    final canvas = session.requireActiveCut.canvasSize;
    expect(session.activePasteboardOrNull, canvas.pasteboardAt(reach));
    expect(session.pasteboardOf(canvas), canvas.pasteboardAt(reach));
    expect(
      session.renderCaches.brushFrameStore.pasteboardReach,
      reach,
      reason: 'the cels stand behind the wall the tools are handed',
    );
  }

  test('a new project has the 3x pasteboard, in use', () {
    expectWallAt(session(), PasteboardReach.whole);
  });

  test('off, every wall is the paper; one undo brings it back', () {
    final s = session();
    s.projectSettings.setPasteboardInUse(false);
    expect(s.repository.requireProject().pasteboardInUse, isFalse);
    expectWallAt(s, PasteboardReach.none);
    s.undo();
    expectWallAt(s, PasteboardReach.whole);
    s.redo();
    expectWallAt(s, PasteboardReach.none);
  });

  test('a size moves every wall to it, and undo moves it back', () {
    final s = session();
    s.projectSettings.setPasteboardSize(PasteboardSize.oneAndAHalf);
    expectWallAt(s, PasteboardReach.quarter);
    s.projectSettings.setPasteboardSize(PasteboardSize.two);
    expectWallAt(s, PasteboardReach.half);
    s.undo();
    expectWallAt(s, PasteboardReach.quarter);
    s.undo();
    expectWallAt(s, PasteboardReach.whole);
  });

  test('off keeps the size for when it is on again', () {
    final s = session();
    s.projectSettings.setPasteboardSize(PasteboardSize.two);
    s.projectSettings.setPasteboardInUse(false);
    expectWallAt(s, PasteboardReach.none);
    s.projectSettings.setPasteboardInUse(true);
    expectWallAt(s, PasteboardReach.half);
  });
}
