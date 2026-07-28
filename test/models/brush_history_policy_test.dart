import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_history_policy.dart';

void main() {
  group('BrushHistoryPolicy', () {
    test('computes deferred bake limit from user undo limit and ratio', () {
      const policy = BrushHistoryPolicy(
        userUndoLimit: 250,
        deferredBakeRatio: 0.10,
        minimumDeferredBakeBuffer: 16,
      );

      expect(policy.deferredBakeLimit, 25);
    });

    test('uses minimum deferred bake buffer as a floor', () {
      const policy = BrushHistoryPolicy(
        userUndoLimit: 20,
        deferredBakeRatio: 0.10,
        minimumDeferredBakeBuffer: 16,
      );

      expect(policy.deferredBakeLimit, 16);
    });
  });
}
