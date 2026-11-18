// 🗣️F-578 ⑨ (유저 2026-11-10): 「용지lo레이어에 작감이 다음에 수정넣으면
// 용지-작감 이런식으로 어태치레이어만들어서 작감용지 얹는다거나. 물론
// 참조fx같은거 생각해서 어태치에도 참조fx에서 옮긴거 적용되게」 — an attach
// row follows its base's reference fx as it follows the base's transform —
// and 🗣️attach-rows-lose-the-base-move-when-it-bakes-Q4 (유저 2026-11-11
// 「어태치줄의 참조fx는없앰」): a file of its own moves by none of its own.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/reference_move_carried.dart'
    show ReferenceCarried, transformCarryingReferenceMove;

void main() {
  const canvas = CanvasSize(width: 400, height: 300);
  const picture = CanvasSize(width: 100, height: 60);
  const paperId = LayerId('paper');

  /// A file laid centred on [from] that its fx keys there at frame 0 and
  /// at [to] at frame 10.
  MediaReference fileMoving(CanvasPoint from, CanvasPoint to) =>
      MediaReference(
        assetPath: '/paper.png',
        pose: TransformPose(center: from),
        pictureSize: picture,
        fx: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>()
              .withKey(0, from)
              .withKey(10, to),
        ),
      );

  /// The 용지: a 100×60 paper its fx carries 200 to the right by frame 10.
  Layer paper({LayerKind kind = LayerKind.animation}) => Layer(
    id: paperId,
    name: '용지',
    kind: kind,
    frames: [Frame(id: const FrameId('f-1'), duration: 1, strokes: const [])],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('f-1'), length: 24),
    },
    mediaReference: fileMoving(
      CanvasPoint(x: 100, y: 50),
      CanvasPoint(x: 300, y: 50),
    ),
  );

  /// A row attached to [to], riding its cel 1 with its own cel 2 — showing
  /// [file] of its own, or drawn.
  Layer sheet({
    MediaReference? file,
    LayerId to = paperId,
    String id = 'sheet',
  }) => Layer(
    id: LayerId(id),
    name: '용지-작감',
    frames: [Frame(id: const FrameId('f-2'), duration: 1, strokes: const [])],
    timeline: const {},
    attachedToLayerId: to,
    baseFrameLinks: {const FrameId('f-1'): const FrameId('f-2')},
    mediaReference: file,
  );

  /// A file of the sheet's own, laid centred on (150, 80), its fx carrying
  /// it 100 down by frame 10.
  final sheetFile = fileMoving(
    CanvasPoint(x: 150, y: 80),
    CanvasPoint(x: 150, y: 180),
  );

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'cut',
    layers: layers,
    duration: 24,
    canvasSize: canvas,
  );

  CanvasPoint landed(Cut cut, String id, CanvasPoint at, int frame) {
    final layer = cut.layers.firstWhere((row) => row.id.value == id);
    final placement = layerPlacementAt(
      cut: cut,
      layer: layer,
      frameIndex: frame,
    );
    return placement == null ? at : placement.apply(at);
  }

  /// Where the composite paints [id]'s pixel [at] at [frame].
  CanvasPoint painted(Cut cut, String id, CanvasPoint at, int frame) {
    final entry = resolveCutFrameCompositeEntries(
      cut: cut,
      frameIndex: frame,
    ).firstWhere((entry) => entry.layer.id.value == id);
    return entry.placement?.apply(at) ?? at;
  }

  test('a sheet drawn on a 용지 its fx moves stands where the paper does — '
      'on the canvas and in the composite', () {
    final cut = cutOf([paper(), sheet()]);
    final at = CanvasPoint(x: 100, y: 50);

    expect(
      landed(cut, 'paper', at, 10),
      CanvasPoint(x: 300, y: 50),
      reason: '⛔CONTROL: the fx carries the paper 200 to the right',
    );
    expect(landed(cut, 'sheet', at, 10), CanvasPoint(x: 300, y: 50));
    expect(painted(cut, 'sheet', at, 10), CanvasPoint(x: 300, y: 50));
    expect(
      landed(cut, 'sheet', at, 0),
      at,
      reason: 'where the paper stands where it was laid, so does the sheet',
    );
  });

  test('a sheet with a file of its own wears the paper\'s move alone — its '
      'own fx moves nothing (-Q4)', () {
    final cut = cutOf([paper(), sheet(file: sheetFile)]);
    final at = CanvasPoint(x: 150, y: 80);
    // The paper's fx carries it 200 to the right; its own would carry it
    // 100 down as well.
    final worn = CanvasPoint(x: 350, y: 80);

    expect(landed(cut, 'sheet', at, 10), worn);
    expect(painted(cut, 'sheet', at, 10), worn);
    expect(
      referenceMoveAt(cut.layers.last, 10),
      isNotNull,
      reason: '⛔CONTROL: its own fx moves its file',
    );
  });

  test('a door that lays its file as it shows reads it standing where it '
      'is laid, and has no move of its own to carry (-Q4)', () {
    final cut = cutOf([paper(), sheet(file: sheetFile)]);
    final row = cut.layers.last;

    expect(
      rowAsItWearsItsFile(cut, row).mediaReference,
      sheetFile.standingWhereLaid,
    );
    expect(
      transformCarryingReferenceMove(
        cut: cut,
        layer: row,
        nameIsFree: (_, _) => true,
      ),
      isA<ReferenceCarried>().having(
        (carry) => carry.track,
        'track',
        row.transformTrack,
      ),
    );
    expect(
      rowAsItWearsItsFile(cut, cut.layers.first),
      same(cut.layers.first),
      reason: '⛔CONTROL: the paper wears its own',
    );
  });

  test('a row riding the conte wears its own fx, and none of the conte\'s '
      'move (I-99)', () {
    final cut = cutOf([
      paper(kind: LayerKind.storyboard),
      sheet(file: sheetFile),
    ]);
    final at = CanvasPoint(x: 150, y: 80);

    expect(landed(cut, 'sheet', at, 10), CanvasPoint(x: 150, y: 180));
    expect(painted(cut, 'sheet', at, 10), CanvasPoint(x: 150, y: 180));
  });

  test('a row whose base is gone moves by its own fx alone', () {
    final cut = cutOf([
      paper(),
      sheet(file: sheetFile, to: const LayerId('gone')),
    ]);

    expect(
      landed(cut, 'sheet', CanvasPoint(x: 150, y: 80), 10),
      CanvasPoint(x: 150, y: 180),
    );
  });

  test('a 용지 that lets go of its reference by keys leaves the sheet where '
      'it stood — the base\'s transform carries the move the sheet wore', () {
    final before = cutOf([paper(), sheet()]);
    final carry = transformCarryingReferenceMove(
      cut: before,
      layer: before.layers.first,
      nameIsFree: (_, _) => true,
    );
    final track = (carry as ReferenceCarried).track;
    final after = cutOf([
      before.layers.first.copyWith(
        transformTrack: track,
        transformEnabled: true,
        mediaReference: null,
      ),
      sheet(),
    ]);
    final at = CanvasPoint(x: 100, y: 50);

    for (final frame in [0, 5, 10]) {
      final was = landed(before, 'sheet', at, frame);
      final now = landed(after, 'sheet', at, frame);
      expect(
        (was.x - now.x).abs() + (was.y - now.y).abs(),
        lessThan(1e-6),
        reason: 'frame $frame: $was then, $now now',
      );
    }
    expect(
      landed(after, 'sheet', at, 10),
      isNot(at),
      reason: '⛔CONTROL: the sheet is carried at all',
    );
  });
}
