import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/app_icon_button_probe.dart';

/// The shared transport. Two things are pinned here, because every surface
/// that runs in time relies on them without re-testing them:
///
///  * the SHAPE the user drew (F-289, 2026-10-06) — the seek track across
///    the top, the readout · the buttons · the sound under it, and IN/OUT
///    in a third row only where a span is handed;
///  * the ARITHMETIC — where a press lands, which handle it takes, and what
///    the range does when the two ends meet.
void main() {
  const barWidth = 420.0;

  ValueKey<String> k(String suffix) => ValueKey<String>('transport-$suffix');

  /// Mounts the bar at a known width, so a pixel is a frame the test can
  /// compute rather than guess.
  Future<void> pump(
    WidgetTester tester, {
    required int frameCount,
    int currentFrame = 0,
    bool playing = false,
    ValueChanged<int>? onSeek,
    VoidCallback? onPlayPause = _ignore,
    TransportRange? range,
    TransportSound? sound,
    double width = barWidth,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: TransportBar(
                frameCount: frameCount,
                currentFrame: currentFrame,
                playing: playing,
                onSeek: onSeek ?? (_) {},
                onPlayPause: onPlayPause,
                range: range,
                sound: sound,
              ),
            ),
          ),
        ),
      ),
    );
  }

  TransportRange span(
    int inFrame,
    int outFrame, [
    void Function(int, int)? onChanged = _ignoreRange,
  ]) => TransportRange(
    inFrame: inFrame,
    outFrame: outFrame,
    onChanged: onChanged,
  );

  Offset along(WidgetTester tester, String track, double fraction) {
    final rect = tester.getRect(find.byKey(k(track)));
    return Offset(rect.left + rect.width * fraction, rect.center.dy);
  }

  /// Every rectangle [track]'s painter draws, with its colour — as the
  /// 32-bit ARGB a screen shows: a paint hands its colour back through the
  /// engine's floats, which no longer equal the doubles it was given.
  List<({Rect rect, int color})> drawn(WidgetTester tester, String track) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(k(track)),
        matching: find.byType(CustomPaint),
      ),
    );
    final canvas = TestRecordingCanvas();
    paint.painter!.paint(canvas, tester.getSize(find.byKey(k(track))));
    return [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawRect)
          (
            rect: call.invocation.positionalArguments[0] as Rect,
            color: (call.invocation.positionalArguments[1] as Paint).color
                .toARGB32(),
          ),
    ];
  }

  final washArgb = TransportBar.rangeWash.toARGB32();

  group('the rows', () {
    testWidgets('the seek track runs the bar\'s width, over the readout, the '
        'buttons and the sound', (tester) async {
      await pump(tester, frameCount: 96, currentFrame: 36);
      final bar = tester.getRect(find.byType(TransportBar));
      final track = tester.getRect(find.byKey(k('track')));
      final readout = tester.getRect(find.byKey(k('position')));
      final first = tester.getRect(find.byKey(k('first')));
      final play = tester.getRect(find.byKey(k('play')));
      final last = tester.getRect(find.byKey(k('last')));
      final mute = tester.getRect(find.byKey(k('mute')));
      final volume = tester.getRect(find.byKey(k('volume')));

      expect(track.left, bar.left + 8);
      expect(track.right, bar.right - 8);
      for (final under in [readout, first, play, last, mute, volume]) {
        expect(under.top, greaterThanOrEqualTo(track.bottom));
      }
      expect(readout.left, bar.left + 8, reason: 'the readout leads the row');
      expect(readout.right, lessThan(first.left));
      expect(
        play.center.dx,
        moreOrLessEquals(bar.center.dx, epsilon: 0.5),
        reason: 'the buttons hold the middle',
      );
      expect(mute.left, greaterThan(last.right));
      expect(volume.right, bar.right - 8, reason: 'the sound ends the row');
    });

    testWidgets('IN and OUT stand in a third row, and only where a span is '
        'handed', (tester) async {
      await pump(tester, frameCount: 96);
      expect(find.byKey(k('range')), findsNothing);
      expect(find.byKey(k('in')), findsNothing);
      expect(find.byKey(k('out')), findsNothing);

      await pump(tester, frameCount: 96, range: span(0, 95));
      final play = tester.getRect(find.byKey(k('play')));
      final range = tester.getRect(find.byKey(k('range')));
      final inValue = tester.getRect(find.byKey(k('in')));
      final outValue = tester.getRect(find.byKey(k('out')));
      expect(range.top, greaterThan(play.bottom));
      expect(inValue.right, lessThan(range.left));
      expect(outValue.left, greaterThan(range.right));
    });

    testWidgets('the bar stands as tall as it says, with the range and '
        'without', (tester) async {
      await pump(tester, frameCount: 96);
      final context = tester.element(find.byType(TransportBar));
      expect(
        tester.getSize(find.byType(TransportBar)).height,
        TransportBar.heightIn(context, range: false),
      );

      await pump(tester, frameCount: 96, range: span(0, 95));
      expect(
        tester.getSize(find.byType(TransportBar)).height,
        TransportBar.heightIn(context, range: true),
      );
      expect(
        TransportBar.heightIn(context, range: true),
        greaterThan(TransportBar.heightIn(context, range: false)),
      );
    });

    testWidgets('a surface names its own keys, so two bars share none', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final prefix in ['main', 'sub'])
                  SizedBox(
                    width: barWidth,
                    child: TransportBar(
                      keyPrefix: prefix,
                      frameCount: 10,
                      currentFrame: 0,
                      playing: false,
                      onSeek: _ignoreFrame,
                      onPlayPause: _ignore,
                      range: span(0, 9),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      for (final suffix in [
        'track',
        'position',
        'first',
        'step-back',
        'play',
        'step-forward',
        'last',
        'mute',
        'volume',
        'range',
        'in',
        'out',
      ]) {
        expect(find.byKey(ValueKey<String>('main-$suffix')), findsOneWidget);
        expect(find.byKey(ValueKey<String>('sub-$suffix')), findsOneWidget);
        expect(find.byKey(k(suffix)), findsNothing);
      }
    });
  });

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

  group('the seek track', () {
    testWidgets('a press seeks there — once', (tester) async {
      final seeks = <int>[];
      await pump(tester, frameCount: 100, onSeek: seeks.add);
      await tester.tapAt(along(tester, 'track', 0.5));
      expect(
        seeks,
        [50],
        reason: 'the drag the release starts lands where the press did',
      );
    });

    testWidgets('and keeps seeking while the finger moves', (tester) async {
      final seeks = <int>[];
      await pump(tester, frameCount: 101, onSeek: seeks.add);
      final gesture = await tester.startGesture(along(tester, 'track', 0.2));
      await gesture.moveTo(along(tester, 'track', 0.8));
      await gesture.up();
      await tester.pump();
      expect(seeks.first, 20);
      expect(seeks.last, 80);
    });

    testWidgets('it carries no handle: a press at the span\'s end seeks', (
      tester,
    ) async {
      final seeks = <int>[];
      int? movedIn;
      await pump(
        tester,
        frameCount: 100,
        onSeek: seeks.add,
        range: span(0, 99, (start, _) => movedIn = start),
      );
      final gesture = await tester.startGesture(along(tester, 'track', 0.01));
      await gesture.moveTo(along(tester, 'track', 0.25));
      await gesture.up();
      await tester.pump();
      expect(seeks.last, 25);
      expect(movedIn, isNull, reason: 'the handles are the range row\'s');
    });

    testWidgets('the span that is kept is washed on it, between its ends', (
      tester,
    ) async {
      await pump(tester, frameCount: 101, range: span(25, 75));
      final track = tester.getSize(find.byKey(k('track')));
      final wash = drawn(
        tester,
        'track',
      ).where((rect) => rect.color == washArgb).toList();
      expect(wash, hasLength(1));
      expect(wash.single.rect.left, moreOrLessEquals(track.width * 0.25));
      expect(wash.single.rect.right, moreOrLessEquals(track.width * 0.75));
    });

    testWidgets('a span that can act on nothing is not washed on it', (
      tester,
    ) async {
      await pump(tester, frameCount: 101, range: span(25, 75, null));
      expect(
        drawn(tester, 'track').where((r) => r.color == washArgb),
        isEmpty,
      );
    });

    testWidgets('a source with one frame has nowhere to seek to', (
      tester,
    ) async {
      final seeks = <int>[];
      await pump(tester, frameCount: 1, onSeek: seeks.add);
      await tester.tapAt(along(tester, 'track', 0.9));
      await tester.dragFrom(along(tester, 'track', 0.1), const Offset(120, 0));
      expect(seeks, isEmpty);
    });
  });

  group('the buttons', () {
    testWidgets('play reports and shows the pause glyph while running', (
      tester,
    ) async {
      var pressed = 0;
      await pump(tester, frameCount: 10, onPlayPause: () => pressed += 1);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.tap(find.byKey(k('play')));
      expect(pressed, 1);

      await pump(tester, frameCount: 10, playing: true);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('with nothing to play, play stays where it is and is off', (
      tester,
    ) async {
      await pump(tester, frameCount: 10, onPlayPause: null);
      expect(tester.appIconButton(find.byKey(k('play'))).onPressed, isNull);
    });

    testWidgets('stepping clamps at both ends', (tester) async {
      var seeked = -1;
      await pump(
        tester,
        frameCount: 10,
        currentFrame: 0,
        onSeek: (frame) => seeked = frame,
      );
      await tester.tap(find.byKey(k('step-back')));
      expect(seeked, 0);
      await tester.tap(find.byKey(k('step-forward')));
      expect(seeked, 1);

      await pump(
        tester,
        frameCount: 10,
        currentFrame: 9,
        onSeek: (frame) => seeked = frame,
      );
      await tester.tap(find.byKey(k('step-forward')));
      expect(seeked, 9);
      await tester.tap(find.byKey(k('step-back')));
      expect(seeked, 8);
    });

    testWidgets('the end buttons stop at the span that is kept', (
      tester,
    ) async {
      var seeked = -1;
      await pump(
        tester,
        frameCount: 100,
        currentFrame: 40,
        onSeek: (frame) => seeked = frame,
        range: span(10, 80),
      );
      await tester.tap(find.byKey(k('first')));
      expect(seeked, 10);
      await tester.tap(find.byKey(k('last')));
      expect(seeked, 80);
    });

    testWidgets('with no span — or one that cannot act — they go to the '
        'source\'s own ends', (tester) async {
      var seeked = -1;
      for (final range in [null, span(10, 80, null)]) {
        await pump(
          tester,
          frameCount: 100,
          currentFrame: 40,
          onSeek: (frame) => seeked = frame,
          range: range,
        );
        await tester.tap(find.byKey(k('first')));
        expect(seeked, 0);
        await tester.tap(find.byKey(k('last')));
        expect(seeked, 99);
      }
    });

    testWidgets('a source with one frame leaves all four where they are, '
        'off', (tester) async {
      await pump(tester, frameCount: 1);
      for (final suffix in ['first', 'step-back', 'step-forward', 'last']) {
        expect(
          tester.appIconButton(find.byKey(k(suffix))).onPressed,
          isNull,
          reason: suffix,
        );
      }
    });
  });

  group('the sound', () {
    testWidgets('with no sound the cell stays where it is, off', (
      tester,
    ) async {
      await pump(tester, frameCount: 10);
      expect(tester.appIconButton(find.byKey(k('mute'))).onPressed, isNull);
      expect(
        tester.widget<FieldSlider>(find.byKey(k('volume'))).onChanged,
        isNull,
      );
    });

    testWidgets('the speaker reports, and wears the off glyph while muted', (
      tester,
    ) async {
      var toggles = 0;
      TransportSound sound({required bool muted}) => TransportSound(
        level: 0.7,
        muted: muted,
        onLevelChanged: (_) {},
        onLevelSettled: (_) {},
        onMuteToggled: () => toggles += 1,
      );
      await pump(tester, frameCount: 10, sound: sound(muted: false));
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(
        tester.widget<FieldSlider>(find.byKey(k('volume'))).restingAccent,
        isNull,
      );
      await tester.tap(find.byKey(k('mute')));
      expect(toggles, 1);

      await pump(tester, frameCount: 10, sound: sound(muted: true));
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      final bar = tester.widget<FieldSlider>(find.byKey(k('volume')));
      expect(bar.value, 0.7, reason: 'muting keeps the level');
      expect(bar.restingAccent, AppColors.textDim, reason: 'and greys it');
    });

    testWidgets('the bar reports each step under the hand, and once where '
        'it is let go', (tester) async {
      final steps = <double>[];
      final settled = <double>[];
      await pump(
        tester,
        frameCount: 10,
        sound: TransportSound(
          level: 1,
          muted: false,
          onLevelChanged: steps.add,
          onLevelSettled: settled.add,
          onMuteToggled: () {},
        ),
      );
      final bar = tester.getRect(find.byKey(k('volume')));
      final gesture = await tester.startGesture(
        Offset(bar.left + bar.width * 0.75, bar.center.dy),
      );
      await gesture.moveTo(Offset(bar.left + bar.width * 0.25, bar.center.dy));
      await gesture.up();
      await tester.pump();
      expect(steps, isNotEmpty);
      expect(steps.last, moreOrLessEquals(0.25, epsilon: 0.02));
      expect(settled, hasLength(1));
      expect(settled.single, moreOrLessEquals(0.25, epsilon: 0.02));
    });
  });

  group('the range row', () {
    testWidgets('a press ON the in handle drags it, and seeks nothing', (
      tester,
    ) async {
      var seeked = -1;
      int? movedIn;
      await pump(
        tester,
        frameCount: 100,
        onSeek: (frame) => seeked = frame,
        range: span(0, 99, (start, _) => movedIn = start),
      );
      final gesture = await tester.startGesture(along(tester, 'range', 0.01));
      await gesture.moveTo(along(tester, 'range', 0.25));
      await gesture.up();
      await tester.pump();
      expect(movedIn, 25);
      expect(seeked, -1, reason: 'the range row never seeks');
    });

    testWidgets('the out handle stops at in rather than crossing it', (
      tester,
    ) async {
      int? movedIn;
      int? movedOut;
      await pump(
        tester,
        frameCount: 100,
        range: span(50, 99, (start, end) {
          movedIn = start;
          movedOut = end;
        }),
      );
      final gesture = await tester.startGesture(along(tester, 'range', 0.99));
      await gesture.moveTo(along(tester, 'range', 0.1));
      await gesture.up();
      await tester.pump();
      expect(movedIn, 50);
      expect(movedOut, 50);
    });

    testWidgets('a press away from both handles moves neither', (
      tester,
    ) async {
      final moves = <(int, int)>[];
      await pump(
        tester,
        frameCount: 101,
        range: span(10, 90, (start, end) => moves.add((start, end))),
      );
      final gesture = await tester.startGesture(along(tester, 'range', 0.5));
      await gesture.moveTo(along(tester, 'range', 0.7));
      await gesture.up();
      await tester.pump();
      expect(moves, isEmpty);
    });

    testWidgets('two handles on one frame part the way the hand goes', (
      tester,
    ) async {
      final moves = <(int, int)>[];
      Future<void> pull(double to) async {
        moves.clear();
        await pump(
          tester,
          frameCount: 101,
          range: span(50, 50, (start, end) => moves.add((start, end))),
        );
        final gesture = await tester.startGesture(along(tester, 'range', 0.5));
        await gesture.moveTo(along(tester, 'range', to));
        await gesture.up();
        await tester.pump();
      }

      await pull(0.2);
      expect(moves.last, (20, 50), reason: 'leftwards is IN');
      await pull(0.8);
      expect(moves.last, (50, 80), reason: 'rightwards is OUT');
    });

    testWidgets('each handle is the playhead\'s hairline, in the accent', (
      tester,
    ) async {
      await pump(
        tester,
        frameCount: 101,
        currentFrame: 50,
        range: span(25, 75),
      );
      final handles = drawn(
        tester,
        'range',
      ).where((rect) => rect.color == AppColors.accent.toARGB32()).toList();
      final playhead = drawn(
        tester,
        'track',
      ).where((rect) => rect.color == AppColors.text.toARGB32()).toList();
      expect(handles, hasLength(2));
      expect(playhead, hasLength(1));
      for (final handle in handles) {
        expect(handle.rect.width, playhead.single.rect.width);
        expect(handle.rect.width, 1);
      }
      final range = tester.getSize(find.byKey(k('range')));
      expect(handles.first.rect.left, moreOrLessEquals(range.width * 0.25));
      expect(handles.last.rect.right, moreOrLessEquals(range.width * 0.75));
    });

    testWidgets('a typed IN is one-based and lands inside the source', (
      tester,
    ) async {
      int? movedIn;
      await pump(
        tester,
        frameCount: 100,
        range: span(0, 40, (start, _) => movedIn = start),
      );
      await tester.tap(find.byKey(k('in')));
      await tester.pump();
      await tester.enterText(find.byKey(k('in-input')), '13');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(movedIn, 12);
    });

    testWidgets('a typed IN past OUT is pulled back to it', (tester) async {
      int? movedIn;
      await pump(
        tester,
        frameCount: 100,
        range: span(0, 40, (start, _) => movedIn = start),
      );
      await tester.tap(find.byKey(k('in')));
      await tester.pump();
      await tester.enterText(find.byKey(k('in-input')), '99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(movedIn, 40);
    });

    testWidgets('a typed OUT before IN is pulled forward to it', (
      tester,
    ) async {
      int? movedOut;
      await pump(
        tester,
        frameCount: 100,
        range: span(30, 99, (_, end) => movedOut = end),
      );
      await tester.tap(find.byKey(k('out')));
      await tester.pump();
      await tester.enterText(find.byKey(k('out-input')), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(movedOut, 30);
    });

    testWidgets('a span that can act on nothing keeps its row, off', (
      tester,
    ) async {
      await pump(tester, frameCount: 100, range: span(0, 99, null));
      for (final suffix in ['in', 'out']) {
        final readout = tester.widget<DragValueLabel>(
          find.ancestor(
            of: find.byKey(k(suffix)),
            matching: find.byType(DragValueLabel),
          ),
        );
        expect(readout.enabled, isFalse, reason: suffix);
      }
      expect(find.byKey(k('range')), findsOneWidget);
      // Nothing to report to: a pull on a handle is taken and goes nowhere.
      await tester.dragFrom(along(tester, 'range', 0.01), const Offset(80, 0));
      expect(tester.takeException(), isNull);
      expect(
        drawn(
          tester,
          'range',
        ).where((r) => r.color == AppColors.accent.toARGB32()),
        isEmpty,
        reason: 'the handles wear the accent only while they can move',
      );
    });
  });

  group('narrow', () {
    testWidgets('at its minimum width the bar lays out without running over', (
      tester,
    ) async {
      await pump(
        tester,
        frameCount: 96,
        range: span(0, 95),
        width: TransportBar.minimumWidth,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(k('play')), findsOneWidget);
      expect(find.byKey(k('in')), findsOneWidget);
    });

    testWidgets('narrower than its buttons, the play row scales rather than '
        'overflow', (tester) async {
      await pump(tester, frameCount: 96, width: 90);
      expect(tester.takeException(), isNull);
      final bar = tester.getRect(find.byType(TransportBar));
      final first = tester.getRect(find.byKey(k('first')));
      final last = tester.getRect(find.byKey(k('last')));
      expect(first.left, greaterThanOrEqualTo(bar.left));
      expect(last.right, lessThanOrEqualTo(bar.right));
    });
  });
}

void _ignore() {}

void _ignoreFrame(int frame) {}

void _ignoreRange(int inFrame, int outFrame) {}
