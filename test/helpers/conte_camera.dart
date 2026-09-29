import 'dart:ui' show Offset, Rect, Size;

import 'package:anicel/src/models/conte/conte_sheet_source.dart';

/// A camera that moves [across] screens right and [down] screens down from
/// its first key to its last — the first key's frame at the canvas origin —
/// as a cell's camera work: two framed keys, called [first] and [last].
ConteCameraWork conteCameraPan({
  double across = 0,
  double down = 0,
  Size screen = const Size(1920, 1080),
  String first = 'IN',
  String last = 'OUT',
}) {
  List<Offset> frameAt(Offset topLeft) => [
    topLeft,
    topLeft + Offset(screen.width, 0),
    topLeft + Offset(screen.width, screen.height),
    topLeft + Offset(0, screen.height),
  ];
  final start = frameAt(Offset.zero);
  final end = frameAt(
    Offset(across * screen.width, down * screen.height),
  );
  return ConteCameraWork(
    screen: screen,
    field: Rect.fromPoints(start.first, end[2]),
    keys: [
      ConteCameraKey(
        corners: start,
        role: ConteCameraKeyRole.first,
        label: first,
      ),
      ConteCameraKey(corners: end, role: ConteCameraKeyRole.last, label: last),
    ],
    trails: [
      for (var corner = 0; corner < 4; corner += 1) [start[corner], end[corner]],
    ],
  );
}
