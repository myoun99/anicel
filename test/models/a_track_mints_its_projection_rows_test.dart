import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_projection_row.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';

/// A TRACK'S OWN ROWS (I-73): the rows the storyboard's rail stands on that
/// no layer's id names — the V track's lane carrier, the conte rows a seat
/// each, and the camera row — each under a name minted from the track
/// (`track_minted_row_id.dart`), each read back as ITS kind and no other.
///
/// The conte rows and the camera row are the PROJECTION rows: a cut's own
/// row shown on the track's axis, which resolve to the layer of a cut they
/// show there ([projectedRowOf]).
void main() {
  const t = TrackId('t');

  test('the camera row\'s address names its track and nothing else', () {
    final camera = trackCameraRowId(t);
    expect(trackIdOfCameraRow(camera), t);
    expect(isTrackCameraRow(LayerRowAddress(camera)), isTrue);
    expect(isTrackCameraRow(LaneRowAddress(camera, 'x')), isFalse);
    expect(isTrackCameraRow(const TrackRowAddress(t)), isFalse);
    expect(isTrackCameraRow(null), isFalse);
    expect(trackIdOfCameraRow(const LayerId('camera-a')), isNull);
  });

  test('the three minted names never read as one another', () {
    final camera = trackCameraRowId(t);
    final conte = trackConteRowId(t);
    final seat = trackConteRowId(t, seat: -1);
    final carrier = trackTransformLaneCarrierId(t);
    expect(trackConteRowOf(camera), isNull);
    expect(trackIdOfTransformLaneCarrier(camera), isNull);
    expect(trackIdOfCameraRow(conte), isNull);
    expect(trackIdOfCameraRow(seat), isNull);
    expect(trackIdOfCameraRow(carrier), isNull);
    expect(trackConteRowOf(carrier), isNull);
    // …and each still reads back as itself.
    expect(trackConteRowOf(conte), (trackId: t, seat: 0));
    expect(trackConteRowOf(seat), (trackId: t, seat: -1));
    expect(trackIdOfTransformLaneCarrier(carrier), t);
  });

  test('a projection row is a conte row at any seat, or the camera row', () {
    expect(trackIdOfProjectionRow(trackCameraRowId(t)), t);
    expect(trackIdOfProjectionRow(trackConteRowId(t)), t);
    expect(trackIdOfProjectionRow(trackConteRowId(t, seat: 2)), t);
    expect(
      trackIdOfProjectionRow(trackTransformLaneCarrierId(t)),
      isNull,
      reason: 'the V lane carrier is the track\'s own, no cut\'s',
    );
    expect(trackIdOfProjectionRow(const LayerId('camera-a')), isNull);
    expect(isTrackProjectionRow(LayerRowAddress(trackCameraRowId(t))), isTrue);
    expect(isTrackProjectionRow(const TrackRowAddress(t)), isFalse);
  });

  test('a projection row shows a cut\'s own layer there', () {
    final cameraLayer = Layer(
      id: const LayerId('camera-a'),
      name: 'Camera',
      kind: LayerKind.camera,
      frames: const [],
    );
    final conteLayer = Layer(
      id: const LayerId('conte-a'),
      name: 'Conte',
      kind: LayerKind.storyboard,
      frames: const [],
    );
    final cut = Cut(
      id: const CutId('a'),
      name: 'a',
      duration: 24,
      canvasSize: const CanvasSize(width: 8, height: 8),
      layers: [conteLayer, cameraLayer],
    );
    expect(
      projectedRowOf(cut, LayerRowAddress(trackCameraRowId(t)))?.id,
      cameraLayer.id,
    );
    expect(
      projectedRowOf(cut, LayerRowAddress(trackConteRowId(t)))?.id,
      conteLayer.id,
    );
    expect(
      projectedRowOf(cut, LayerRowAddress(trackConteRowId(t, seat: 1))),
      isNull,
      reason: 'no attach row rides this conte',
    );
    expect(projectedRowOf(cut, LayerRowAddress(cameraLayer.id)), isNull);
    expect(projectedRowOf(cut, const TrackRowAddress(t)), isNull);
    final noCamera = cut.copyWith(layers: [conteLayer]);
    expect(
      projectedRowOf(noCamera, LayerRowAddress(trackCameraRowId(t))),
      isNull,
    );
  });
}
