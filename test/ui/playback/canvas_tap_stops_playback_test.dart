import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// D13, the whole chain through the REAL app: the actuation gate's
/// navigation hole lets a press reach the canvas panel during playback,
/// and a plain TAP there stops — `CanvasPlaybackView`'s own tap handler,
/// awake again now that pointers reach it (the pre-T28-c law). One
/// gesture, both halves: the hole passes, the canvas stops.
void main() {
  testWidgets('a tap ON the canvas during playback stops it — through the '
      'gate\'s navigation hole, by the canvas\'s own hand', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;

    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.playback.isPlaying, isTrue);

    // A point on the canvas panel clear of the floating regions: the
    // upper third of the panel's own rect.
    final panel = tester.getRect(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-container')),
    );
    await tester.tapAt(Offset(panel.center.dx, panel.top + panel.height / 4));
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      session.playback.isPlaying,
      isFalse,
      reason: 'the hole passed the press to the canvas, and the canvas\'s '
          'tap-to-stop answered — a tap navigates nothing, so it stops',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('D13: a single-finger DRAG on the canvas during playback '
      'does not stop it — the press claims into the panel THROUGH the '
      'translucent full-bleed drop target above it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;

    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.playback.isPlaying, isTrue);

    final panel = tester.getRect(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-container')),
    );
    final start = Offset(panel.center.dx, panel.top + panel.height / 4);
    // A drag, not a tap: the down must NOT stop (it claims into the
    // canvas panel — the media drop target's translucent MetaData sits
    // over the whole tab and reading path.first declared IT the surface,
    // killing the hole; adversarial review). The movement disqualifies
    // the tap-to-stop, so playback survives the whole gesture.
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      session.playback.isPlaying,
      isTrue,
      reason: 'the canvas press navigates — it must not stop on DOWN',
    );
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      session.playback.isPlaying,
      isTrue,
      reason: 'a drag is navigation, not a tap — playback keeps running',
    );

    session.playback.stop();
    await tester.pumpAndSettle();
  });
}
