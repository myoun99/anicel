import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;

/// UI-R5 ③b: the storyboard says where you STAND, as the timeline does —
/// its standing cell, which paints nothing since F-212 (the playhead's wash
/// says it) but still tells semantics and the probes which row you are on.
///
/// The oracle is the same sentence on every row kind: the standing cell IS
/// the intersection of the playhead column and the row you stand on. It is
/// measured against the row's own widget rather than against the panel's
/// row table, so a table that drifts out of step with the rows it mirrors
/// fails here instead of standing on a neighbour.
Cut _cut(String id, int duration) {
  return Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(
        id: LayerId('$id-cel'),
        name: 'A',
        frames: const [],
        timeline: const {},
      ),
    ],
  );
}

/// The V row's own lanes are its EFFECT chain since the transform teardown, so
/// the fixture carries one — otherwise the row's twirl-down is empty and there
/// is no V lane row to stand on.
const _trackEffect = EffectId('sb-fx');

Project _project() {
  return Project(
    id: const ProjectId('sb-standing-project'),
    name: 'SB Standing',
    createdAt: DateTime.utc(2026, 8, 9),
    tracks: [
      Track(
        id: const TrackId('sb-track'),
        name: 'Video',
        cuts: [_cut('cut-1', 8), _cut('cut-2', 6)],
        effects: [
          LayerEffect(
            id: _trackEffect,
            kind: EffectKind.brightnessContrast,
            parameters: {'brightness': EffectParameter(value: 0.4)},
          ),
        ],
        seLayers: [
          Layer(
            id: const LayerId('se-row-1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(
                id: const FrameId('f-one'),
                duration: 3,
                name: 'One!',
                strokes: const [],
              ),
            ],
            timeline: const {
              1: TimelineExposure.drawing(FrameId('f-one'), length: 3),
            },
          ),
        ],
      ),
    ],
  );
}

