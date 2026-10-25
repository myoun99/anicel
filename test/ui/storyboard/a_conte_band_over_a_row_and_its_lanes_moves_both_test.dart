import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// 🚨H20 on the conte (유저 2026-08-23): 「fx랑 블록이랑 같이 움직이게할거면
/// 둘다 유저가 선택하게 할거니까 … 선택한 곳만 움직이게하라고」 — and the
/// board's law for the two panels: 「타임라인 패널에만 있는 것은 콘티 패널에도
/// — 같은 법 · 같은 코드로」. The timeline's half is
/// `a_band_over_a_row_and_its_lanes_moves_both_test`.
///
/// 🧪Measured on master `ae6592342` (2026-10-25, a real mouse): a sweep from
/// S1's cells down into its Position lane drew a band over S1 alone — the
/// rail's head skipped the lanes and the session cut the band out of its
/// own rows, which name none. A press on a lane cell it seemed to cover
/// began a lane selection and the band went; the keys never moved with
/// the sound.
///
/// ★The band holds the lanes it swept, and wherever it is pressed it moves
/// what each of its rows holds — S1's row its sound, the lanes their keys.
const _track = TrackId('t');
const _s1 = LayerId('S1');
const _s2 = LayerId('S2');
const _cell = 30.0;
const _fx = EffectId('v-fx');
const _brightness = 'brightness';

/// S1 holds a two-frame sound at 4 and Position keys at 5 and 7, S2 (one
/// slot up, above S1 on the rail) nothing; the V row's own brightness fx is
/// keyed at 5 and 7 too.
Project _project() => Project(
  id: const ProjectId('p'),
  name: 'P',
  createdAt: DateTime.utc(2026, 10, 25),
  tracks: [
    Track(
      id: _track,
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'C',
          duration: 24,
          canvasSize: const CanvasSize(width: 64, height: 64),
          camera: CutCamera.empty(),
          layers: [
            Layer(
              id: const LayerId('conte'),
              name: 'Conte',
              kind: LayerKind.storyboard,
              frames: const [],
            ),
          ],
        ),
      ],
      effects: [
        LayerEffect(
          id: _fx,
          kind: EffectKind.brightnessContrast,
          parameters: {
            _brightness: EffectParameter(
              track: PropertyTrack<double>().withKey(5, 10).withKey(7, 20),
            ),
          },
        ),
      ],
      seLayers: [
        Layer(
          id: _s1,
          name: 'S1',
          kind: LayerKind.se,
          transformTrack: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>()
                .withKey(5, CanvasPoint(x: 1, y: 1))
                .withKey(7, CanvasPoint(x: 5, y: 5)),
          ),
          frames: [
            Frame(
              id: const FrameId('f'),
              duration: 2,
              name: 'One',
              strokes: const [],
            ),
          ],
          timeline: const {
            4: TimelineExposure.drawing(FrameId('f'), length: 2),
          },
        ),
        Layer(id: _s2, name: 'S2', kind: LayerKind.se, frames: const []),
      ],
    ),
  ],
);

final _s1Row = find.byKey(const ValueKey<String>('storyboard-se-row-0-1'));
final _s2Row = find.byKey(const ValueKey<String>('storyboard-se-row-0-2'));
final _position = find.byKey(
  const ValueKey<String>('storyboard-se-lane-row-0-1-position'),
);
final _transformGroup = find.byKey(
  const ValueKey<String>('storyboard-se-lane-row-0-1-transform-group'),
);
final _vRow = find.byKey(const ValueKey<String>('storyboard-track-row-t'));
final _vLane = find.byKey(
  ValueKey<String>(
    'storyboard-track-lane-row-0-${effectLaneId(_fx, _brightness)}',
  ),
);
final _vLaneRow = LaneRowAddress(
  const LayerId('v-track:t'),
  effectLaneId(_fx, _brightness),
);

/// The conte with S1's Transform lanes open.
Future<EditorSessionManager> _openS1Lanes(WidgetTester tester) async {
  final session = await pumpStoryboardHost(
    tester,
    _project(),
    surface: const Size(1400, 900),
    pixelsPerFrame: _cell,
  );
  session.layerSwitches.toggleLayerLanes(_s1);
  await tester.pumpAndSettle();
  await tester.tap(
    find.named('storyboard-lane-group-toggle-S1-transform-group'),
  );
  await tester.pumpAndSettle();
  return session;
}

