import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
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
    Map<int, TimelineExposure>? timeline,
  }) => Layer(
    id: LayerId(id),
    name: name,
    frames: frames,
    kind: kind,
    timeline: timeline,
  );

  /// A block of `sb1`, written on under [inkId] when it has one.
  TimelineExposure sb1Block(int length, [String inkId = '']) =>
      TimelineExposure.drawing(
        const FrameId('sb1'),
        length: length,
        memo: ExposureMemo(inkId: inkId),
      );

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
            layer(
              'sb',
              'SB',
              [frame('sb1', ' 2 ')],
              kind: LayerKind.storyboard,
              // One drawing exposed three times: two blocks written on,
              // one not.
              timeline: {
                0: sb1Block(8, 'ink-a'),
                8: sb1Block(8),
                16: sb1Block(8, 'ink-b'),
              },
            ),
          ]),
          cut('c2', '2', [
            layer('b', 'B', [frame('b1', 'x')]),
            layer('bg', 'BG', [frame('bg1')], kind: LayerKind.image),
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

  test('🗣️an IMAGE row\'s unnamed cel prints no mark — the row is the '
      'picture, so its name is the whole of the place', () {
    // 유저 2026-09-25: 「이미지레이어는 프레임 이름 없으면 중간나누기
    // 마크가아니라 이름을 안보이게」.
    expect(placesOf([drawn('c2', 'bg', 'bg1')]), ['drawing 2/BG/']);
  });

  test('a row the TRACK owns is named by its track', () {
    expect(placesOf([drawn('c2', 's1', 's1-f')]), ['drawing Track 1/S1/hey']);
  });

  group('🗣️F-284 — a drawing\'s place says where its blocks start', () {
    // 유저 2026-10-04: 「인덱스도 표시 … S1의 15」.
    List<int> startsOf(BrushFrameKey key) =>
        switch (celPlacesOf(project, [key]).single) {
          DrawingCelPlace(:final blockStarts) => blockStarts,
          _ => throw StateError('fixture premise: a drawing'),
        };

    test('every block that shows it, in the order of the row', () {
      expect(startsOf(drawn('c1', 'sb', 'sb1')), [0, 8, 16]);
    });

    test('on the frames of the row\'s OWN axis — a track row\'s are the '
        'track\'s, whichever cut the key was saved under', () {
      final long = Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 7),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'Track 1',
            seLayers: [
              layer(
                's1',
                'S1',
                [frame('hit')],
                kind: LayerKind.se,
                // In the second cut's span: 24 frames in, then 6.
                timeline: {
                  30: const TimelineExposure.drawing(FrameId('hit'), length: 2),
                },
              ),
            ],
            cuts: [cut('c1', '1', const []), cut('c2', '2', const [])],
          ),
        ],
      );
      expect(
        switch (celPlacesOf(long, [drawn('c2', 's1', 'hit')]).single) {
          DrawingCelPlace(:final blockStarts) => blockStarts,
          _ => throw StateError('fixture premise: a drawing'),
        },
        [30],
      );
    });

    test('a drawing no block shows stands nowhere', () {
      final unshown = Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 7),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'Track 1',
            cuts: [
              cut('c1', '1', [
                layer(
                  'a',
                  'A',
                  [frame('shown', '1'), frame('kept', '2')],
                  timeline: {
                    3: const TimelineExposure.drawing(
                      FrameId('shown'),
                      length: 1,
                    ),
                  },
                ),
              ]),
            ],
          ),
        ],
      );
      List<int> starts(String frameId) =>
          switch (celPlacesOf(unshown, [drawn('c1', 'a', frameId)]).single) {
            DrawingCelPlace(:final blockStarts) => blockStarts,
            _ => throw StateError('fixture premise: a drawing'),
          };
      expect(starts('shown'), [3]);
      expect(starts('kept'), isEmpty);
    });
  });

  test('conte ink: a block\'s handwriting by its cut and the drawing the '
      'block shows', () {
    expect(
      placesOf([
        conteInkRowKey(const CutId('c1'), 'ink-b'),
        conteInkRowKey(const CutId('c1'), 'ink-a'),
      ]),
      ['conte row 1/2', 'conte row 1/2'],
      reason: 'two blocks of one drawing are two handwritings, each a '
          'place of its own',
    );
  });

  test('🚨a row key names a BLOCK, not a drawing — the drawing\'s id and '
      'another cut\'s block are no place', () {
    expect(
      placesOf([
        conteInkRowKey(const CutId('c1'), 'sb1'),
        conteInkRowKey(const CutId('c2'), 'ink-a'),
      ]),
      ['gone', 'gone'],
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
        conteInkRowKey(const CutId('c1'), 'long-dead-block'),
        envelopeInkBoxKey(const CutId('deleted-cut'), 'memo'),
        drawn('c1', 'a', 'a1'),
      ]),
      ['drawing 1/A/1', 'gone', 'gone', 'gone', 'gone', 'gone'],
    );
  });
}
