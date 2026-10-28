import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show flagLaneWord;
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagUnderlineLaneId;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️F-475 (유저 2026-10-26): 「다른버튼도 조사」 — a lane's ◆ and a flag
/// lane's ring are buttons of the rail too, so a drag begun on one presses
/// the same button on every lane it crosses: each lane keyed — or flagged —
/// as the press left the first, at the frame its own row stands on, and
/// one undo takes the stroke back.
///
/// On S1 in cut 2, with the key cut 1 made still on the row (F-102's
/// fixture): the timeline's rail stands on the cut's own frames and the
/// storyboard's on the track's, so a stroke that pressed each lane at a
/// frame of its own reading would key cut 1's frames or shift cut 2's twice.
EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

/// Cut 1 keys S1's Rotation at global frame 2; a second cut is made, which
/// makes it active, and the playhead parks on its local frame 3. Returns the
/// global frame the playhead stands on.
int _keyInCut1ThenStandInCut2(EditorSessionManager session) {
  final se = session.activeTrack.seLayers.first;
  session.laneVerbs.updateLayerTransformTrack(
    se.id,
    TransformTrack.empty().copyWith(
      rotation: PropertyTrack(keys: {2: const PropertyKey(30.0)}),
    ),
  );
  session.cutVerbs.createCut();
  session.selectFrameIndex(3);
  final standing = session.activeCutGlobalStartFrame + 3;
  expect(
    standing,
    greaterThan(2),
    reason: 'fixture premise: cut 2 stands after the key cut 1 made',
  );
  return standing;
}

Layer _s1(EditorSessionManager session) => session.activeTrack.seLayers.first;

/// The frames each of S1's transform lanes is keyed at, by lane.
Map<String, List<int>> _transformKeys(EditorSessionManager session) {
  final track = _s1(session).transformTrack;
  List<int> framesOf(PropertyTrack<Object?> lane) => [...lane.keys.keys]
    ..sort();
  return {
    'anchor-point': framesOf(track.anchorPoint),
    'position': framesOf(track.position),
    'scale': framesOf(track.scale),
    'rotation': framesOf(track.rotation),
    'opacity': framesOf(track.opacity),
  };
}

/// S1's name tag as it stands at the global [frame].
SeNameTag _tagAt(EditorSessionManager session, int frame) =>
    (_s1(session).seNameTag ?? const SeNameTag()).resolveAt(frame);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A mouse stroke from [from]'s centre straight down or up to [to]'s, in
