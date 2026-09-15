import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/media/media_asset_uses.dart';
import 'package:anicel/src/services/persistence/cel_places.dart';
import 'package:anicel/src/ui/text/place_lines.dart';

/// A use of a pool file reads as the line a person finds it by (F-118): a
/// row by its cut and its name, a frame the way the save's lost-picture list
/// names a drawing — one line for a frame on a row, in both lists.
void main() {
  test('a row placed from the file reads as its cut and its name', () {
    expect(
      mediaAssetUseLine(
        const RowMediaUse(
          cutId: CutId('c1'),
          layerId: LayerId('walk'),
          ownerName: 'C1',
          layerName: 'walk',
        ),
      ),
      'C1 · walk',
    );
  });

  test('a frame that carries the file reads the way the lost-picture list '
      'names a drawing', () {
    const place = DrawingCelPlace(
      ownerName: 'Video',
      layerName: 'S1',
      celName: 'walk.mp4',
    );
    expect(
      mediaAssetUseLine(
        const FrameMediaUse(
          trackId: TrackId('t1'),
          cutId: null,
          layerId: LayerId('s1'),
          frameId: FrameId('step'),
          place: place,
        ),
      ),
      'Video · S1 · walk.mp4',
    );
    expect(celPlaceLine(place), 'Video · S1 · walk.mp4');
  });
}
