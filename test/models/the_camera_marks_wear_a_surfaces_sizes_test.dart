import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_work_marks.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/ui/conte/conte_fonts.dart' show conteTextStyle;

/// One drawing for a camera's work (`camera_work_marks.dart`): every surface
/// says how large it writes it — the conte in points on its paper, the
/// canvas in screen pixels — and each of those sizes goes to its own mark.
void main() {
  /// Every size apart from every other, so a size given to the wrong mark
  /// shows.
  const sizes = CameraMarkSizes(
    frameWidth: 1.8,
    trailWidth: 1.4,
    labelSize: 12,
    crossArm: 5,
    crossWidth: 1.6,
    labelInset: 4,
  );

  /// A 160×90 frame with its top-left corner at (100, 50).
  const corners = [
    Offset(100, 50),
    Offset(260, 50),
    Offset(260, 140),
    Offset(100, 140),
  ];

  List<SheetMark> marksOf(String label) => cameraWorkMarks(
    trails: const [
      [Offset.zero, Offset(40, 0), Offset(80, 0)],
    ],
    keys: [
      CameraMarkedKey(
        corners: corners,
        role: CameraKeyRole.first,
        label: label,
      ),
    ],
    sizes: sizes,
    layer: SheetPaintLayer.picture,
  ).toList();

  test('each of a surface\'s sizes goes to its own mark: the trail\'s line, '
      'the frame\'s, a cross\'s arms and their line, and the label\'s '
      'letters, bold', () {
    final marks = marksOf('A');
    final strokes = marks.whereType<SheetStroke>().toList();
    final trail = strokes.firstWhere((stroke) => stroke.points.length == 3);
    expect(trail.width, sizes.trailWidth);
    final frame = strokes.singleWhere((stroke) => stroke.closed);
    expect(frame.width, sizes.frameWidth);
    final arms = [
      for (final stroke in strokes)
        if (stroke.points.length == 2) stroke,
    ];
    expect(arms, hasLength(2));
    for (final arm in arms) {
      expect(arm.width, sizes.crossWidth);
      expect((arm.points[1] - arm.points[0]).distance, 2 * sizes.crossArm);
    }
    final label = marks.whereType<SheetWords>().single;
    expect(label.size, sizes.labelSize);
    expect(label.bold, isTrue);
  });

  test('a label stands inside its frame\'s top-left corner by the inset, '
      'kept off the frame\'s far side by it as well, and its slot holds a '
      'line of the face the sheets print in — no letter is cut', () {
    final label = marksOf(
      'A long name for a key',
    ).whereType<SheetWords>().single;
    expect(label.slot.left, corners[0].dx + sizes.labelInset);
    expect(label.slot.top, corners[0].dy + sizes.labelInset);
    expect(label.slot.right, corners[1].dx - sizes.labelInset);
    final line = conteTextStyle(sizes.labelSize).height! * sizes.labelSize;
    expect(label.slot.height, greaterThanOrEqualTo(line));
  });

  test('a surface\'s sizes in another\'s units are each of them that many '
      'times over, each still its own', () {
    final twice = sizes.scaledBy(2);
    expect(
      [
        twice.frameWidth,
        twice.trailWidth,
        twice.labelSize,
        twice.crossArm,
        twice.crossWidth,
        twice.labelInset,
      ],
      [3.6, 2.8, 24, 10, 3.2, 8],
    );
  });
}