/// The middle of [frame]'s cell on the strip [strip].
Offset _at(WidgetTester tester, Finder strip, int frame) => Offset(
  tester.getRect(_s1Row).left + _cell * frame + _cell / 2,
  tester.getCenter(strip).dy,
);

/// A mouse sweep from [from]'s cell [start] to [to]'s cell 7.
Future<void> _sweep(
  WidgetTester tester,
  Finder from,
  Finder to, {
  int start = 4,
}) async {
  final mouse = await tester.startGesture(
    _at(tester, from, start),
    kind: PointerDeviceKind.mouse,
  );
  await mouse.moveBy(const Offset(_cell, 0));
  await tester.pump();
  await mouse.moveTo(_at(tester, to, 7));
  await tester.pump();
  await mouse.up();
  await tester.pumpAndSettle();
}

/// A mouse press on [strip]'s cell 6, carried two cells on and [across]
/// rows' worth of pixels, then let go.
Future<void> _carry(
  WidgetTester tester,
  Finder strip, {
  double across = 0,
}) async {
  final mouse = await tester.startGesture(
    _at(tester, strip, 6),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await mouse.moveBy(const Offset(_cell, 0));
  await tester.pump();
  await mouse.moveBy(Offset(_cell, across));
  await tester.pump();
  await mouse.up();
  await tester.pumpAndSettle();
}

Layer _se(EditorSessionManager session, LayerId id) =>
    session.activeTrack.seLayers.firstWhere((layer) => layer.id == id);

List<int> _sounds(EditorSessionManager session, LayerId id) =>
    _se(session, id).timeline.keys.toList();

List<int> _positionKeys(EditorSessionManager session) =>
    _se(session, _s1).transformTrack.position.keys.keys.toList();

List<int> _vKeys(EditorSessionManager session) => session.activeTrack.effects
    .single
    .parameters[_brightness]!
    .track
    .keys
    .keys
    .toList();

void main() {
  testWidgets('a sweep from S1\'s cells into its Position lane holds every '
      'lane it crossed', (tester) async {
    final session = await _openS1Lanes(tester);

    await _sweep(tester, _s1Row, _position);

    final band = session.trackFrameRangeSelection.value;
    expect(band?.startFrame, 4);
    expect(band?.endFrameExclusive, 8);
    expect(
      band?.spanRows,
      containsAllInOrder(const [
        LayerRowAddress(_s1),
        LaneRowAddress(_s1, 'transform-group'),
        LaneRowAddress(_s1, 'position'),
      ]),
      reason: 'the rows the rail drew between the press and the pointer',
    );
    expect(band?.spanRows.last, const LaneRowAddress(_s1, 'position'));
  });

  for (final (pressed, strip) in [
    ('its Position lane', _position),
    ('S1\'s cells', _s1Row),
  ]) {
    testWidgets('dragged by $pressed, the band carries the sound and the keys '
        'two frames — one undo puts both back', (tester) async {
      final session = await _openS1Lanes(tester);
      await _sweep(tester, _s1Row, _position);
      final rows = session.trackFrameRangeSelection.value!.spanRows;

      await _carry(tester, strip);

      expect(_sounds(session, _s1), [6]);
      expect(_positionKeys(session), [7, 9]);
      final band = session.trackFrameRangeSelection.value;
      expect(band?.startFrame, 6, reason: 'the band went with them');
      expect(band?.spanRows, rows, reason: 'over the rows it held');

      session.undo();
      await tester.pumpAndSettle();
      expect(_sounds(session, _s1), [4]);
      expect(_positionKeys(session), [5, 7]);
    });

    testWidgets('carried by $pressed onto S2, the sound changes rows and the '
        'keys slide on S1\'s lane', (tester) async {
      final session = await _openS1Lanes(tester);
      await _sweep(tester, _s1Row, _position);

      await _carry(
        tester,
        strip,
        across: tester.getCenter(_s2Row).dy - tester.getCenter(strip).dy,
      );

      expect(_sounds(session, _s2), [6]);
      expect(_sounds(session, _s1), isEmpty);
      expect(
        _positionKeys(session),
        [7, 9],
        reason: 'keys stay on their lane (a-lane-press-clears-a-mixed-run-Q1)',
      );
    });
  }

  testWidgets('Delete takes the band\'s sound and the keys its lane holds', (
    tester,
  ) async {
    final session = await _openS1Lanes(tester);
    await _sweep(tester, _s1Row, _position);

    session.cells.deleteCellAtCurrentFrame();
    await tester.pumpAndSettle();

    expect(_sounds(session, _s1), isEmpty);
    expect(_positionKeys(session), isEmpty);
  });

  testWidgets('a click on a lane inside the band lets it go', (tester) async {
    final session = await _openS1Lanes(tester);
    await _sweep(tester, _s1Row, _position);

    final mouse = await tester.startGesture(
      _at(tester, _position, 6),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(session.trackFrameRangeSelection.value, isNull);
    expect(session.laneRangeSelection.value, isNull);
    expect(_positionKeys(session), [5, 7]);
  });

  testWidgets('carried by its Position lane one row up, onto the lane above '
      'it, the sound stays on S1 — the rows count from the lane', (
    tester,
  ) async {
    final session = await _openS1Lanes(tester);
    await _sweep(tester, _s1Row, _position);

    await _carry(
      tester,
      _position,
      across:
          tester.getCenter(_transformGroup).dy -
          tester.getCenter(_position).dy,
    );

    expect(_sounds(session, _s1), [6]);
    expect(_sounds(session, _s2), isEmpty);
    expect(_positionKeys(session), [7, 9]);
  });

  testWidgets('a band from the V row\'s cells up into S1\'s Position lane '
      'holds S1\'s keys but not its sound — dragged by the lane, the keys '
      'go alone', (tester) async {
    final session = await _openS1Lanes(tester);
    await _sweep(tester, _vRow, _position);
    final rows = session.trackFrameRangeSelection.value?.spanRows;
    expect(
      rows,
      containsAllInOrder(const [
        LaneRowAddress(_s1, 'position'),
        TrackRowAddress(_track),
      ]),
      reason: 'premise: the lane and the V row, S1\'s own row not',
    );
    expect(rows, isNot(contains(const LayerRowAddress(_s1))));

    await _carry(tester, _position);

    expect(_positionKeys(session), [7, 9]);
    expect(_sounds(session, _s1), [4], reason: 'its row was not swept');
  });

  testWidgets('a band that holds no whole sound still carries the keys its '
      'lane holds', (tester) async {
    final session = await _openS1Lanes(tester);
    await _sweep(tester, _s1Row, _position, start: 6);
    expect(session.trackFrameRangeSelection.value?.startFrame, 6);

    await _carry(tester, _position);

    expect(_sounds(session, _s1), [4], reason: 'its sound was not in it');
    expect(_positionKeys(session), [5, 9]);
  });

  testWidgets('a band from S1\'s cells down into the V row\'s fx lane, '
      'dragged by that lane, carries the fx keys with the sound', (
    tester,
  ) async {
    final session = await _openVLanes(tester);
    await _sweep(tester, _s1Row, _vLane);
    expect(
      session.trackFrameRangeSelection.value?.spanRows,
      contains(_vLaneRow),
      reason: 'premise: the band holds the fx lane',
    );

    await _carry(tester, _vLane);

    expect(_sounds(session, _s1), [6]);
    expect(_vKeys(session), [7, 9]);
  });

  testWidgets('a band from the V row\'s cells into its fx lane holds no '
      'sound, and dragged by the lane carries the fx keys alone', (
    tester,
  ) async {
    final session = await _openVLanes(tester);
    await _sweep(tester, _vRow, _vLane);
    final rows = session.trackFrameRangeSelection.value?.spanRows;
    expect(
      rows,
      containsAllInOrder([const TrackRowAddress(_track), _vLaneRow]),
    );

    await _carry(tester, _vLane);

    expect(_vKeys(session), [7, 9]);
    expect(_sounds(session, _s1), [4]);
    expect(
      session.trackFrameRangeSelection.value?.spanRows,
      rows,
      reason: 'over the rows it held — no S row joins it',
    );
  });
}

/// The conte with the V row's fx lane open.
Future<EditorSessionManager> _openVLanes(WidgetTester tester) async {
  final session = await pumpStoryboardHost(
    tester,
    _project(),
    surface: const Size(1400, 900),
    pixelsPerFrame: _cell,
  );
  await tester.tap(find.named('storyboard-track-lane-toggle-t'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.named(
      'storyboard-lane-group-toggle-v-track:t-${effectGroupLaneId(_fx)}',
    ),
  );
  await tester.pumpAndSettle();
  return session;
}
