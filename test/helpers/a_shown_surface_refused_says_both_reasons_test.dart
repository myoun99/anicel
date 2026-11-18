import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'a_shown_surface.dart';

/// What a test's shown surface says when the platform refuses it (board
/// ci-linux-shards-cannot-make-a-shown-surface): the first refusal was
/// dropped, and the second — always the same on Linux — read as the cause.
void main() {
  test('refused both ways, the refusal names what was asked and both '
      'reasons', () {
    Never refuse({required bool bgra}) => throw GpuRefused(
      bgra ? 'BGRA is never shown here' : 'past the buffer limit',
    );
    expect(
      () => shownOf<String>(refuse, '5120 × 3584'),
      throwsA(
        isA<GpuRefused>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('5120 × 3584'),
            contains('RGBA: past the buffer limit'),
            contains('BGRA: BGRA is never shown here'),
          ),
        ),
      ),
    );
  });

  test('RGBA is asked first, and BGRA only when RGBA is refused', () {
    final asked = <bool>[];
    String rgbaMade({required bool bgra}) {
      asked.add(bgra);
      return bgra ? 'bgra' : 'rgba';
    }

    expect(shownOf(rgbaMade, 'x'), 'rgba');
    expect(asked, [false]);

    asked.clear();
    String bgraOnly({required bool bgra}) {
      asked.add(bgra);
      if (!bgra) throw GpuRefused('Apple makes BGRA alone');
      return 'bgra';
    }

    expect(shownOf(bgraOnly, 'x'), 'bgra');
    expect(asked, [false, true]);
  });
}
