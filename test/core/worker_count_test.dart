import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/worker_count.dart';

/// [workersFor] — the one law every fan-out over isolates sizes itself by:
/// the brush roster's rasters, both import pools and the cel thaw.
void main() {
  test('one fewer than the cores — the UI isolate is one of them — never '
      'below one, never past the ceiling', () {
    for (final (cores, ceiling, workers) in [
      (1, 4, 1),
      (2, 4, 1),
      (4, 4, 3),
      (5, 4, 4),
      (20, 4, 4),
      (20, 8, 8),
      (6, 8, 5),
    ]) {
      expect(
        workersFor(cores, ceiling: ceiling),
        workers,
        reason: '$cores cores under a ceiling of $ceiling',
      );
    }
  });
}
