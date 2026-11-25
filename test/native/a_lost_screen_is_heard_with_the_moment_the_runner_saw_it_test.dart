import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/lost_screen.dart';

/// H63 ③ (관제 2026-11-18): the runner says the screen's device went with
/// the reason Windows gave AND the moment its watch saw it — the log the
/// app writes is stamped when the app hears it, and the channel and the UI
/// thread lie between the two.
///
/// And who said it is heard with it: the runner's watch, or — where the
/// engine is the one Anicel builds — the engine itself, whose word the
/// runner passes on (board a-real-gpu-reset-went-unheard-on-the-main-pc,
/// 2026-11-23). The two say one loss.
///
/// Here the channel is the runner, and says what the runner says; that the
/// runner does say it is `a_lost_screen_is_heard_from_the_runner_test`'s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    LostScreen.listen();
    addTearDown(() {
      messenger.setMockMethodCallHandler(LostScreen.channel, null);
      LostScreen.debugForget();
    });
  });

  /// What the Windows runner says by [method] — once its watch saw the
  /// device go, unless another is named: [reason] as an int32 and [seenAt]
  /// in milliseconds since 1970 UTC.
  Future<void> runnerSays(
    int reason,
    int seenAt, [
    String method = LostScreen.wentMethod,
  ]) => messenger.handlePlatformMessage(
    LostScreen.channel.name,
    LostScreen.channel.codec.encodeMethodCall(
      MethodCall(method, [reason, seenAt]),
    ),
    (_) {},
  );

  test('the reason and the moment the runner saw it are heard '
      'together', () async {
    expect(LostScreen.hasGone, isFalse, reason: '⛔전제: nothing went yet');
    const seenAt = 1795000000123;

    await runnerSays(0x887A0006.toSigned(32), seenAt);

    expect(LostScreen.went.value, (
      reason: 0x887A0006.toSigned(32),
      seenAt: DateTime.fromMillisecondsSinceEpoch(seenAt),
      by: ScreenGoneBy.watch,
    ));
  });

  test('the engine\'s own word is heard as the engine\'s, with the EGL '
      'error it failed by and the moment the runner heard it', () async {
    expect(LostScreen.hasGone, isFalse, reason: '⛔전제: nothing went yet');
    const heardAt = 1795000000456;
    // EGL_CONTEXT_LOST.
    const lost = 0x300E;

    await runnerSays(lost, heardAt, LostScreen.contextLostMethod);

    expect(LostScreen.went.value, (
      reason: lost,
      seenAt: DateTime.fromMillisecondsSinceEpoch(heardAt),
      by: ScreenGoneBy.engine,
    ));
    expect(LostScreen.hasGone, isTrue);
  });

  test('the engine and the watch say one loss: whichever says it first '
      'is the one kept', () async {
    await runnerSays(0x300E, 1795000000456, LostScreen.contextLostMethod);
    await runnerSays(0x887A0006.toSigned(32), 1795000000999);
    expect(LostScreen.went.value?.by, ScreenGoneBy.engine);
    expect(LostScreen.went.value?.reason, 0x300E);

    LostScreen.debugForget();
    await runnerSays(0x887A0006.toSigned(32), 1795000000999);
    await runnerSays(0x300E, 1795000001456, LostScreen.contextLostMethod);
    expect(LostScreen.went.value?.by, ScreenGoneBy.watch);
    expect(LostScreen.went.value?.reason, 0x887A0006.toSigned(32));
  });

  // 🗣️Q1, 11-23 20:40: the pixel the screen did not say back, passed on by
  // the runner as a loss.
  test('the app\'s own pixel not said back, said again by the runner, is '
      'heard as the pixel\'s — no system gave a reason', () async {
    const askedAt = 1795000000789;

    await runnerSays(0, askedAt, LostScreen.pixelNotSaidMethod);

    expect(LostScreen.went.value, (
      reason: 0,
      seenAt: DateTime.fromMillisecondsSinceEpoch(askedAt),
      by: ScreenGoneBy.pixel,
    ));
  });

  test('what the runner says by another name is no loss', () async {
    await runnerSays(0x300E, 1795000000456, LostScreen.standsMethod);

    expect(LostScreen.hasGone, isFalse);
  });

  test('the first loss a run hears is the one it keeps', () async {
    await runnerSays(0x887A0006.toSigned(32), 1795000000123);
    await runnerSays(0x887A0007.toSigned(32), 1795000009999);

    expect(LostScreen.went.value?.reason, 0x887A0006.toSigned(32));
    expect(
      LostScreen.went.value?.seenAt,
      DateTime.fromMillisecondsSinceEpoch(1795000000123),
    );
  });

  // Step two (board a-real-gpu-reset-went-unheard-on-the-main-pc): where the
  // engine restores, the runner says the loss only as part of its answer.
  /// What the runner says once the engine stood again: the word it held —
  /// said by [saidBy] — and the moment it stood.
  Future<void> runnerSaysItStoodAgain(
    int reason,
    int seenAt,
    String saidBy,
    int stoodAt,
  ) => messenger.handlePlatformMessage(
    LostScreen.channel.name,
    LostScreen.channel.codec.encodeMethodCall(
      MethodCall(LostScreen.contextRestoredMethod, [
        reason,
        seenAt,
        saidBy,
        stoodAt,
      ]),
    ),
    (_) {},
  );

  test('a screen that stood again is heard with the loss as it would have '
      'been said and the moment it stood — and is no loss', () async {
    expect(LostScreen.stoodAgain.value, isNull, reason: '⛔전제: none yet');

    await runnerSaysItStoodAgain(
      0x887A0006.toSigned(32),
      1795000000123,
      LostScreen.wentMethod,
      1795000000456,
    );

    expect(LostScreen.stoodAgain.value, (
      lost: (
        reason: 0x887A0006.toSigned(32),
        seenAt: DateTime.fromMillisecondsSinceEpoch(1795000000123),
        by: ScreenGoneBy.watch,
      ),
      stoodAt: DateTime.fromMillisecondsSinceEpoch(1795000000456),
    ));
    expect(LostScreen.hasGone, isFalse);
  });

  test('each time it stands again is heard, the engine\'s word as the '
      'engine\'s', () async {
    final heard = <ScreenStoodAgain?>[];
    void hear() => heard.add(LostScreen.stoodAgain.value);
    LostScreen.stoodAgain.addListener(hear);
    addTearDown(() => LostScreen.stoodAgain.removeListener(hear));

    await runnerSaysItStoodAgain(
      0x300E,
      1795000000123,
      LostScreen.contextLostMethod,
      1795000000456,
    );
    await runnerSaysItStoodAgain(
      0x300E,
      1795000009000,
      LostScreen.contextLostMethod,
      1795000009500,
    );

    expect(heard.map((each) => each?.lost.by), [
      ScreenGoneBy.engine,
      ScreenGoneBy.engine,
    ]);
    expect(
      heard.map((each) => each?.stoodAt.millisecondsSinceEpoch),
      [1795000000456, 1795000009500],
    );
  });

  test('a stand again said of a word that says no loss is not '
      'heard', () async {
    await runnerSaysItStoodAgain(
      0x300E,
      1795000000123,
      LostScreen.standsMethod,
      1795000000456,
    );

    expect(LostScreen.stoodAgain.value, isNull);
  });
}
