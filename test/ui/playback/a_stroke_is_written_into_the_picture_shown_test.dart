import 'package:anicel/src/models/canvas_viewport.dart';

import '../../helpers/a_stroke_written_into_the_picture_shown.dart';

/// A stroke's step written into the picture the canvas shows
/// ([aStrokeIsWrittenIntoThePictureShown]) on the tester's Skia: through a
/// pan, a zoom in and out and a device's ratio, and every pin of no view.
void main() => aStrokeIsWrittenIntoThePictureShown(
  views: {
    'panned': CanvasViewport(panX: 8, panY: 4),
    'at 200%': CanvasViewport(zoom: 2, panX: -6, panY: -10),
    // Bilinear on a 1.0 screen, the chain at 50% and 25% — and on a 1.5
    // screen the chain at 25% alone.
    'at 75%': CanvasViewport(zoom: 0.75, panX: 8, panY: 4),
    'at 50%': CanvasViewport(zoom: 0.5, panX: 8, panY: 4),
    'at 25%': CanvasViewport(zoom: 0.25, panX: 8, panY: 4),
  },
  ratios: const [1.0, 1.5],
);
