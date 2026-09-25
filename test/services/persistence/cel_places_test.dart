import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/cel_places.dart';

/// 🚨★★★A SAVE THAT COULD NOT CARRY PICTURES SAYS WHICH (C-save-percent).
///
/// 유저 2026-09-11: the notice said a picture was lost, and nothing on
/// screen said which. These pins say what each kind of key is found as —
/// and that every key is found as SOMETHING, so the list is as long as the
/// count the notice gives.
void main() {
  Frame frame(String id, [String? name]) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Layer layer(
    String id,
    String name,
    List<Frame> frames, {
    LayerKind kind = LayerKind.animation,
  }) => Layer(id: LayerId(id), name: name, frames: frames, kind: kind);

  Cut cut(String id, String name, List<Layer> layers) => Cut(
    id: CutId(id),
    name: name,
    layers: layers,
    duration: 24,
    canvasSize: const CanvasSize(width: 16, height: 16),
  );

  final project = Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 15),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Track 1',
        seLayers: [
          layer('s1', 'S1', [frame('s1-f', 'hey')], kind: LayerKind.se),
        ],
        cuts: [
          cut('c1', '1', [
            layer('a', 'A', [
              frame('a1', '1'),
              frame('a2'),
              frame('a3', '   '),
            ]),
            layer('sb', 'SB', [
              frame('sb1', ' 2 '),
            ], kind: LayerKind.storyboard),
          ]),
          cut('c2', '2', [
            layer('b', 'B', [frame('b1', 'x')]),
          ]),
        ],
      ),
    ],
  );

  BrushFrameKey drawn(String cutId, String layerId, String frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: const TrackId('t'),
        cutId: CutId(cutId),
        layerId: LayerId(layerId),
        frameId: FrameId(frameId),
      );

  /// What each place says, in this test's own words.
  String said(CelPlace place) => switch (place) {
    DrawingCelPlace(:final ownerName, :final layerName, :final celName) =>
      'drawing $ownerName/$layerName/$celName',
    ContePageInkPlace(:final pageNumber) => 'conte page $pageNumber',
    ConteRowInkPlace(:final cutName, :final celName) =>
      'conte row $cutName/$celName',
    EnvelopeInkPlace(:final cutName) => 'envelope $cutName',
    GoneCelPlace() => 'gone',
  };

  List<String> placesOf(List<BrushFrameKey> keys) => [
    for (final place in celPlacesOf(project, keys)) said(place),
  ];

  test('a drawing is named by its cut, its row and what its block prints — '
      'in the order the project holds them, not the order asked', () {
    expect(
      placesOf([
        drawn('c2', 'b', 'b1'),
        drawn('c1', 'a', 'a3'),
        drawn('c1', 'a', 'a2'),
        drawn('c1', 'a', 'a1'),
      ]),
      ['drawing 1/A/1', 'drawing 1/A/${unnamedDrawingMark.glyph}', 'drawing 1/A/${unnamedDrawingMark.glyph}', 'drawing 2/B/x'],
      reason: 'a blank name prints the mark, as the sheet prints it',
    );
  });

  test('a row the TRACK owns is named by its track', () {
    expect(placesOf([drawn('c2', 's1', 's1-f')]), ['drawing Track 1/S1/hey']);
  });

  test('conte ink: the paper by the page it prints, a row by its cut and '
      'its storyboard drawing', () {
    expect(
      placesOf([
        conteInkRowKey(const CutId('c1'), const FrameId('sb1')),
        conteInkPageKey(2),
        conteInkPageKey(0),
      ]),
      ['conte page 1', 'conte page 3', 'conte row 1/2'],
    );
  });

  test('envelope ink: by its cut, once for every box', () {
    expect(
      placesOf([
        envelopeInkBoxKey(const CutId('c2'), 'memo'),
        envelopeInkBoxKey(const CutId('c2'), 'cel-row-3'),
      ]),
      ['envelope 2', 'envelope 2'],
    );
  });

  test('🚨one place for every key: what the project holds no place for is '
      'said too — never dropped, never thrown on', () {
    expect(
      placesOf([
        drawn('c1', 'a', 'deleted-drawing'),
        drawn('c1', 'deleted-row', 'a1'),
        drawn('deleted-cut', 'deleted-row', 'x'),
        conteInkRowKey(const CutId('c1'), const FrameId('long-dead-block')),
        envelopeInkBoxKey(const CutId('deleted-cut'), 'memo'),
        drawn('c1', 'a', 'a1'),
      ]),
      ['drawing 1/A/1', 'gone', 'gone', 'gone', 'gone', 'gone'],
    );
  });
}
