import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';
import 'package:anicel/src/ui/session/sheet_photo_hold.dart';

import '../helpers/app_shortcuts.dart';
import '../helpers/cel_photo_fixture.dart';
import '../helpers/cel_text_tool_harness.dart';

/// I-97 through the app: a photo held on a sheet is the thing in hand.
/// Escape lets go of it, as a press past its cell does (Q4), and Delete
/// takes it off its cel as its pill's delete does (Q3) — ONE step — both
/// ahead of anything else the keys answer: any press of a tool past the
/// photo lets go of it, so one still held is the last thing the hand took.
void main() {
  Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects
        .active;
  }

  /// A photo put on a box of the cut's 봉투, in the session's own store.
  SheetPhotoAt putPhoto(EditorSessionManager session) {
    final ink = CutEnvelopeInkController(
      store: session.renderCaches.envelopeInkStore,
    )..syncGeometry(aspectRatio: 1);
    addTearDown(ink.dispose);
    final key = envelopeInkBoxKey(session.requireActiveCut.id, 'sheet-space');
    ink.putPhoto(
      plane: null,
      key: key,
      reference: photoOf(1).reference,
      historyManager: session.historyManager,
    );
    return (key: key, id: 1);
  }

  int photosOn(EditorSessionManager session, SheetPhotoAt at) =>
      session.renderCaches.envelopeInkStore
          .bakedSurfaceOrNull(at.key)
          ?.photos
          .length ??
      0;

  testWidgets('Escape lets go of the photo held — first, and of nothing '
      'else: a canvas being adjusted stays open for the next', (
    tester,
  ) async {
    final session = await pumpApp(tester);
    final cut = session.requireActiveCut;
    session.canvasAdjust.begin(CanvasEdgesDraft.of(cut.id, cut.canvasSize));
    final at = putPhoto(session);
    session.sheetPhotoHold.take(at);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(session.sheetPhotoHold.held, isNull);
    expect(photosOn(session, at), 1, reason: 'let go of, not taken off');
    expect(session.canvasAdjust.isOpen, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(session.canvasAdjust.isOpen, isFalse);
  });

  testWidgets('Delete takes the photo held off its cel — ONE step — and '
      'lets go of it; one undo puts it back', (tester) async {
    final session = await pumpApp(tester);
    // Delete is 삭제 on the registry's keys — Clip Studio's is its Erase.
    await useAnicelKeys(tester);
    final at = putPhoto(session);
    final history = session.historyManager;
    final steps = history.undoCount;
    session.sheetPhotoHold.take(at);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(photosOn(session, at), 0);
    expect(history.undoCount, steps + 1);
    expect(session.sheetPhotoHold.held, isNull);

    history.undo();
    expect(photosOn(session, at), 1);
  });

  testWidgets('🚨a text held on the canvas as well: Delete takes the photo '
      '— the last thing the hand took, as a text taken after it would have '
      'let go of it — and the text is the next Delete\'s', (tester) async {
    await pumpTextToolApp(tester);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await clickAt(tester, c.dx + 300, c.dy + 200);
    await useAnicelKeys(tester);
    await clickAt(tester, c.dx + 10, c.dy + 30);
    expect(textToolOf(tester).session, isNotNull, reason: '⛔전제: held');
    final session = sessionOf(tester);
    final at = putPhoto(session);
    session.sheetPhotoHold.take(at);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await pumpFrames(tester);

    expect(photosOn(session, at), 0);
    expect(celOf(tester).texts, hasLength(1), reason: 'the text stays');

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await pumpFrames(tester);
    expect(celOf(tester).texts, isEmpty);
  });
}
