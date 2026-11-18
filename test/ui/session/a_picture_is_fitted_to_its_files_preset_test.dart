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
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart'
    show placedReference;
import 'package:anicel/src/services/media/media_preset_sync.dart';
import 'package:anicel/src/services/project_lookup.dart' show requireLayer;
import 'package:anicel/src/ui/editor_session_manager.dart';

const _cloud = 'C:/media/cloud.png';
const _cutId = CutId('c1');
const _oneCel = LayerId('p1');
const _twoCels = LayerId('p2');

/// The cut's canvas, and the still twice its size — its preset fits it
/// inside the cut, at half its size, as an image.
const _canvas = CanvasSize(width: 640, height: 360);
const _picture = CanvasSize(width: 1280, height: 720);

/// The still as it was placed 1:1, and keyed since: moved once, and grown
/// from half its size to four fifths of it.
MediaReference _placed() =>
    placedReference(_cloud, _picture, _canvas, MediaFitMode.none).copyWith(
      fx: TransformTrack.properties(
        anchorPoint: PropertyTrack.empty(),
        position: PropertyTrack(
          keys: {0: PropertyKey(CanvasPoint(x: 100, y: 120))},
        ),
        scale: PropertyTrack(
          keys: {
            0: PropertyKey(CanvasPoint(x: 0.5, y: 0.5)),
            10: PropertyKey(CanvasPoint(x: 0.8, y: 0.8)),
          },
        ),
        rotation: PropertyTrack.empty(),
        opacity: PropertyTrack.empty(),
      ),
    );

Layer _row(LayerId id, {required int cels}) => Layer(
  id: id,
  name: id.value,
  frames: [
    for (var cel = 0; cel < cels; cel++)
      Frame(id: FrameId('${id.value}-$cel'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (var cel = 0; cel < cels; cel++)
      cel * 12: TimelineExposure.drawing(
        FrameId('${id.value}-$cel'),
        length: 12,
      ),
  },
  mediaReference: _placed(),
);

/// The still on two animation rows: one of one cel, one of two.
Project _project() => Project(
  id: const ProjectId('fit-a-picture'),
  name: 'Fit a picture',
  createdAt: DateTime.utc(2026, 11, 18),
  mediaAssets: [
    MediaAsset(
      path: _cloud,
      name: 'cloud',
      kind: MediaAssetKind.image,
      preset: const MediaPreset(
        fit: MediaFitMode.contain,
        pictureKind: LayerKind.image,
      ),
    ),
  ],
  tracks: [
    Track(
      id: const TrackId('t1'),
      name: 'Video',
      cuts: [
        Cut(
          id: _cutId,
          name: 'c1',
          duration: 24,
          canvasSize: _canvas,
          layers: [_row(_oneCel, cels: 1), _row(_twoCels, cels: 2)],
        ),
      ],
    ),
  ],
);

const MediaSyncLengths _known = (sound: null, pictures: null);

List<MediaSyncPlace> _placesIn(Project project) =>
    syncPlacesOf(project, project.mediaAssets.single, lengths: _known);

const _fitAndKind = {MediaSyncField.fit, MediaSyncField.kind};

/// 🗣️유저 2026-11-18 (card 「파일마다 배치 기본값」-Q7 kind-too-off · Q8
/// same-switch · Q9 「키는 유지함. 거기서 크기만 새롭게」 · Q10 「크기 키를
/// 새 맞춤 비율만큼 함께 바꾼다」): a placed picture's fit is its reference's
/// placed size, and syncing it sets that size and carries the size keys by
/// the same ratio; its kind is set through the layer kind switch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a still\'s row holds its fit — the size it was placed at, and the '
      'one its preset\'s fit makes on the cut — and its kind; it holds no '
      'start and no length, so the pool\'s mark does not turn for it', () {
    final project = _project();
    final [one, two] = _placesIn(project);
    expect(one.fields, _fitAndKind);
    expect(one.size, (
      held: CanvasPoint(x: 1, y: 1),
      placed: CanvasPoint(x: 0.5, y: 0.5),
      heldFit: MediaFitMode.none,
    ));
    expect(one.kind, LayerKind.animation);
    expect(one.placed.kind, LayerKind.image);
    expect(one.partsFrom(MediaSyncField.values.toSet()), _fitAndKind);
    expect(
      partsFromItsPreset(project, project.mediaAssets.single, lengths: _known),
      isFalse,
    );
    expect(one.canSetAt(_fitAndKind), isTrue);
    expect(
      two.canSetAt(_fitAndKind),
      isFalse,
      reason: 'an image holds one cel, and this row holds two',
    );
    expect(two.canSetAt({MediaSyncField.fit}), isTrue);
  });

  test('syncing the fit sets the size it was placed at and carries every '
      'size key by the same ratio — where it stands, its other keys and '
      'where its pixels are laid as they were; the kind turns it into an '
      'image — ONE undo takes all of it back', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    Layer row() => requireLayer(
      session.repository.requireProject(),
      cutId: _cutId,
      layerId: _oneCel,
    );
    final before = row();
    final was = before.mediaReference!;
    session.mediaPool.syncPlaces(
      _cloud,
      fields: _fitAndKind,
      places: [_placesIn(session.repository.requireProject()).first],
    );
    final now = row().mediaReference!;
    expect(now.pose, was.pose.copyWith(scaleX: 0.5, scaleY: 0.5));
    expect(
      {
        for (final MapEntry(:key, :value) in now.fx.scale.keys.entries)
          key: value.value,
      },
      {
        0: CanvasPoint(x: 0.25, y: 0.25),
        10: CanvasPoint(x: 0.4, y: 0.4),
      },
    );
    expect(now.fx.position, was.fx.position);
    expect(now.laid, was.laid, reason: 'its pixels stay where they lie');
    expect(row().kind, LayerKind.image);
    session.historyManager.undo();
    expect(row(), before);
  });

  test('a row of more cels than an image holds keeps its kind — its fit '
      'is set all the same', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    session.mediaPool.syncPlaces(
      _cloud,
      fields: _fitAndKind,
      places: [_placesIn(session.repository.requireProject()).last],
    );
    final row = requireLayer(
      session.repository.requireProject(),
      cutId: _cutId,
      layerId: _twoCels,
    );
    expect(row.kind, LayerKind.animation);
    expect(row.mediaReference!.pose.scale, CanvasPoint(x: 0.5, y: 0.5));
  });
}
