import 'package:anicel/src/models/frame.dart' show InbetweenMark;

/// [offsets] each wearing [mark] — a block's `breakdownMarks` as a fixture
/// states it.
Map<int, InbetweenMark> dotsAt(
  Iterable<int> offsets, {
  InbetweenMark mark = InbetweenMark.two,
}) => {for (final offset in offsets) offset: mark};
