import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';

import '../helpers/conte_camera.dart';

/// A cell whose camera moves, as the conte prints it (유저 2026-09-29/30): the
/// canvas the camera sweeps, the trail each corner of its frame draws, the
/// first and last frames in IN's green and OUT's red, and each key's name
/// at its frame's top-left corner.
void main() {
  const metrics = ConteSheetMetrics();
  const green = 0xFF3B6D11;
  const red = 0xFFA32D2D;

  /// The page of [cells], a cut each, and every mark it prints.
  ({ContePageLayout page, List<SheetMark> marks}) printed(
    List<ConteCellSource> cells,
  ) {
    final source = ConteSheetSource(
      framesPerSecond: 24,
      cuts: [
        for (final (index, cell) in cells.indexed)
          ConteCutSource(
            cutId: CutId('$index'),
            name: '$index',
            durationFrames: 24,
            cumulativeEndFrames: 24 * (index + 1),
            cells: [cell],
          ),
      ],
    );
    final page = layoutConteSheet(source, metrics: metrics).first;
    return (
      page: page,
      marks: contePageMarks(page, source, words: conteWordsIn(AppLanguage.ja)),
    );
  }

  ConteCellSource still() => const ConteCellSource(
    startFrame: 0,
    endFrameExclusive: 24,
    pictureFrame: 0,
  );

  ConteCellSource moving(ConteCameraWork work) => ConteCellSource(
    startFrame: 0,
    endFrameExclusive: 24,
    pictureFrame: 0,
    camera: work,
  );

  void expectPoint(Offset actual, Offset expected, String reason) {
    expect(actual.dx, closeTo(expected.dx, 1e-9), reason: reason);
    expect(actual.dy, closeTo(expected.dy, 1e-9), reason: reason);
  }

  /// [work]'s canvas point [point] where [picture] lays it on the paper.
  Offset onPaper(SheetPicture picture, ConteCameraWork work, Offset point) {
    final scale = picture.frame.width / work.field.width;
    return picture.frame.topLeft + (point - work.field.topLeft) * scale;
  }

  test('a camera that holds still writes nothing on its picture', () {
    final marks = printed([still()]).marks;
    expect(marks.whereType<SheetStroke>(), isEmpty);
    expect(
      marks.whereType<SheetWords>().where(
        (words) => words.layer == SheetPaintLayer.picture,
      ),
      isEmpty,
    );
  });

  test('the picture shows the canvas the camera sweeps, and the first key\'s '
      'frame is drawn in green and the last\'s in red, each where the '
      'picture shows it', () {
    final work = conteCameraPan(across: 0.3);
    final marks = printed([moving(work)]).marks;
    final picture = marks.whereType<SheetPicture>().single;
    expect(picture.canvasRegion, work.field);
    final frames = [
      for (final stroke in marks.whereType<SheetStroke>())
        if (stroke.closed) stroke,
    ];
    expect(frames.map((frame) => frame.argb), [green, red]);
    for (final (frame, key) in [
      (frames.first, work.keys.first),
      (frames.last, work.keys.last),
    ]) {
      expect(frame.layer, SheetPaintLayer.picture);
      for (final (index, corner) in key.corners.indexed) {
        expectPoint(
          frame.points[index],
          onPaper(picture, work, corner),
          'corner $index of the ${key.label} frame',
        );
      }
    }
    expectPoint(
      frames.first.points.first,
      picture.frame.topLeft,
      'the pan starts at the swept canvas\'s left',
    );
    expectPoint(
      frames.last.points[2],
      picture.frame.bottomRight,
      'and ends at its right',
    );
  });

  test('each corner of the frame draws its own trail, key to key — four '
      'lines, never one through the middle (「궤도는 중앙이아니라 각 꼭짓점 4개 '
      '전부야」) — under the frames', () {
    final work = conteCameraPan(across: 0.3, down: 0.5);
    final marks = printed([moving(work)]).marks;
    final picture = marks.whereType<SheetPicture>().single;
    final strokes = marks.whereType<SheetStroke>().toList();
    final trails = [
      for (final stroke in strokes)
        if (!stroke.closed) stroke,
    ];
    expect(trails, hasLength(4));
    for (final (corner, trail) in trails.indexed) {
      expect(trail.points, hasLength(2));
      expectPoint(
        trail.points.first,
        onPaper(picture, work, work.keys.first.corners[corner]),
        'trail $corner starts at the first frame\'s corner $corner',
      );
      expectPoint(
        trail.points.last,
        onPaper(picture, work, work.keys.last.corners[corner]),
        'and ends at the last frame\'s',
      );
    }
    expect(
      strokes.indexWhere((stroke) => stroke.closed),
      greaterThan(strokes.lastIndexWhere((stroke) => !stroke.closed)),
      reason: 'the frames print over the trails',
    );
  });

  test('a key between draws no frame (「첫/끝 키 말고 중간키는 실루엣을 '
      '안그려」), and its name stands where its frame\'s corner would be '
      '(「원래 위치해야할곳에 위치시키고 틀만 안보이게」)', () {
    List<Offset> frameAt(double x) => [
      Offset(x, 0),
      Offset(x + 1920, 0),
      Offset(x + 1920, 1080),
      Offset(x, 1080),
    ];
    final corners = [frameAt(0), frameAt(960), frameAt(1920)];
    final work = ConteCameraWork(
      screen: const Size(1920, 1080),
      field: const Rect.fromLTRB(0, 0, 3840, 1080),
      keys: [
        ConteCameraKey(
          corners: corners[0],
          role: ConteCameraKeyRole.first,
          label: 'IN',
        ),
        ConteCameraKey(
          corners: corners[1],
          role: ConteCameraKeyRole.between,
          label: 'B',
        ),
        ConteCameraKey(
          corners: corners[2],
          role: ConteCameraKeyRole.last,
          label: 'OUT',
        ),
      ],
      trails: [
        for (var corner = 0; corner < 4; corner += 1)
          [for (final frame in corners) frame[corner]],
      ],
    );
    final marks = printed([moving(work)]).marks;
    final picture = marks.whereType<SheetPicture>().single;
    expect(
      marks.whereType<SheetStroke>().where((stroke) => stroke.closed),
      hasLength(2),
      reason: 'the first and the last frames only',
    );
    final between = marks.whereType<SheetWords>().singleWhere(
      (words) => words.text == 'B',
    );
    expectPoint(
      between.slot.topLeft,
      onPaper(picture, work, corners[1].first) + const Offset(2, 2),
      'inside the corner its frame would have',
    );
    expect(between.argb, isNot(anyOf(green, red)));
  });

  test('every name stands inside its frame\'s top-left corner and turns with '
      'the frame (「기운 틀의 모서리. 각도 그대로따라감」) — a name the first '
      'key has takes IN\'s green', () {
    const turn = math.pi / 6;
    List<Offset> turned(Offset centre) => [
      for (final corner in const [
        Offset(-960, -540),
        Offset(960, -540),
        Offset(960, 540),
        Offset(-960, 540),
      ])
        centre +
            Offset(
              corner.dx * math.cos(turn) - corner.dy * math.sin(turn),
              corner.dx * math.sin(turn) + corner.dy * math.cos(turn),
            ),
    ];
    final first = turned(const Offset(1500, 1000));
    final last = turned(const Offset(2500, 1000));
    final work = ConteCameraWork(
      screen: const Size(1920, 1080),
      field: const Rect.fromLTRB(0, 0, 4000, 2000),
      keys: [
        ConteCameraKey(
          corners: first,
          role: ConteCameraKeyRole.first,
          label: 'A',
        ),
        ConteCameraKey(
          corners: last,
          role: ConteCameraKeyRole.last,
          label: 'OUT',
        ),
      ],
      trails: [
        for (var corner = 0; corner < 4; corner += 1)
          [first[corner], last[corner]],
      ],
    );
    final marks = printed([moving(work)]).marks;
    final picture = marks.whereType<SheetPicture>().single;
    final labels = marks.whereType<SheetWords>().where(
      (words) => words.layer == SheetPaintLayer.picture,
    );
    expect(labels.map((words) => words.text), ['A', 'OUT']);
    for (final (label, corners, argb) in [
      (labels.first, first, green),
      (labels.last, last, red),
    ]) {
      expect(label.turn, closeTo(turn, 1e-9));
      expect(label.argb, argb);
      final inset =
          Offset(math.cos(turn), math.sin(turn)) * 2 +
          Offset(-math.sin(turn), math.cos(turn)) * 2;
      expectPoint(
        label.slot.topLeft,
        onPaper(picture, work, corners.first) + inset,
        '${label.text}: inside its frame\'s top-left corner, along its sides',
      );
    }
  });

  test('where its words moved under it, the picture column of that row is '
      'paper, ruled like the head — and footed on the page\'s last row', () {
    Iterable<SheetMark> wordsRowOf(List<SheetMark> marks, double top) =>
        marks.where(
          (mark) =>
              mark.layer == SheetPaintLayer.picture &&
              switch (mark) {
                SheetFill(:final rect) || SheetRule(:final rect) =>
                  rect.top >= top - 1e-9 && rect.right <= metrics.actionLeft,
                _ => false,
              },
        );

    final high = printed([moving(conteCameraPan(across: 0.9))]);
    final row = wordsRowOf(high.marks, metrics.rowTop(1)).toList();
    expect(
      row.whereType<SheetFill>().single.rect,
      Rect.fromLTRB(
        metrics.pictureLeft,
        metrics.rowTop(1),
        metrics.actionLeft,
        metrics.rowTop(2),
      ),
    );
    expect(row.whereType<SheetFill>().single.argb, 0xFFFFFFFF);
    expect(
      row.whereType<SheetRule>().map((rule) => (rule.isUpright, rule.hold)),
      [(true, SheetRuleHold.near), (true, SheetRuleHold.far)],
      reason: 'its two sides, the way the head rules the column',
    );

    final low = printed([
      still(),
      still(),
      still(),
      moving(conteCameraPan(across: 0.9)),
    ]);
    final foot = wordsRowOf(
      low.marks,
      metrics.rowTop(4),
    ).whereType<SheetRule>().where((rule) => !rule.isUpright);
    expect(
      foot.single.rect.bottom,
      closeTo(metrics.bodyBottom, 1e-9),
      reason: 'on the last row the black no longer closes the column',
    );
  });

  test('the length moves down with the words (「초수도 다음코마에 '
      '넣으면되니까」)', () {
    final sheet = printed([moving(conteCameraPan(across: 0.9))]);
    final total = sheet.marks.whereType<SheetWords>().singleWhere(
      (words) =>
          words.slot.left >= metrics.timeLeft &&
          words.slot.top >= metrics.bodyTop &&
          words.slot.top < metrics.bodyBottom &&
          words.text.isNotEmpty,
    );
    expect(total.slot.top, greaterThanOrEqualTo(metrics.rowTop(1)));
    final picture = sheet.marks.whereType<SheetPicture>().single;
    expect(
      picture.slot.right,
      greaterThan(metrics.timeLeft),
      reason: 'fixture: the picture reaches into the time column',
    );
  });

  test('a picture renders as sharp on the paper as every window: the canvas '
      'a moving camera sweeps takes more pixels as it takes more paper', () {
    SheetPicture pictureOf(ConteCellSource cell) =>
        printed([cell]).marks.whereType<SheetPicture>().single;
    expect(contePictureRenderWidth(pictureOf(still()), metrics, 1920), 1920);
    expect(
      contePictureRenderWidth(
        pictureOf(moving(conteCameraPan(across: 0.9))),
        metrics,
        1920,
      ),
      (1920 * 1.9).round(),
      reason: 'a screen and nine tenths, at a screen a window',
    );
    final far = pictureOf(moving(conteCameraPan(down: 6)));
    expect(
      contePictureRenderWidth(far, metrics, 1920),
      lessThan(1920),
      reason: 'seven screens laid into four rows take less paper a screen',
    );
  });
}
