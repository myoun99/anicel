import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';
import 'package:anicel/src/ui/session/sheet_photo_hold.dart';

import '../helpers/app_shortcuts.dart';
import '../helpers/cel_photo_fixture.dart';
import '../helpers/cel_text_tool_harness.dart';
import '../helpers/key_chords.dart';

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

  testWidgets('🗣️F-377: Ctrl+Z takes the held photo\'s grabs back one at a '
      'time, and once it is let go they are ONE step', (tester) async {
    final session = await pumpApp(tester);
    final at = putPhoto(session);
    final history = session.historyManager;
    final hold = session.sheetPhotoHold;
    TransformPose poseOf() => session.renderCaches.envelopeInkStore
        .bakedSurfaceOrNull(at.key)!
        .photos
        .single
        .reference
        .pose;
    final put = poseOf();
    final steps = history.undoCount;
    hold.take(at);
    final moved = put.copyWith(
      center: CanvasPoint(x: put.center.x + 30, y: put.center.y),
    );
    final sized = moved.copyWith(scaleX: 2, scaleY: 2);
    for (final pose in [moved, sized, sized.copyWith(rotationDegrees: 30)]) {
      hold.land(at, pose);
    }
    await tester.pump();
    expect(history.undoCount, steps + 3, reason: '⛔전제: a step a grab');

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    expect(poseOf(), sized, reason: 'the last grab taken back');
    expect(hold.held, at, reason: 'and the photo still held');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(hold.held, isNull);
    expect(history.undoCount, steps + 1, reason: 'its grabs are ONE step');

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    expect(poseOf(), put, reason: 'one undo takes the hold back whole');

    // Held again with no grab to take back, an undo is the document's — and
    // lets go of the photo first, as it lands a text in hand.
    hold.take(at);
    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    expect(hold.held, isNull);
  });

  testWidgets('F-377: another photo taken lets go of the one held — its '
      'grabs one step', (tester) async {
    final session = await pumpApp(tester);
    final first = putPhoto(session);
    putPhoto(session);
    final store = session.renderCaches.envelopeInkStore;
    final ids = [
      for (final photo in store.bakedSurfaceOrNull(first.key)!.photos)
        photo.id,
    ];
    expect(ids, hasLength(2), reason: '⛔전제: two photos on the box');
    final held = (key: first.key, id: ids.first);
    TransformPose poseOf(SheetPhotoAt at) => store
        .bakedSurfaceOrNull(at.key)!
        .photos
        .firstWhere((photo) => photo.id == at.id)
        .reference
        .pose;
    final put = poseOf(held);
    final moved = put.copyWith(
      center: CanvasPoint(x: put.center.x + 30, y: put.center.y),
    );
    session.sheetPhotoHold
      ..take(held)
      ..land(held, moved)
      ..land(held, moved.copyWith(rotationDegrees: 30))
      ..take((key: first.key, id: ids.last));
    await tester.pump();

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);

    expect(poseOf(held), put, reason: 'its grabs went back in one');
  });

  testWidgets('F-377: a photo taken off after a grab — the grab is one step, '
      'and taking it off another', (tester) async {
    final session = await pumpApp(tester);
    await useAnicelKeys(tester);
    final at = putPhoto(session);
    final hold = session.sheetPhotoHold;
    final store = session.renderCaches.envelopeInkStore;
    final put = store.bakedSurfaceOrNull(at.key)!.photos.single.reference.pose;
    final moved = put.copyWith(
      center: CanvasPoint(x: put.center.x + 30, y: put.center.y),
    );
    hold
      ..take(at)
      ..land(at, moved)
      ..land(at, moved.copyWith(rotationDegrees: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(photosOn(session, at), 0, reason: '⛔전제: taken off');

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    expect(
      store.bakedSurfaceOrNull(at.key)!.photos.single.reference.pose,
      moved.copyWith(rotationDegrees: 30),
      reason: 'back on, where the grabs had it',
    );
    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    expect(
      store.bakedSurfaceOrNull(at.key)!.photos.single.reference.pose,
      put,
      reason: 'and its grabs back whole, in one',
    );
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
