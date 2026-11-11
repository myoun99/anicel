import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_read_source.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_fill_on_a_session.dart';
import '../../helpers/a_fill_on_the_engine.dart';
import '../../helpers/fill_pieces.dart';

/// WHAT A FILL PRESSED ON A CANVAS READS (`fillPictureOver`), asked as the
/// canvas asks it ([fillPressedOn]): the rows its read source names
/// (I-36), each as the frame shows it — a row clipped to the one below
/// where its base is (I-92), a cel's letters with its drawing (🗣️유저
/// 2026-10-06: 「셀의 그림이랑 정확히 동일」) — and no ghost of the onion.
void main() {
  opensTheEnginesScreens();
  const canvasSize = CanvasSize(width: 8, height: 8);
  const ink = LayerId('ink');
  const paint = LayerId('paint');
  const exact = FloodFillOptions(expandPx: 0, antiAlias: false);
  const black = [0, 0, 0, 255];

  /// A closed box outline (2,2)..(5,5) — interior = (3..4, 3..4).
  Map<(int, int), List<int>> boxOutline(List<int> rgba) => {
    for (var x = 2; x <= 5; x += 1) ...{(x, 2): rgba, (x, 5): rgba},
    for (var y = 3; y <= 4; y += 1) ...{(2, y): rgba, (5, y): rgba},
  };

  /// What a fill pressed inside the box encloses, by the box of what it
  /// lays.
  (int, int) filled(
    EditorSessionManager session, {
    FloodFillOptions options = exact,
  }) {
    final dabs =
        fillPressedOn(
          session,
          CanvasPoint(x: 3, y: 3),
          options: options,
        )?.dabsIn(0xFF3366CC) ??
        const [];
    final box = piecesBox(dabs);
    return (box.width, box.height);
  }

  const page = (8, 8);
  const box = (2, 2);

  test('the fill reads what its READ SOURCE says (I-36 — its middle mode, '
      'the flagged layers, went with I-92)', () {
    // A paint row whose opaque blob covers the whole canvas, over the ink:
    // read with the ink it is the seed's colour everywhere, and the box on
    // the ink row is invisible to the fill.
    final blob = celOfPixels(canvasSize, {
      for (var y = 0; y < 8; y += 1)
        for (var x = 0; x < 8; x += 1) (x, y): const [200, 0, 0, 255],
    });
    (int, int) read(
      CanvasReadSource source, {
      required LayerId standOn,
      bool clipped = false,
    }) => filled(
      sessionOfRows(
        [
          drawingRow('ink'),
          drawingRow('paint').copyWith(clipsToBelow: clipped),
        ],
        canvasSize: canvasSize,
        cels: {
          (ink, theCel): celOfPixels(canvasSize, boxOutline(black)),
          (paint, theCel): blob,
        },
        standOn: standOn,
      ),
      options: exact.copyWith(source: source),
    );

    // 「보이는거 전부」: the blob hides the box, whichever row is stood on.
    for (final standOn in [ink, paint]) {
      expect(
        read(CanvasReadSource.display, standOn: standOn),
        page,
        reason: 'what you see is the blob, standing on $standOn',
      );
    }
    // 「현재레이어」: the row stood on alone.
    expect(read(CanvasReadSource.layer, standOn: paint), page);
    expect(read(CanvasReadSource.layer, standOn: ink), box);
    // I-92: clipped to the ink under it, the blob shows on the box's walls
    // alone — what you see holds the seed in the box; read alone, it is the
    // blob as drawn.
    expect(read(CanvasReadSource.display, standOn: paint, clipped: true), box);
    expect(read(CanvasReadSource.layer, standOn: paint, clipped: true), page);
  });

  group('a cel\'s letters', () {
    /// A cel that draws nothing and carries one text baked to [letters].
    BitmapSurface written(Map<(int, int), List<int>> letters) =>
        BitmapSurface(
          canvasSize: canvasSize,
          texts: [
            CelText(
              id: 1,
              content: CelTextContent(
                spans: const [CelTextSpan(text: 'a', style: TextLetterStyle())],
                anchor: CanvasPoint(x: 0, y: 0),
              ),
              plate: celOfPixels(canvasSize, letters).tiles,
            ),
          ],
        );

    EditorSessionManager sessionOf(BitmapSurface cel) => sessionOfRows(
      [drawingRow('ink')],
      canvasSize: canvasSize,
      cels: {(ink, theCel): cel},
      standOn: ink,
    );

    test('🚨wall a fill as a drawn line does: a box written as text encloses '
        'its inside', () {
      expect(filled(sessionOf(written(boxOutline(black)))), box);
    });

    test('fixture: with no letters the same press floods the whole page', () {
      expect(filled(sessionOf(written(const {}))), page);
    });
  });

  test('🚨a ghost of the onion walls nothing: the frame before lies in the '
      'picture the canvas shows, and the fill reads the frame alone', () {
    const before = FrameId('before');
    const stood = FrameId('stood');
    final session = sessionOfRows(
      [
        Layer(
          id: ink,
          name: 'ink',
          frames: [
            Frame(id: before, duration: 1, strokes: const []),
            Frame(id: stood, duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(before, length: 1),
            1: const TimelineExposure.drawing(stood, length: 1),
          },
        ),
      ],
      canvasSize: canvasSize,
      cels: {(ink, before): celOfPixels(canvasSize, boxOutline(black))},
      standOn: ink,
    );
    expect(filled(session), box, reason: 'fixture: the box walls its frame');

    session.selectFrameIndex(1);
    session.onionSkin.toggleLayerOnionSkin(ink);
    final settings = session.onionSkin.settings;
    settings.value = settings.value.copyWith(
      placement: OnionSkinPlacement.inPlace,
    );
    expect(
      session.onionSkin
          .ghostsAt(session.requireActiveCut, 1, null)
          .values
          .expand((ghosts) => ghosts),
      isNotEmpty,
      reason: 'fixture: the box is a ghost on the frame stood on',
    );

    expect(filled(session), page);
  });
}