/// one column. 🚨MOUSE: a finger is no timeline edit device unless one-finger
/// drawing is on, so a touch here would measure nothing.
Future<void> _sweep(WidgetTester tester, Finder from, Finder to) async {
  await tester.ensureVisible(from);
  await tester.pumpAndSettle();
  final start = tester.getCenter(from);
  final end = tester.getCenter(to);
  expect(
    (end.dx - start.dx).abs(),
    lessThan(6),
    reason: 'one column — the sweep paints by the column it began in',
  );
  expect(
    (end.dy - start.dy).abs(),
    greaterThan(40),
    reason: 'and rows apart, or the stroke crosses nothing',
  );
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  for (var step = 1; step <= 8; step += 1) {
    await gesture.moveTo(Offset.lerp(start, end, step / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<EditorSessionManager> _timelineInCut2(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  final session = _sessionOf(tester);
  _keyInCut1ThenStandInCut2(session);
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
  await _tapVisible(
    tester,
    find.named('timeline-lane-toggle-${_s1(session).id.value}'),
  );
  return session;
}

void main() {
  group('the ◆ column', () {
    testWidgets('🚨a stroke down the TIMELINE\'s ◆s keys every lane it '
        'crosses at the playhead — a lane keyed there already stays keyed, '
        'cut 1\'s key stays, and one undo takes the stroke back', (
      tester,
    ) async {
      final session = await _timelineInCut2(tester);
      final se = _s1(session).id.value;
      final standing = session.activeCutGlobalStartFrame + 3;
      await _tapVisible(
        tester,
        find.named('timeline-lane-group-toggle-$se-transform-group'),
      );
      Finder diamond(String laneId) => find.byKey(
        ValueKey<String>('timeline-lane-key-toggle-$se-$laneId'),
      );
      // Scale is keyed there already, by its own ◆ — so it agrees with
      // what the stroke spreads and is left alone.
      await _tapVisible(tester, diamond('scale'));
      expect(_transformKeys(session)['scale'], [standing]);
      final undoDepth = session.historyManager.undoCount;

      await _sweep(tester, diamond('anchor-point'), diamond('opacity'));

      expect(_transformKeys(session), {
        'anchor-point': [standing],
        'position': [standing],
        'scale': [standing],
        'rotation': [2, standing],
        'opacity': [standing],
      }, reason: 'every lane keyed at the frame the playhead stands on');
      expect(
        session.historyManager.undoCount,
        undoDepth + 1,
        reason: 'one stroke, one undo',
      );

      session.undo();
      await tester.pumpAndSettle();

      expect(_transformKeys(session), {
        'anchor-point': <int>[],
        'position': <int>[],
        'scale': [standing],
        'rotation': [2],
        'opacity': <int>[],
      });
    });

    testWidgets('🚨a stroke that UNKEYS spreads that: the ◆ pressed takes its '
        'key away, and so does every lane the stroke crosses', (tester) async {
      final session = await _timelineInCut2(tester);
      final se = _s1(session).id.value;
      final standing = session.activeCutGlobalStartFrame + 3;
      await _tapVisible(
        tester,
        find.named('timeline-lane-group-toggle-$se-transform-group'),
      );
      Finder diamond(String laneId) => find.byKey(
        ValueKey<String>('timeline-lane-key-toggle-$se-$laneId'),
      );
      for (final laneId in ['position', 'rotation', 'opacity']) {
        await _tapVisible(tester, diamond(laneId));
      }
      expect(_transformKeys(session)['rotation'], [2, standing]);

      await _sweep(tester, diamond('opacity'), diamond('position'));

      expect(_transformKeys(session), {
        'anchor-point': <int>[],
        'position': <int>[],
        'scale': <int>[],
        'rotation': [2],
        'opacity': <int>[],
      }, reason: 'cut 1\'s key is no frame the playhead stands on');
    });

    testWidgets('🚨a stroke down the STORYBOARD\'s ◆s on S1 keys every lane at '
        'the global frame its labels read — not shifted by the cut start a '
        'second time', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final standing = _keyInCut1ThenStandInCut2(session);
      await pumpStoryboardHostOn(
        tester,
        session,
        surface: const Size(1600, 1400),
        pixelsPerFrame: 12,
      );
      final se = _s1(session).id.value;
      await _tapVisible(tester, find.named('storyboard-lane-toggle-$se'));
      await _tapVisible(
        tester,
        find.named('storyboard-lane-group-toggle-$se-transform-group'),
      );
      Finder diamond(String laneId) => find.byKey(
        ValueKey<String>('storyboard-lane-key-toggle-$se-$laneId'),
      );

      await _sweep(tester, diamond('anchor-point'), diamond('opacity'));

      expect(_transformKeys(session), {
        'anchor-point': [standing],
        'position': [standing],
        'scale': [standing],
        'rotation': [2, standing],
        'opacity': [standing],
      });
    });

    testWidgets('🚨a stroke ACROSS the x-sheet\'s ◆s keys every lane column it '
        'crosses at the frame the sheet stands on', (tester) async {
      const draw = LayerId('draw');
      final session = await pumpTimelineHost(
        tester,
        Project(
          id: const ProjectId('key-sweep'),
          name: 'Key sweep',
          createdAt: DateTime.utc(2026, 10, 27),
          tracks: [
            Track(
              id: const TrackId('t'),
              name: 'V',
              cuts: [
                Cut(
                  id: const CutId('c'),
                  name: 'C',
                  duration: 12,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [Layer(id: draw, name: 'Drawing', frames: const [])],
                ),
              ],
            ),
          ],
        ),
        surface: const Size(1400, 1000),
      );
      session.selectFrameIndex(5);
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.named('timeline-lane-toggle-draw'));
      await _tapVisible(
        tester,
        find.named('timeline-lane-group-toggle-draw-transform-group'),
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-orientation-toggle-button'),
        ),
      );
      await tester.pumpAndSettle();
      Finder diamond(String laneId) =>
          find.byKey(ValueKey<String>('xsheet-lane-key-toggle-draw-$laneId'));
      await tester.ensureVisible(diamond('position'));
      await tester.pumpAndSettle();
      final from = tester.getCenter(diamond('position'));
      final to = tester.getCenter(diamond('rotation'));
      expect(
        (to.dx - from.dx).abs(),
        greaterThan((to.dy - from.dy).abs()),
        reason: '⛔전제: the sheet stands its lanes side by side',
      );

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 1; step <= 8; step += 1) {
        await gesture.moveTo(
          Offset(from.dx + (to.dx - from.dx) * step / 8, from.dy),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final track = session.layers
          .singleWhere((layer) => layer.id == draw)
          .transformTrack;
      expect(
        {
          'position': [...track.position.keys.keys],
          'scale': [...track.scale.keys.keys],
          'rotation': [...track.rotation.keys.keys],
        },
        {
          'position': [5],
          'scale': [5],
          'rotation': [5],
        },
      );
    });
  });

  group('the flag column', () {
    testWidgets('🚨a stroke down the TIMELINE\'s flag rings sets every flag '
        'it crosses as the press set the first — the colours between are no '
        'flags — and one undo takes the stroke back', (tester) async {
      final session = await _timelineInCut2(tester);
      final se = _s1(session).id.value;
      final standing = session.activeCutGlobalStartFrame + 3;
      await _tapVisible(
        tester,
        find.named('timeline-lane-group-toggle-$se-name-tag-group'),
      );
      Finder ring(String member) => find.byKey(
        ValueKey<String>('timeline-lane-toggle-$se-name-tag:$member'),
      );
      final before = _tagAt(session, standing);
      expect(
        (
          bold: before.style.bold,
          italic: before.style.italic,
          underline: before.style.underline,
          strikethrough: before.style.strikethrough,
          showLine: before.showLine,
        ),
        (
          bold: true,
          italic: false,
          underline: false,
          strikethrough: false,
          showLine: true,
        ),
        reason:
            'fixture premise: the name tag\'s own look — two flags on, '
            'three off between them',
      );
      final undoDepth = session.historyManager.undoCount;

      await _sweep(tester, ring('bold'), ring('show-line'));

      final after = _tagAt(session, standing);
      expect(
        (
          bold: after.style.bold,
          italic: after.style.italic,
          underline: after.style.underline,
          strikethrough: after.style.strikethrough,
          showLine: after.showLine,
        ),
        (
          bold: false,
          italic: false,
          underline: false,
          strikethrough: false,
          showLine: false,
        ),
        reason:
            'the press turned Bold off, and the stroke turned off the one '
            'flag it crossed that was on — at the frame the playhead '
            'stands on',
      );
      final keys = _s1(session).seNameTag!.track!;
      expect(
        {
          'bold': [...keys.bold.keys.keys],
          'showLine': [...keys.showLine.keys.keys],
        },
        {
          'bold': [standing],
          'showLine': [standing],
        },
        reason: 'each keyed at the frame the playhead stands on',
      );
      expect(
        [keys.nameInk, keys.boxColor, keys.lineInk].every(
          (lane) => lane.isEmpty,
        ),
        isTrue,
        reason: 'the inks between the flags are no flags, and stay unkeyed',
      );
      expect(
        session.historyManager.undoCount,
        undoDepth + 1,
        reason: 'one stroke, one undo',
      );

      session.undo();
      await tester.pumpAndSettle();

      final undone = _tagAt(session, standing);
      expect((bold: undone.style.bold, showLine: undone.showLine), (
        bold: true,
        showLine: true,
      ));
    });

    testWidgets('🚨a stroke down the STORYBOARD\'s flag rings on S1 sets them '
        'at the global frame its labels read', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final standing = _keyInCut1ThenStandInCut2(session);
      await pumpStoryboardHostOn(
        tester,
        session,
        surface: const Size(1600, 1400),
        pixelsPerFrame: 12,
      );
      final se = _s1(session).id.value;
      await _tapVisible(tester, find.named('storyboard-lane-toggle-$se'));
      await _tapVisible(
        tester,
        find.named('storyboard-lane-group-toggle-$se-name-tag-group'),
      );
      Finder ring(String member) => find.byKey(
        ValueKey<String>('storyboard-lane-toggle-$se-name-tag:$member'),
      );
      // The underline is OFF where the playhead stands and ON a frame on: a
      // row read at any frame but the one it stands on — the cut's own
      // frame taken for the track's lands the cut's start further on —
      // finds it on already and passes it by.
      expect(
        session.activeCutGlobalStartFrame,
        greaterThan(1),
        reason: 'fixture premise: the wrong frame lies past the ON key',
      );
      for (final (frame, on) in [(standing - 1, false), (standing + 1, true)]) {
        session.laneVerbs.setLaneValueAt(
          _s1(session).id,
          seNameTagUnderlineLaneId,
          frame,
          flagLaneWord(on),
          frameIsGlobal: true,
          description: 'the underline around the playhead',
          scaleLinked: false,
        );
      }
      await tester.pumpAndSettle();
      expect(
        _tagAt(session, standing).style.underline,
        isFalse,
        reason: 'fixture premise: off where the playhead stands',
      );

      await _sweep(tester, ring('italic'), ring('strikethrough'));

      final after = _tagAt(session, standing);
      expect(
        (
          italic: after.style.italic,
          underline: after.style.underline,
          strikethrough: after.style.strikethrough,
        ),
        (italic: true, underline: true, strikethrough: true),
      );
      final keys = _s1(session).seNameTag!.track!;
      expect(
        {
          'italic': [...keys.italic.keys.keys]..sort(),
          'underline': [...keys.underline.keys.keys]..sort(),
          'strikethrough': [...keys.strikethrough.keys.keys]..sort(),
        },
        {
          'italic': [standing],
          'underline': [standing - 1, standing, standing + 1],
          'strikethrough': [standing],
        },
        reason: 'each keyed at the frame the playhead stands on',
      );
    });
  });
}
