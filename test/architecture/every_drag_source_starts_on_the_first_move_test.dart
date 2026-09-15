import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// ⛔Every drag SOURCE under `lib/src/ui` is an `OwningDraggable`.
///
/// F-126 (유저 2026-09-13: 「패널을 드래그 해서 위치 움직이는 패널탭 띠,
/// 마우스로는 움직여서 패널 위치 도킹가능한데 펜으로는 불가능. 이유 확인해서
/// 법 통일」). A stock `Draggable` waits for a distance that depends on the
/// device — one pixel for a mouse, eighteen for a pen — so the same drag starts
/// for one and loses to a press claim or a scroller for the other.
///
/// ⚠️WHY THE SOURCE AND NOT A DRAG: every drag test in the suite reached its
/// target in one long hop, and a first move longer than any slop starts every
/// recogniser at once. That is how the panel tab's grip passed all of them
/// while a pen could not lift it.
void main() {
  test('no stock Draggable or LongPressDraggable under lib/src/ui', () {
    // The one home: it IS the subclass, so it names its parent.
    const home = 'lib/src/ui/widgets/owning_draggable.dart';
    final stock = RegExp('(?<![A-Za-z])(LongPress)?Draggable<');
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib/src/ui')) {
      final path = libPath(file);
      if (path == home) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) {
          continue;
        }
        if (stock.hasMatch(line)) {
          offenders.add('$path:${i + 1}  $line');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'use OwningDraggable — a stock Draggable starts for a mouse and '
          'waits eighteen pixels for a pen',
    );
  });
}
