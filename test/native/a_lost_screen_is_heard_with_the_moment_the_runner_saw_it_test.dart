import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/lost_screen.dart';

/// H63 ③ (관제 2026-11-18): the runner says the screen's device went with
/// the reason Windows gave AND the moment its watch saw it — the log the
/// app writes is stamped when the app hears it, and the channel and the UI
/// thread lie between the two.
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

  /// What the Windows runner says once its watch saw the device go:
  /// [reason] as an int32 and [seenAt] in milliseconds since 1970 UTC.
  Future<void> runnerSays(int reason, int seenAt) =>
      messenger.handlePlatformMessage(
        LostScreen.channel.name,
        LostScreen.channel.codec.encodeMethodCall(
          MethodCall(LostScreen.wentMethod, [reason, seenAt]),
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
    ));
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
}
