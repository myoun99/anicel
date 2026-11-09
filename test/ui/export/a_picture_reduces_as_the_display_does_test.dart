import '../../helpers/a_canvas_standing_on_a_frame.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/panel_pictures.dart';
import 'package:anicel/src/ui/sheet_painting.dart';

/// 🗣️F-215 (유저 2026-09-30): 「브러시허용누르면 그림 바뀌는거 … 허용누르면
/// 필터on되는거같은데. 왜 브러시허용이랑 렌더링이랑 연관있는거냐고」 ·
/// 「콘티프리뷰패널의 픽쳐칸 그림 … 축소시 이거 캔버스랑 같은규칙으로
/// 안티low 필터같은거 동일적용한거맞나?」.
///
/// A panel's picture — the print a conte cell shows while the brush is off
/// — is reduced as the canvas's display reduces the same cut beside it
/// while the brush is on: its one picture at canvas resolution, read from
/// its own mip chain with the display's filter. ↩️Halved a 2×2 box mean at
/// a time, and only what was left of the reduction filtered, while the
/// display drew below 100% from a level — until one-picture-per-frame
/// ②-5b-3.
void main() {
  opensTheEnginesScreens();
  // One tile exactly: the composed image IS the canvas rect, the case the
  // legacy draw at the origin is kept for.
  const canvas = CanvasSize(width: 128, height: 128);
  const size = 128;

  /// A panel's picture [width] pixels wide of a cut whose one cel is black
  /// on the columns [inked] picks, clear between, over [region] of its
  /// canvas — the ink each pixel of its tenth row holds: the paper's white
  /// it takes away.
  Future<List<int>> pictureRow(
    WidgetTester tester, {
    required bool Function(int x) inked,
    required int width,
    ui.Rect? region,
  }) async {
    return (await tester.runAsync(() async {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('levels'),
          name: 'Levels',
          cameraSize: canvas,
          createdAt: DateTime.utc(2026, 9, 30),
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Video',
              cuts: [
                Cut(
                  id: const CutId('c'),
                  name: '1',
                  duration: 6,
                  canvasSize: canvas,
                  layers: [
                    Layer(
                      id: const LayerId('a'),
                      name: 'A',
                      kind: LayerKind.animation,
                      frames: [
                        Frame(
                          id: const FrameId('f'),
                          duration: 1,
                          strokes: const [],
                        ),
                      ],
                      timeline: const {
                        0: TimelineExposure.drawing(FrameId('f'), length: 6),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      final cut = session.requireActiveCut;
      final pixels = Uint8List(size * size * 4);
      for (var y = 0; y < canvas.height; y += 1) {
        for (var x = 0; x < size; x += 1) {
          if (inked(x)) {
            pixels[(y * size + x) * 4 + 3] = 255;
          }
        }
      }
      session.renderCaches.brushFrameStore.storeBakedSurface(
        session.brushFrameKeyForCut(
          cut,
          const LayerId('a'),
          const FrameId('f'),
        ),
        BitmapSurface(canvasSize: canvas, tileSize: size).putTiles([
          (
            coord: TileCoord(x: 0, y: 0),
            tile: BitmapTile(size: size, pixels: pixels),
          ),
        ]),
      );
      final image = await PanelPictures(
        session: session,
      ).render(cut, 0, width: width, region: region);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final shown = image.width;
      image.dispose();
      session.dispose();
      return [
        for (var x = 0; x < shown; x += 1)
          255 - bytes.getUint8((9 * shown + x) * 4),
      ];
    }))!;
  }

  testWidgets('at a quarter, a line a pixel wide every fourth pixel stays a '
      'quarter of every pixel — it does not fall between the samples', (
    tester,
  ) async {
    final row = await pictureRow(
      tester,
      inked: (x) => x % 4 == 0,
      width: 32,
    );
    expect(row, hasLength(32), reason: 'fixture: a quarter of the camera');
    // ⚠️Short of the last column, which the display's reduction reads past
    // the canvas for (`stage_at`: a stage and a resample of it, wider than
    // the four columns). ↩️Every column, while a picture reduced through
    // Flutter's. 🗣️유저 11-08: 「지금화면이랑 맞출필요는없어 … 바뀌고
    // 나서만 동일하면되」.
    expect(
      row.sublist(0, 31),
      everyElement(inInclusiveRange(60, 68)),
      reason: 'each pixel a quarter covered: the mean of the four columns '
          'it stands for',
    );
  });

  testWidgets('a picture a canvas pixel off the grid is moved onto its pixels '
      'as the display moves a view', (tester) async {
    bool inked(int x) => (x ~/ 4).isEven;
    Future<List<int>> from(double left) => pictureRow(
      tester,
      inked: inked,
      width: 32,
      region: ui.Rect.fromLTWH(left, 0, 128, 72),
    );
    final row = await from(1);
    expect(row.toSet().length, greaterThan(1), reason: 'LIVENESS: the ink');
    expect(row, await from(0));
    // ↩️Beside Flutter's own reduction of the ink, while a picture was read
    // from a level through it; ↩️whole or clear, as a level had them, until
    // one-picture-per-frame ②-5b-3.
  });

  test('the print is laid into its shot with the display\'s own filter for '
      'what is left of the reduction', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(100, 50);
    picture.dispose();
    addTearDown(image.dispose);

    expect(
      sheetPictureQuality(image.width, const Rect.fromLTWH(0, 0, 40, 20), 2),
      FilterQuality.low,
      reason: '80 device pixels for 100: reduced, so filtered',
    );
    expect(
      sheetPictureQuality(image.width, const Rect.fromLTWH(0, 0, 50, 25), 2),
      FilterQuality.none,
      reason: 'a pixel a pixel',
    );
    expect(
      sheetPictureQuality(image.width, const Rect.fromLTWH(0, 0, 100, 50), 2),
      FilterQuality.none,
      reason: 'magnified: the pixels themselves, as the canvas shows them',
    );
  });
}
