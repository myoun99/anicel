import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/contact_census.dart';
import 'package:anicel/src/ui/input/warmer_hand.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';

import '../../helpers/panel_finders.dart';

/// 🗣️H57-Q2 = 1 (유저 2026-11-19 「손이 닿는 조작은 전부 「손」으로 — 입구
/// 한 곳」): every input the hand makes is told to the warmer of the project
/// on screen from the window's one input entry — a press holds it while a
/// contact is down, every other input opens its quiet window again, and a
/// hover is no hand on it.
void main() {
  throughTheWindow();

  late _Warmer onScreen;
  late ContactCensus census;
  late WarmerHand hand;

  setUp(() {
    onScreen = _Warmer();
    census = ContactCensus(cancel: (_) {});
    hand = WarmerHand(() => onScreen);
  });

  /// [event] off the global pointer route, as the window hears it.
  void route(PointerEvent event) {
    census.note(event);
    hand.heard(event, down: census.anyDown);
  }

  test('a press holds the warmer while it is down, and lets it go with a '
      'fresh quiet window as it lifts', () {
    route(const PointerDownEvent(pointer: 1));
    route(const PointerMoveEvent(pointer: 1, position: Offset(4, 4)));
    expect(onScreen.holds, 1);

    final told = onScreen.told;
    route(const PointerUpEvent(pointer: 1));

    expect(onScreen.holds, 0);
    expect(onScreen.told, greaterThan(told));
  });

  test('a press cancelled lets the warmer go as a lift does', () {
    route(const PointerDownEvent(pointer: 1));
    route(const PointerCancelEvent(pointer: 1));

    expect(onScreen.holds, 0);
  });

  test('two fingers down hold it once — till the last of them lifts', () {
    const touch = PointerDeviceKind.touch;
    route(const PointerDownEvent(pointer: 1, kind: touch));
    route(const PointerDownEvent(pointer: 2, kind: touch));
    expect(onScreen.holds, 1);

    route(const PointerUpEvent(pointer: 1, kind: touch));
    expect(onScreen.holds, 1, reason: 'a finger is still down');

    route(const PointerUpEvent(pointer: 2, kind: touch));
    expect(onScreen.holds, 0);
  });

  test('a wheel, a trackpad\'s pan and a key open the quiet window again',
      () {
    route(
      const PointerScrollEvent(
        position: Offset(10, 10),
        scrollDelta: Offset(0, 100),
      ),
    );
    expect(onScreen.told, 1);

    route(const PointerPanZoomStartEvent());
    route(const PointerPanZoomUpdateEvent(pan: Offset(0, 8)));
    route(const PointerPanZoomEndEvent());
    expect(onScreen.told, 4);

    final handled = hand.heardKey(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        timeStamp: Duration.zero,
      ),
    );
    expect(onScreen.told, 5);
    expect(handled, isFalse, reason: 'the key goes on to whom it is for');
    expect(onScreen.holds, 0, reason: 'none of them is a contact down');
  });

  test('a pointer that only moves over the window is no hand on it', () {
    route(const PointerHoverEvent(position: Offset(10, 10)));
    route(const PointerAddedEvent());
    route(const PointerRemovedEvent());

    expect(onScreen.told, 0);
    expect(onScreen.holds, 0);
  });

  test('the press lets go of the warmer it took, whichever project is on '
      'screen as it lifts', () {
    final first = onScreen;
    route(const PointerDownEvent(pointer: 1));
    onScreen = _Warmer();

    route(const PointerUpEvent(pointer: 1));

    expect(first.holds, 0);
    expect(onScreen.holds, 0, reason: 'never held, never let go');
  });
}

/// 🧪Through the window itself: the route and the keyboard the window
/// hears every input on, the warmer of the project it shows.
void throughTheWindow() {
  late PlaybackPrerenderScheduler warmer;

  Future<void> boot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    warmer = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip).first)
        .projects
        .sessions
        .first
        .playbackRig
        .prerenderScheduler;
  }

  testWidgets('a press held on the canvas keeps the warmer shut — past the '
      'quiet window — till it lifts', (tester) async {
    await boot(tester);
    var quiet = false;
    // The middle button pans the view: no stroke, no edit — nothing else
    // holds the warmer.
    final press = await tester.startGesture(
      tester.getCenter(mainCanvasView()),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    unawaited(warmer.untilQuiet().then((_) => quiet = true));
    await tester.pump(const Duration(seconds: 1));
    expect(quiet, isFalse, reason: 'a contact down, a second past the window');

    await press.up();
    await tester.pump(const Duration(seconds: 1));

    expect(quiet, isTrue);
  });

  testWidgets('a wheel over the canvas and a key open the quiet window of '
      'the warmer again', (tester) async {
    await boot(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse)
      ..hover(tester.getCenter(mainCanvasView()));
    final before = warmer.lastEditActivity;

    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    final wheeled = warmer.lastEditActivity;
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);

    expect(wheeled, isNot(before));
    expect(warmer.lastEditActivity, isNot(wheeled));
  });
}

/// A warmer that counts what the hand tells it.
final class _Warmer implements PlaybackPrerenderScheduler {
  /// Holds open ([beginInputHold] less [endInputHold]).
  int holds = 0;

  /// How often its quiet window was opened again — by an input, or by a
  /// hold let go ([endInputHold] opens one too).
  int told = 0;

  @override
  void beginInputHold() => holds += 1;

  @override
  void endInputHold() {
    holds -= 1;
    told += 1;
  }

  @override
  void notifyEditActivity() => told += 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
