import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/input/pencil_interaction_service.dart';

/// PEN-5: the Apple Pencil double-tap channel consumer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(PencilInteractionService.instance.debugReset);

  Future<void> sendPencilTap(Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          PencilInteractionService.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('pencilTap', arguments),
          ),
          (_) {},
        );
  }

  test('maps the runner actions and treats unknown names as ignore', () async {
    final received = <PencilTapAction>[];
    PencilInteractionService.instance
      ..bind(force: true)
      ..onPencilTap = received.add;

    await sendPencilTap(const {'action': 'switchEraser'});
    await sendPencilTap(const {'action': 'switchPrevious'});
    await sendPencilTap(const {'action': 'showColorPalette'});
    await sendPencilTap(const {'action': 'somethingFromTheFuture'});
    await sendPencilTap(const <String, Object>{});
    await sendPencilTap(null);

    expect(received, const [
      PencilTapAction.switchEraser,
      PencilTapAction.switchPrevious,
      PencilTapAction.showColorPalette,
      PencilTapAction.ignore,
      PencilTapAction.ignore,
      PencilTapAction.ignore,
    ]);
  });

  test('unbound platforms never install a handler', () async {
    // Not iOS and not forced: bind is a no-op, taps fall on the floor.
    final received = <PencilTapAction>[];
    PencilInteractionService.instance
      ..bind()
      ..onPencilTap = received.add;
    await sendPencilTap(const {'action': 'switchEraser'});
    expect(received, isEmpty);
  });
}
