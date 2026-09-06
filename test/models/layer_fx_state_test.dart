import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';

/// Whether a row's FX apply, read off its master state: only OFF means no.
/// The session, the grid hooks and the storyboard's rail rows each spelled
/// `state != LayerFxState.off` with a null-means-on default (the audit's
/// clone scan, 2026-09-06).
void main() {
  test('on and mixed apply, off does not', () {
    expect(fxEnabledFromState(LayerFxState.on), isTrue);
    expect(fxEnabledFromState(LayerFxState.mixed), isTrue);
    expect(fxEnabledFromState(LayerFxState.off), isFalse);
  });

  test('no answer at all reads as applied — a host that hides the master '
      'has nothing bypassed', () {
    expect(fxEnabledFromState(null), isTrue);
  });
}
