import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🚨유저 2026-09-24: 「두손가락 핑거로 언두랑 세손가락 리두가
/// 안먹히는거같으니 다른부분도 조사해줘」 — through the REAL app, on the
/// canvas, because the gesture's own test drew it over a black box and
/// passed the whole time the app refused it.
///
/// 🔬What refused it: F-173's 「a contact down refuses undo」 counts contacts
/// in the pointer router, and the gesture fired inside its last finger's
/// lift, before the router had heard of the lift — so the finger that was
/// leaving was still 「down」 and every two-finger undo and three-finger
/// redo was refused. And the same survey found the playing canvas taking a
/// gesture as TWO actuations — the panel's stop on the first lift, then the
/// bound action.
void main() {
  Future<EditorSessionManager> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    // One edit to take back and put again.
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    expect(session.canUndo, isTrue, reason: 'LIVENESS — an edit to undo');
    expect(session.canRedo, isFalse);
    return session;
  }

  /// A point on the canvas panel clear of the floating regions.
  Offset onCanvas(WidgetTester tester) {
    final panel = tester.getRect(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-container')),
    );
    return Offset(panel.center.dx, panel.top + panel.height / 4);
  }

  /// [fingers] touches landing together, held a moment, lifted in place.
  Future<void> fingerTap(
    WidgetTester tester, {
    required int fingers,
    required int firstPointer,
  }) async {
    final at = onCanvas(tester);
    final contacts = [
      for (var finger = 0; finger < fingers; finger += 1)
        await tester.startGesture(
          at + Offset(finger * 60.0, 0),
          kind: PointerDeviceKind.touch,
          pointer: firstPointer + finger,
        ),
    ];
    await tester.pump(const Duration(milliseconds: 40));
    for (final contact in contacts) {
      await contact.up(timeStamp: const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('🎯a two-finger tap on the canvas undoes, and a three-finger '
      'tap redoes', (tester) async {
    final session = await pumpEditor(tester);

    await fingerTap(tester, fingers: 2, firstPointer: 20);
    expect(session.canRedo, isTrue, reason: 'the two-finger tap undid');
    expect(session.canUndo, isFalse);

    await fingerTap(tester, fingers: 3, firstPointer: 30);
    expect(session.canRedo, isFalse, reason: 'the three-finger tap redid');
    expect(session.canUndo, isTrue);
  });

  testWidgets('🚨and F-173 still holds: while a pen is down, a two-finger tap '
      'undoes nothing', (tester) async {
    final session = await pumpEditor(tester);
    final pen = await tester.startGesture(
      onCanvas(tester) + const Offset(0, 120),
      kind: PointerDeviceKind.stylus,
      pointer: 5,
    );
    await tester.pump(const Duration(milliseconds: 16));

    await fingerTap(tester, fingers: 2, firstPointer: 40);

    expect(
      session.canRedo,
      isFalse,
      reason: 'a contact still down is a verb in flight (유저 2026-09-21: '
          '「도구를 사용중이면 언두/리두 작동불가」)',
    );
    await pen.up();
    await tester.pumpAndSettle();
  });

  group('🚨on the PLAYING canvas a gesture is a stop, and only a stop (T28-c: '
      '「재생 중 첫 작동은 정지이고, 정지일 뿐이다」)', () {
    Future<void> play(WidgetTester tester, EditorSessionManager session) async {
      session.playbackRig.playback.play(scope: PlaybackScope.activeCut);
      await tester.pump(const Duration(milliseconds: 16));
      expect(session.playbackRig.playback.isPlaying, isTrue);
    }

    testWidgets('four fingers — the play/pause tap — stop it and it stays '
        'stopped', (tester) async {
      final session = await pumpEditor(tester);
      await play(tester, session);

      await fingerTap(tester, fingers: 4, firstPointer: 50);

      expect(
        session.playbackRig.playback.isPlaying,
        isFalse,
        reason: 'it stopped and then started again: the panel stopped it on '
            'the first lift, and the gesture pressed play/pause after',
      );
    });

    testWidgets('two fingers stop it and undo nothing', (tester) async {
      final session = await pumpEditor(tester);
      await play(tester, session);

      await fingerTap(tester, fingers: 2, firstPointer: 60);

      expect(session.playbackRig.playback.isPlaying, isFalse);
      expect(session.canRedo, isFalse, reason: 'the stop was all it did');
    });
  });
}
