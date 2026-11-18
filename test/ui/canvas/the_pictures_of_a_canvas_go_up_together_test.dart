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
