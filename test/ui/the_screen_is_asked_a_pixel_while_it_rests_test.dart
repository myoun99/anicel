import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/lost_screen.dart';
import 'package:anicel/src/native/qa_display_timing.dart';
import 'package:anicel/src/ui/look_only_frames.dart';
import 'package:anicel/src/ui/playback/looking_ticker.dart';
import 'package:anicel/src/ui/present_pacing.dart';
import 'package:anicel/src/ui/raster_watch.dart';
import 'package:anicel/src/ui/screen_canary.dart';

/// The test binding with the PRODUCTION mixins a playback's frames go
/// through — looks, not drawn where they change nothing, and its clock
/// counted — in the order the app's binding wears them (`AnicelBinding`),
/// on a display that says nothing, as one may.
class _CanaryBinding extends AutomatedTestWidgetsFlutterBinding
    with LookOnlyFrames, PresentPacing {
  @override
  DisplayTiming? get displayTiming => null;
}

/// 🗣️a-real-gpu-reset-went-unheard-on-the-main-pc-Q1 (유저 2026-11-22):
/// 「앱이 화면용 컨텍스트로 1픽셀을 그려 되읽는다 — 처음엔 기록만」 —
/// [ScreenCanary]: while the screen rests, the runner's watch is asked and
/// then a pixel of the screen's own context, and one not said back is
/// said once.
///
/// ⚠️A context whose device went is not one this suite has: the pixel is
/// drawn here by a stand-in saying what such a context is read to say, and
/// the draw the app makes is pinned on a context that stands.
void main() {
  _CanaryBinding();

  late DateTime now;

  /// What the runner's watch says each time it is asked, and whether a
  /// runner watches at all — on a platform where none does, no one hears
  /// the asking.
  late bool? Function() runnerSays;
  late bool runnerWatches;

  /// What a context gives back for a pixel of a colour.
  late Future<Uint8List> Function(int argb) context;

  /// What was asked, in order: `runner`, and `draw` with the colour.
  late List<String> asked;

  String drawOf(int asking) => 'draw ${ScreenCanary.colorOf(asking)}';

  setUp(() {
    now = DateTime(2026, 11, 22, 16, 47);
    runnerSays = () => true;
    runnerWatches = true;
    context = (argb) async => ScreenCanary.bytesOf(argb);
    asked = [];
    ScreenCanary.debugClockOverride = () => now;
    RasterWatch.debugClockOverride = () => now;
    ScreenCanary.debugDrawOverride = (argb) {
      asked.add('draw $argb');
      return context(argb);
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LostScreen.channel, (call) async {
          asked.add(
            call.method == LostScreen.standsMethod ? 'runner' : call.method,
          );
          return runnerWatches
              ? runnerSays()
              : throw MissingPluginException();
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LostScreen.channel, null);
      ScreenCanary.debugForget();
      ScreenCanary.debugClockOverride = null;
      ScreenCanary.debugDrawOverride = null;
      RasterWatch.debugForget();
      RasterWatch.debugClockOverride = null;
      LostScreen.debugForget();
    });
  });

  test('the runner\'s watch is asked first, and a pixel drawn only where it '
      'says its device stands — another colour each asking, one asking at '
      'a time', () async {
    runnerSays = () => false;
    await ScreenCanary.ask();
    expect(asked, ['runner'], reason: 'its device went, or it holds none');
    runnerSays = () => null;
    await ScreenCanary.ask();
    expect(asked, ['runner', 'runner'], reason: 'no word vouches for none');

    asked.clear();
    runnerSays = () => true;
    await ScreenCanary.ask();
    expect(asked, ['runner', drawOf(1)]);
    expect(ScreenCanary.notSaid.value, isNull, reason: 'said back as asked');

    await ScreenCanary.ask();
    expect(asked.sublist(2), ['runner', drawOf(2)]);
    expect(drawOf(2), isNot(drawOf(1)));

    // Asked again while one asking is under way: that one is the asking.
    asked.clear();
    final under = ScreenCanary.ask();
    await ScreenCanary.ask();
    await under;
    expect(asked, ['runner', drawOf(3)]);
  });

  test('a pixel read back as another is said — what was asked, what came, '
      'and when — and no other is asked this run', () async {
    context = (argb) async => Uint8List(4);
    await ScreenCanary.ask();
    expect(ScreenCanary.notSaid.value, (
      asked: '3779b1ff',
      instead: 'read 00000000',
      askedAt: now,
    ));

    asked.clear();
    await ScreenCanary.ask();
    expect(asked, isEmpty, reason: 'once a run');
  });

  test('a draw that fails is said with why', () async {
    context = (argb) => Future.error(StateError('the context is lost'));
    await ScreenCanary.ask();
    expect(
      ScreenCanary.notSaid.value?.instead,
      'failed: Bad state: the context is lost',
    );
  });

  testWidgets('a pixel not said back within the raster watch\'s patience is '
      'said — and one a timer far later than it was set for found is not: '
      'the machine stood still, no context did', (tester) async {
    Future<void> settle() async {
      for (var turn = 0; turn < 3; turn += 1) {
        await tester.pump();
      }
    }

    // What will not come.
    context = (argb) => Completer<Uint8List>().future;

    unawaited(ScreenCanary.ask());
    await settle();
    expect(asked, ['runner', drawOf(1)]);
    // The timer comes, and the clock says three waits went by.
    now = now.add(RasterWatch.patience * 3);
    await tester.pump(RasterWatch.patience);
    await settle();
    expect(ScreenCanary.notSaid.value, isNull, reason: 'a sleep, a debugger');

    final askedAt = now;
    unawaited(ScreenCanary.ask());
    await settle();
    expect(asked.sublist(2), ['runner', drawOf(2)], reason: 'asked again');
    now = now.add(RasterWatch.patience);
    await tester.pump(RasterWatch.patience);
    await settle();
    expect(ScreenCanary.notSaid.value, (
      asked: ScreenCanary.bytesOf(ScreenCanary.colorOf(2))
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
      instead: 'nothing in ${RasterWatch.patience.inSeconds} s',
      askedAt: askedAt,
    ));
  });

  test('while frames are handed over nothing is asked, the runner neither — '
      'only once none was for the rest', () async {
    RasterWatch.handedOver(7);
    now = now.add(ScreenCanary.rest);
    await ScreenCanary.ask();
    expect(asked, isEmpty, reason: 'a frame within the rest');

    now = now.add(const Duration(milliseconds: 1));
    await ScreenCanary.ask();
    expect(asked, ['runner', drawOf(1)]);
  });

  // 🗣️The option chosen, its third cost (Q1, 유저 2026-11-22): 「재생
  // 중에는 프레임을 밀까 봐 안 묻는다」. A playback holding one picture
  // draws no frame, so the frame watch alone reads its hold as a rest.
  testWidgets('while a playback runs nothing is asked, the runner neither — '
      'though its frames change nothing and none is drawn', (tester) async {
    Future<void> settle() async {
      for (var turn = 0; turn < 3; turn += 1) {
        await tester.pump();
      }
    }

    final playback = LookingTicker((_) {})..start(tester);
    addTearDown(playback.stop);
    await settle();
    expect(
      RasterWatch.handedOverAt,
      DateTime(0),
      reason: '⛔premise: by the frame watch\'s count, the screen rests',
    );

    unawaited(ScreenCanary.ask());
    await settle();
    expect(asked, isEmpty, reason: 'a playback runs');

    playback.stop();
    unawaited(ScreenCanary.ask());
    await settle();
    expect(asked, ['runner', drawOf(1)], reason: 'LIVENESS — it stopped');
  });

  test('a screen its watch said gone is asked nothing', () async {
    LostScreen.debugGo();
    await ScreenCanary.ask();
    expect(asked, isEmpty);
  });

  testWidgets('installed, it asks every so often for the run — once, however '
      'often installed — and where no runner watches, never again', (
    tester,
  ) async {
    Future<void> after(Duration time) async {
      await tester.pump(time);
      for (var turn = 0; turn < 3; turn += 1) {
        await tester.pump();
      }
    }

    ScreenCanary.install();
    ScreenCanary.install();
    await after(ScreenCanary.every - const Duration(milliseconds: 1));
    expect(asked, isEmpty);
    await after(const Duration(milliseconds: 1));
    expect(asked, ['runner', drawOf(1)]);
    await after(ScreenCanary.every);
    expect(asked.sublist(2), ['runner', drawOf(2)]);

    asked.clear();
    runnerWatches = false;
    await after(ScreenCanary.every);
    expect(asked, ['runner'], reason: 'no runner watches here');
    await after(ScreenCanary.every * 3);
    expect(asked, ['runner'], reason: 'and none will: the asking ends');

    // A timer may not outlive the test's body.
    ScreenCanary.debugForget();
  });

  test('main installs it before the app is run', () {
    final source = File('lib/main.dart').readAsStringSync();
    final (installed, run) = (
      source.indexOf('ScreenCanary.install();'),
      source.indexOf('runApp('),
    );
    expect(installed, isNonNegative, reason: 'main installs it');
    expect(installed, lessThan(run));
  });

  testWidgets('🎯a context that stands says back the pixel asked of it — the '
      'draw the app makes, with no stand-in', (tester) async {
    for (final argb in [
      ScreenCanary.colorOf(1),
      ScreenCanary.colorOf(2),
      0xFF000000,
      0xFFFFFFFF,
    ]) {
      expect(
        await tester.runAsync(() => ScreenCanary.readBack(argb)),
        ScreenCanary.bytesOf(argb),
        reason: 'a pixel of 0x${argb.toRadixString(16)}',
      );
    }
  });
}
