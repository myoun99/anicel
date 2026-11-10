import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/cel_number_letters.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart' show LayerPlacement;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/text/se_name_tag_paint.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/app_faces.dart';

/// 🗣️card cel-number-letters-drawn-as-vectors (유저 2026-11-07 「지금까지가
/// 셀번호가 벡터엿던게 버그야. 통일하지 않았던거니까」): the letters a picture
/// holds are canvas pixels, as the picture is. Drawn at 400% they are their
/// pixels at 100%, each four times over, and on a row scaled twice each of
/// them twice over. ↩️Drawn as vectors, their edges were smooth at whatever
/// resolution they landed on.
void main() {
  opensTheEnginesScreens();

  const canvas = CanvasSize(width: 120, height: 60);
  final letters = CelNumberLetters(
    text: 'A12',
    color: 0xFF202020,
    center: CanvasPoint(x: 30.3, y: 22.6),
    scale: CanvasPoint(x: 0.5, y: 0.5),
  );

  setUpAll(loadTheAppFaces);

  /// The frame holding the number on a bare row, [placement] where it lies
  /// otherwise, on a world [over] the canvas's size, a canvas pixel [zoom] to
  /// a side — the engine's.
  ({Uint8List rgba, int width}) numberAt({
    double zoom = 1,
    int over = 1,
    LayerPlacement? placement,
  }) {
    final world = ui.Rect.fromLTWH(
      0,
      0,
      (canvas.width * over).toDouble(),
      (canvas.height * over).toDouble(),
    );
    final frame = stackedFrameOf(
      [
        CompositeCelNumber<CanvasStackRow>(
          on: CompositeLeaf(
            CanvasLayerImageRequest(
              frameKey: const BrushFrameKey(
                projectId: ProjectId('project'),
                trackId: TrackId('track'),
                cutId: CutId('cut'),
                layerId: LayerId('row'),
                frameId: FrameId('cel'),
              ),
              opacity: 1,
              placement: placement,
            ),
          ),
          letters: letters,
        ),
      ],
      page: (
        canvasSize: canvas,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: false,
        paperBackground: ProjectBackground.defaultBackground,
      ),
      surfaceOf: (_) => BitmapSurface(canvasSize: canvas),
    );
    return (
      rgba: pixelsOfFrame(frame, world, zoom: zoom),
      width: (world.width * zoom).round(),
    );
  }

  void tag(ui.Canvas into, double scale) => paintSeNameTags(
    into,
    tags: [
      ResolvedSeNameTag(
        layerId: 's1',
        widthBudget: 400,
        shot: const LayerPlacement.identity(),
        content: TextCelContent(
          text: 'タロウ',
          // A size between pixels: what the tag may paint ends between
          // them too, and its plate still lies on whole ones.
          style: SeNameTag.defaultStyle.copyWith(fontSize: 17.5),
          position: const ui.Offset(60.4, 30.7),
        ),
      ),
    ],
    canvasSize: canvas,
    rasterScale: scale,
  );

  test('a cel number at 400% is its pixels at 100%, each four times over', () {
    _expectBlocks(numberAt(), numberAt(zoom: 4), 4);
  });

  test('a cel number on a row scaled twice is its pixels, each twice over', () {
    _expectBlocks(
      numberAt(),
      // The row's paper twice as large, its corner where the canvas's is
      // twice as far: each canvas pixel lands on a block of 2×2.
      numberAt(over: 2, placement: const LayerPlacement(2, 0, 0, 2, 0, 0)),
      2,
    );
  });

  test('a name tag at 400% is its pixels at 100%, each four times over', () async {
    final whole = await _pixels(canvas, 1, (into) => tag(into, 1));
    final zoomed = await _pixels(
      canvas,
      4,
      (into) => tag(into..scale(4), 4),
    );

    _expectBlocks(whole, zoomed, 4);
  });
}

/// [canvas] drawn by [paint] at [times] its size, as straight RGBA.
Future<({Uint8List rgba, int width})> _pixels(
  CanvasSize canvas,
  int times,
  void Function(ui.Canvas into) paint,
) async {
  final width = canvas.width * times;
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  final image = recorder.endRecording().toImageSync(
    width,
    canvas.height * times,
  );
  final bytes = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return (rgba: bytes!.buffer.asUint8List(), width: width);
}

/// Every pixel of [larger] is [whole]'s pixel under it, [times] to a side.
void _expectBlocks(
  ({Uint8List rgba, int width}) whole,
  ({Uint8List rgba, int width}) larger,
  int times,
) {
  var inked = 0;
  var soft = 0;
  for (var at = 3; at < whole.rgba.length; at += 4) {
    if (whole.rgba[at] > 0) {
      inked += 1;
      if (whole.rgba[at] < 255) {
        soft += 1;
      }
    }
  }
  expect(inked, greaterThan(40), reason: 'LIVENESS: the letters drew');
  expect(
    soft,
    greaterThan(10),
    reason: '⛔전제: their edges are partly covered, so smooth letters at '
        'the larger size would show between the blocks',
  );
  var apart = 0;
  final height = whole.rgba.length ~/ 4 ~/ whole.width;
  for (var y = 0; y < height * times; y += 1) {
    for (var x = 0; x < whole.width * times; x += 1) {
      final at = (y * larger.width + x) * 4;
      final under = ((y ~/ times) * whole.width + x ~/ times) * 4;
      for (var channel = 0; channel < 4; channel += 1) {
        if (larger.rgba[at + channel] != whole.rgba[under + channel]) {
          apart += 1;
          break;
        }
      }
    }
  }
  expect(
    apart,
    0,
    reason: '🚨the letters were drawn finer than the canvas pixels the '
        'picture is made of',
  );
}
