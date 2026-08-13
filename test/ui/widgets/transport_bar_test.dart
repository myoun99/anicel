import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

/// The shared transport bar. What is pinned here is the ARITHMETIC — where
/// a press lands, which handle it takes, and what the range does when the
/// two ends meet — because those are the parts three surfaces will rely on
/// without re-testing them.
void main() {
  const trackWidth = 420.0;

  /// Mounts the bar at a known width, so a pixel is a frame the test can
  /// compute rather than guess.
  Future<void> pump(
    WidgetTester tester, {
    required int frameCount,
    int currentFrame = 0,
    int inFrame = 0,
    int? outFrame,
    bool playing = false,
    ValueChanged<int>? onSeek,
    VoidCallback? onPlayPause,
    void Function(int, int)? onRangeChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: trackWidth,
              child: TransportBar(
                frameCount: frameCount,
                currentFrame: currentFrame,
                inFrame: inFrame,
                outFrame: outFrame ?? (frameCount - 1),
                playing: playing,
                onSeek: onSeek ?? (_) {},
                onPlayPause: onPlayPause ?? () {},
                onRangeChanged: onRangeChanged ?? (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset trackAt(WidgetTester tester, double fraction) {
    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('transport-track')),
    );
    return Offset(rect.left + rect.width * fraction, rect.center.dy);
  }

  group('readout', () {
    testWidgets('counts from one and pads to the source width', (tester) async {
      await pump(tester, frameCount: 96, currentFrame: 36);
      expect(find.text('37 / 96'), findsOneWidget);
    });

    testWidgets('a still shows one of one', (tester) async {
      await pump(tester, frameCount: 1);
      expect(find.text('1 / 1'), findsOneWidget);
    });
  });

  group('the track', () {
    testWidgets('a press away from the handles seeks there', (tester) async {
      var seeked = -1;
      await pump(tester, frameCount: 100, onSeek: (frame) => seeked = frame);
      await tester.tapAt(trackAt(tester, 0.5));
      expect(seeked, 50);
    });

    testWidgets('a press ON the in handle drags it, not the playhead', (
      tester,
    ) async {
      var seeked = -1;
      int? movedIn;
      await pump(
        tester,
        frameCount: 100,
        onSeek: (frame) => seeked = frame,
        onRangeChanged: (start, _) => movedIn = start,
      );
      final gesture = await tester.startGesture(trackAt(tester, 0.01));
      await gesture.moveTo(trackAt(tester, 0.25));
      await gesture.up();
      await tester.pump();
      expect(movedIn, 25);
      expect(seeked, -1, reason: 'the handle took the gesture');
    });

    testWidgets('the out handle stops at in rather than crossing it', (
      tester,
    ) async {
      int? movedIn;
      int? movedOut;
      await pump(
        tester,
        frameCount: 100,
        inFrame: 50,
        onRangeChanged: (start, end) {
          movedIn = start;
          movedOut = end;
        },
      );
      final gesture = await tester.startGesture(trackAt(tester, 0.99));
      await gesture.moveTo(trackAt(tester, 0.1));
      await gesture.up();
      await tester.pump();
      expect(movedIn, 50);
      expect(movedOut, 50);
    });

    testWidgets('a still frame source cannot be scrubbed off zero', (
      tester,
    ) async {
      var seeked = -1;
      await pump(tester, frameCount: 1, onSeek: (frame) => seeked = frame);
      await tester.tapAt(trackAt(tester, 0.9));
      expect(seeked, 0);
    });
  });

  group('the buttons', () {
    testWidgets('play reports and shows the pause glyph while running', (
      tester,
    ) async {
      var pressed = 0;
      await pump(tester, frameCount: 10, onPlayPause: () => pressed += 1);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('transport-play')));
      expect(pressed, 1);

      await pump(tester, frameCount: 10, playing: true);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('stepping clamps at both ends', (tester) async {
      var seeked = -1;
      await pump(
        tester,
        frameCount: 10,
        currentFrame: 0,
        onSeek: (frame) => seeked = frame,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('transport-step-back')),
      );
      expect(seeked, 0);

      await pump(
        tester,
        frameCount: 10,
        currentFrame: 9,
        onSeek: (frame) => seeked = frame,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('transport-step-forward')),
      );
      expect(seeked, 9);
    });

    testWidgets('the end buttons go to the RANGE, not the source', (
      tester,
    ) async {
      var seeked = -1;
      await pump(
        tester,
        frameCount: 100,
        inFrame: 10,
        outFrame: 80,
        onSeek: (frame) => seeked = frame,
      );
      await tester.tap(find.byKey(const ValueKey<String>('transport-to-in')));
      expect(seeked, 10);
      await tester.tap(find.byKey(const ValueKey<String>('transport-to-out')));
      expect(seeked, 80);
    });
  });

  group('narrow', () {
    testWidgets('the compact bar drops the step buttons and still fits', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: TransportBar(
                  frameCount: 96,
                  currentFrame: 0,
                  inFrame: 0,
                  outFrame: 95,
                  playing: false,
                  onSeek: _ignoreFrame,
                  onPlayPause: _ignore,
                  onRangeChanged: _ignoreRange,
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('transport-step-back')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('transport-play')),
        findsOneWidget,
      );
    });
  });

  group('the range fields', () {
    testWidgets('a typed IN is one-based and lands inside the source', (
      tester,
    ) async {
      int? movedIn;
      await pump(
        tester,
        frameCount: 100,
        outFrame: 40,
        onRangeChanged: (start, _) => movedIn = start,
      );
      await tester.tap(find.byKey(const ValueKey<String>('transport-in')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('transport-in-input')),
        '13',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(movedIn, 12);
    });

    testWidgets('a typed IN past OUT is pulled back to it', (tester) async {
      int? movedIn;
      await pump(
        tester,
        frameCount: 100,
        outFrame: 40,
        onRangeChanged: (start, _) => movedIn = start,
      );
      await tester.tap(find.byKey(const ValueKey<String>('transport-in')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('transport-in-input')),
        '99',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(movedIn, 40);
    });
  });
}

void _ignore() {}

void _ignoreFrame(int frame) {}

void _ignoreRange(int inFrame, int outFrame) {}
