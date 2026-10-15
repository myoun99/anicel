import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/place_lines.dart';
import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/cel_text_fixture.dart';

const _sky = 'C:/media/sky.png';
const _sea = 'C:/media/sea.png';

Cut _cut(String id, String name) => Cut(
  id: CutId(id),
  name: name,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [Layer(id: LayerId('$id-a'), name: 'A', frames: const [])],
);

Project _project() => Project(
  id: const ProjectId('sheet-photos'),
  name: 'Sheet photos',
  createdAt: DateTime.utc(2026, 10, 15),
  mediaAssets: [
    MediaAsset(path: _sky, name: 'sky.png'),
    MediaAsset(path: _sea, name: 'sea.png'),
  ],
  tracks: [
    Track(
      id: const TrackId('t1'),
      name: 'Video',
      cuts: [_cut('c1', '39'), _cut('c2', '40')],
    ),
  ],
);

final _box = envelopeInkBoxKey(const CutId('c1'), 'memo');
final _page = timesheetInkPageKey(const CutId('c2'), 0);

/// Handwriting with [photos] over it — a cel that loses them is still a
/// picture.
BitmapSurface _inked(List<CelPhoto> photos) => drawingOf({
  TileCoord(x: 0, y: 0): tileOf({
    (1, 1): [9, 9, 9, 255],
  }),
}).withPhotos(photos);

/// A session whose cut 39's envelope box carries both files and whose cut
/// 40's timesheet page carries the sky — the sheets' own ink, which the
/// project does not hold.
EditorSessionManager _session() {
  final session = EditorSessionManager(initialProject: _project());
  addTearDown(session.dispose);
  session.renderCaches.envelopeInkStore.storeBakedSurface(
    _box,
    _inked([photoOf(1, path: _sky), photoOf(2, path: _sea)]),
  );
  session.renderCaches.timesheetInkStore.storeBakedSurface(
    _page,
    _inked([photoOf(1, path: _sky)]),
  );
  return session;
}

/// The files [key]'s photos show, in the order they stand.
List<String> _photosOn(EditorSessionManager session, BrushFrameKey key) => [
  for (final photo
      in session.renderCaches
          .sheetInkStoreFor(key)!
          .bakedSurfaceOrNull(key)!
          .photos)
    photo.reference.assetPath,
];

/// 🗣️유저 I-97 (2026-10-15): a pool picture dropped on a sheet stays a
/// photo of that file — so the pool says where it is used, and what the
/// pool does to the file reaches it there: 「사용 중 표시 · 제거 질문
/// F-118 · 다시 연결」.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('🚨a sheet\'s photo of a pool file is a use of it — named by its '
      'sheet and its cut, as the list the in-use mark opens names a row', () {
    final session = _session();
    List<String> uses(String path) => [
      for (final use in session.mediaPool.mediaAssetUses(path))
        mediaAssetUseLine(use, framePlace: session.framePlaceLabel),
    ];
    final strings = AppText.strings;

    expect(uses(_sky), [
      '${strings.panelEnvelope} · 39',
      '${strings.panelTimesheet} · 40',
    ]);
    expect(uses(_sea), ['${strings.panelEnvelope} · 39']);
  });

  test('🚨removing a file takes its photos off every sheet that carries '
      'them — the other file\'s photo and the ink stay — and ONE undo puts '
      'them back, as a redo takes them again', () {
    final session = _session();
    final before = session.repository.requireProject().toJson();

    expect(session.mediaPool.removeMediaAsset(_sky), isTrue);

    expect(session.mediaPool.mediaAssetUses(_sky), isEmpty);
    expect(_photosOn(session, _box), [_sea]);
    expect(_photosOn(session, _page), isEmpty);
    expect(
      session.renderCaches.timesheetInkStore
          .bakedSurfaceOrNull(_page)!
          .tiles,
      isNotEmpty,
      reason: 'the ink under a photo is no use of the file',
    );

    session.undo();

    expect(session.repository.requireProject().toJson(), before);
    expect(_photosOn(session, _box), [_sky, _sea]);
    expect(_photosOn(session, _page), [_sky]);
    expect(session.historyManager.canUndo, isFalse, reason: 'ONE step');

    session.redo();

    expect(_photosOn(session, _box), [_sea]);
    expect(_photosOn(session, _page), isEmpty);
  });

  test('🚨a file relinked by hand takes its photos along — in the pool\'s '
      'one step, which an undo takes back whole', () async {
    final session = _session();
    const found = 'D:/found/sky.png';

    await session.mediaPool.relinkMediaAsset(
      r'C:\media\sky.png',
      r'D:\found\sky.png',
    );

    expect(_photosOn(session, _box), [found, _sea]);
    expect(_photosOn(session, _page), [found]);
    expect(session.mediaPool.mediaAssetUses(found), hasLength(2));

    session.undo();

    expect(_photosOn(session, _box), [_sky, _sea]);
    expect(_photosOn(session, _page), [_sky]);
    expect(session.historyManager.canUndo, isFalse, reason: 'ONE step');
  });

  test('the batch relink takes every file\'s photos along, in its one '
      'step', () {
    final session = _session();

    session.mediaPool.relinkMediaAssets({
      _sky: 'D:/found/sky.png',
      _sea: 'D:/found/sea.png',
    });

    expect(_photosOn(session, _box), ['D:/found/sky.png', 'D:/found/sea.png']);
    expect(_photosOn(session, _page), ['D:/found/sky.png']);

    session.undo();

    expect(_photosOn(session, _box), [_sky, _sea]);
    expect(_photosOn(session, _page), [_sky]);
    expect(session.historyManager.canUndo, isFalse, reason: 'ONE step');
  });

  test('a relink the pool refuses moves no photo, and leaves no step', () {
    final session = _session();

    // The sky onto the sea's path: the pool holds the sea there.
    session.mediaPool.relinkMediaAssets({_sky: _sea});

    expect(_photosOn(session, _box), [_sky, _sea]);
    expect(_photosOn(session, _page), [_sky]);
    expect(session.historyManager.canUndo, isFalse);
  });
}
