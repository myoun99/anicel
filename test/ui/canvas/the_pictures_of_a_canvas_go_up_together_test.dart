import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/canvas/picture_up_view.dart';

/// 🚨★★★THE PICTURES OF ONE CANVAS GO UP TOGETHER ([PicturesUpTogether]):
/// a frame the GPU has finished goes up once every other frame of the
/// canvas's pictures being drawn meanwhile has finished too, or failed.
///
/// 🗣️관제 2026-11-16 (a-pan-moves-the-overlays-before-the-canvas (ㄱ)): 「덮는
/// 어니언 = 묶는다」.
void main() {
  /// Whether [up] has ended, once what is due has run.
  Future<bool> isUp(Future<void> up) async {
    var ended = false;
    unawaited(up.then((_) => ended = true, onError: (Object _) {}));
    await pumpEventQueue();
    return ended;
  }

  test('a frame drawn alone goes up as it finishes', () async {
    final together = PicturesUpTogether();
    final done = Completer<void>();

    final up = together.joined(done.future);
    expect(await isUp(up), isFalse, reason: 'up before it finished');
    done.complete();

    expect(await isUp(up), isTrue);
  });

  test('🚨a frame finished waits for the one drawn beside it, and they go '
      'up together', () async {
    final together = PicturesUpTogether();
    final (frame, ghosts) = (Completer<void>(), Completer<void>());
    final frameUp = together.joined(frame.future);
    final ghostsUp = together.joined(ghosts.future);

    frame.complete();
    expect(await isUp(frameUp), isFalse);

    ghosts.complete();
    expect(await isUp(frameUp), isTrue);
    expect(await isUp(ghostsUp), isTrue);
  });

  test('a frame that fails lets the rest go up, and is told so', () async {
    final together = PicturesUpTogether();
    final (frame, ghosts) = (Completer<void>(), Completer<void>());
    final frameUp = together.joined(frame.future);
    final ghostsUp = together.joined(ghosts.future);
    Object? told;
    unawaited(ghostsUp.catchError((Object error) => told = error));

    frame.complete();
    ghosts.completeError(StateError('the GPU past its limit'));

    expect(await isUp(frameUp), isTrue);
    await pumpEventQueue();
    expect(told, isA<StateError>());
  });

  group('the frames being drawn, as one (what a stroke\'s step waits for)', () {
    test('are none where no frame is being drawn', () async {
      final together = PicturesUpTogether();
      expect(together.beingDrawn, isNull);

      final done = Completer<void>();
      unawaited(together.joined(done.future));
      expect(together.beingDrawn, isNotNull);
      done.complete();
      await pumpEventQueue();

      expect(together.beingDrawn, isNull, reason: 'none once it is up');
    });

    test('🚨end once every frame drawn is up — after each has gone '
        'up', () async {
      final together = PicturesUpTogether();
      final (frame, ghosts) = (Completer<void>(), Completer<void>());
      final order = <String>[];
      unawaited(together.joined(frame.future).then((_) => order.add('frame')));
      unawaited(
        together.joined(ghosts.future).then((_) => order.add('ghosts')),
      );
      final drawn = together.beingDrawn!;
      unawaited(drawn.then((_) => order.add('all')));

      frame.complete();
      expect(await isUp(drawn), isFalse, reason: 'the ghosts still drawn');
      ghosts.complete();

      expect(await isUp(drawn), isTrue);
      expect(order, ['frame', 'ghosts', 'all']);
    });

    test('end where the last of them fails', () async {
      final together = PicturesUpTogether();
      final (frame, ghosts) = (Completer<void>(), Completer<void>());
      unawaited(together.joined(frame.future));
      unawaited(together.joined(ghosts.future).catchError((Object _) {}));
      final drawn = together.beingDrawn!;

      frame.complete();
      ghosts.completeError(StateError('the GPU past its limit'));

      expect(await isUp(drawn), isTrue);
      expect(together.beingDrawn, isNull);
    });

    test('are the next frames\' alone once those are up', () async {
      final together = PicturesUpTogether();
      final first = Completer<void>();
      unawaited(together.joined(first.future));
      final drawnFirst = together.beingDrawn!;
      first.complete();
      expect(await isUp(drawnFirst), isTrue);

      final next = Completer<void>();
      unawaited(together.joined(next.future));
      final drawnNext = together.beingDrawn!;

      expect(await isUp(drawnNext), isFalse);
      next.complete();
      expect(await isUp(drawnNext), isTrue);
    });
  });

  test('once up, the next frame waits for none of those', () async {
    final together = PicturesUpTogether();
    final (frame, ghosts) = (Completer<void>(), Completer<void>());
    unawaited(together.joined(frame.future));
    unawaited(together.joined(ghosts.future));
    frame.complete();
    ghosts.complete();
    await pumpEventQueue();
    final next = Completer<void>();

    final up = together.joined(next.future);
    next.complete();

    expect(await isUp(up), isTrue);
  });
}