void main() {
  Future<void> pumpStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
  }

  Rect standingRect(WidgetTester tester) => tester.getRect(
    find.byKey(const ValueKey<String>('storyboard-standing-cell')),
  );

  Rect playheadRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey<String>('storyboard-playhead')));

  void expectStandingOnRow(
    WidgetTester tester,
    String rowKey, {
    String? reason,
  }) {
    final standing = standingRect(tester);
    final row = tester.getRect(find.byKey(ValueKey<String>(rowKey)));
    final playhead = playheadRect(tester);
    expect(standing.left, moreOrLessEquals(playhead.left), reason: reason);
    expect(standing.width, moreOrLessEquals(playhead.width), reason: reason);
    expect(standing.top, moreOrLessEquals(row.top), reason: reason);
    expect(standing.height, moreOrLessEquals(row.height), reason: reason);
  }

  testWidgets('the V row you land on stands on the cell the playhead crosses', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    // Nothing picked yet: the rail rests on the V row.
    expectStandingOnRow(
      tester,
      'storyboard-track-row-sb-track',
      reason: 'the standing cell belongs to the row the rail is resting on',
    );

    // Park the playhead off frame 0 so 'follows the cursor' is a claim with
    // something to fail: at the origin every wrong x is also the right one.
    final area = find.byKey(
      const ValueKey<String>('storyboard-track-timeline-area-sb-track'),
    );
    final areaRect = tester.getRect(area);
    final cell = playheadRect(tester).width;
    await tester.tapAt(
      Offset(areaRect.left + 5.5 * cell, areaRect.top + areaRect.height / 2),
    );
    await tester.pumpAndSettle();

    expect(
      playheadRect(tester).left,
      greaterThan(areaRect.left + cell),
      reason: 'the press really moved the playhead down the axis',
    );
    expectStandingOnRow(tester, 'storyboard-track-row-sb-track');
  });

  testWidgets('standing on an S row takes the standing cell with it', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    final vStanding = standingRect(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('storyboard-se-label-sb-track-1'),
        ),
        matching: find.text('S1'),
      ),
    );
    await tester.pumpAndSettle();

    expectStandingOnRow(tester, 'storyboard-se-row-0-1');
    expect(
      standingRect(tester).top,
      isNot(moreOrLessEquals(vStanding.top)),
      reason: 'the standing cell really moved off the V row',
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-standing-cell')),
      findsOneWidget,
      reason: 'exactly one row is stood on, so exactly one standing cell',
    );
  });

  /// Twirls the V row's lanes open, then its EFFECT group. There is no
  /// Transform group in between any more — a track row does not own one — so
  /// the fx chain is the whole twirl-down.
  Future<void> twirlOpenVLanes(WidgetTester tester) async {
    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-toggle-sb-track'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-group-toggle-v-track:sb-track-'
          '${effectGroupLaneId(_trackEffect)}',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // `scrollToAndTap` went with the FADE row's test. ⚠️Its reason has NOT gone
  // away and the next test that reaches a twirled-open V lane needs it back:
  // those lanes sit at the BOTTOM of the group, so every row the rail gains
  // pushes them past the viewport's clip — where `getRect` still reports a
  // layout position but a tap cannot land, which reads as "standing never
  // moved" rather than as an off-screen target. `ensureVisible` first; the rail
  // and the strips share ONE vertical viewport, so the scroll moves both and
  // the standing-cell/row comparison stays valid.
  //
  // The FADE row's test itself is gone with the cut-fade envelope: the V row's
  // Opacity lane no longer exists, and the fade it drew is F.I/F.O spans on the
  // transition row.

  /// 🚨EVERY DEVICE, because the bug was a device-shaped accident.
  ///
  /// The host's outermost `Listener` claims the panel on pointer-DOWN, and
  /// dispatch is deepest-first, so that claim ran LAST on every press. It
  /// claimed `selectedRow` — the getter that answers 「which RAIL row is
  /// lit」 and collapses a lane to its track — so it un-stood you from the
  /// lane the press had just stood on.
  ///
  /// ⛔A finger hid it: touch stood on the RELEASE, after the claim, while
  /// a mouse stood on the DOWN, before it. This case drove only `tapAt`
  /// (touch), so it stayed green while the mouse was broken. Lifting the
  /// finger's carve-out (터치 묘화 ON) is what made it speak.
  ///
  /// ⛔`trackpad` is left out and the reason is the FRAMEWORK's, not a
  /// convenience: `WidgetController.startGesture` opens a trackpad gesture
  /// with `panZoomStart`, never a pointer down (flutter_test's own doc:
  /// 「if kind is set to PointerDeviceKind.trackpad, the gesture will start
  /// with a panZoomStart gesture」). A laptop trackpad CLICK arrives as a
  /// mouse pointer, which the loop already covers.
  for (final kind in PointerDeviceKind.values.where(
    (kind) => kind != PointerDeviceKind.trackpad,
  )) {
    testWidgets('standing on a V LANE row stands on the lane, not its track '
        'row (${kind.name})', (tester) async {
      await pumpStoryboard(tester);
      await twirlOpenVLanes(tester);

      // Stand on the effect's parameter lane by pressing its band — the
      // storyboard's own press path (R5 ③a), through the real host
      // wiring. The lane KIND changed with the teardown; the contract
      // did not.
      final laneId = effectLaneId(_trackEffect, 'brightness');
      final laneRow = find.byKey(
        ValueKey<String>('storyboard-track-lane-row-0-$laneId'),
      );
      await tester.ensureVisible(laneRow);
      await tester.pumpAndSettle();
      final rowRect = tester.getRect(laneRow);
      final gesture = await tester.startGesture(
        Offset(rowRect.left + 6, rowRect.center.dy),
        kind: kind,
      );
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pumpAndSettle();

      expectStandingOnRow(tester, 'storyboard-track-lane-row-0-$laneId');
      expect(
        find.byKey(const ValueKey<String>('storyboard-standing-cell')),
        findsOneWidget,
      );
    });
  }

  // 🗣️유저 2026-09-11: 「트랜스폼행에서 더블클릭으로 편집창 안열리는것등
  // 이런거 싹 법 하나로 통일」 — on the storyboard's lanes too, through this
  // panel's own two verbs: an empty cell is keyed, a key opens the common
  // key window.
  testWidgets('a DOUBLE tap on a V lane keys an empty cell, and on the key '
      'opens the common key window', (tester) async {
    late ProjectRepository repository;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: _project(),
          onRepositoryCreated: (created) => repository = created,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    await twirlOpenVLanes(tester);

    final laneId = effectLaneId(_trackEffect, 'brightness');
    final laneRow = find.byKey(
      ValueKey<String>('storyboard-track-lane-row-0-$laneId'),
    );
    await tester.ensureVisible(laneRow);
    await tester.pumpAndSettle();
    final rowRect = tester.getRect(laneRow);
    final at = Offset(rowRect.left + 6, rowRect.center.dy);
    Future<void> doubleTap() async {
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
    }

    PropertyTrack<double> brightness() => repository
        .requireProject()
        .tracks
        .single
        .effects
        .single
        .parameterOf('brightness')
        .track;

    expect(brightness().isEmpty, isTrue, reason: 'fixture: no key yet');
    await doubleTap();
    expect(brightness().isEmpty, isFalse, reason: 'the empty cell was keyed');
    expect(find.text('Rename key'), findsNothing);

    await doubleTap();
    expect(
      find.text('Rename key'),
      findsOneWidget,
      reason: 'the key opens its window',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-cancel-button')),
    );
    await tester.pumpAndSettle();
  });
}
