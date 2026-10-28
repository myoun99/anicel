import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart'
    show trackConteRowShown;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/widgets/instant_tap_region.dart'
    show InstantTapRegion;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// 🗣️I-99 (유저 2026-10-28): 「콘티행은 어태치폴더 못가진다는데 그게 일단
/// 버그임. 법 통일해서 가질수있게하고 진행」 — the card's third piece:
/// 「콘티 패널도 어태치 폴더를 그린다 — 타임라인 패널과 같은 법」.
///
/// A 공정 folder filing rows of a track's conte is a seat of its group, and
/// the conte panel draws it as the timeline does: the timeline's head for a
/// folder, over the rows it files, which hang one level in; its fold shuts
/// them, on this rail and in every cut; the conte's fold shuts it with them.
///
/// Cuts a and b, bottom first: the conte, `over1` filed in the folder
/// `proc`, then `over2` — seats 0, +1, +2 (the folder) and +3.
void main() {
  const trackId = TrackId('t1');

  Layer conte(String cut) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    frames: [Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
  );

  Layer rider(String cut, String suffix, {String? folder}) => Layer(
    id: LayerId('$cut-$suffix'),
    name: suffix,
    kind: LayerKind.storyboard,
    attachedToLayerId: LayerId('$cut-conte'),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: AttachedMode.free,
    folderId: folder == null ? null : LayerId('$cut-$folder'),
    frames: [
      Frame(id: FrameId('$cut-$suffix-1'), duration: 6, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-$suffix-1'), length: 6),
    },
  );

  Cut cutOf(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      conte(id),
      rider(id, 'over1', folder: 'proc'),
      createFolderLayer(id: LayerId('$id-proc'), name: '[연출]'),
      rider(id, 'over2'),
    ],
  );

  Project film() => Project(
    id: const ProjectId('conte-folders'),
    name: 'Conte folders',
    createdAt: DateTime.utc(2026, 10, 28),
    tracks: [
      Track(id: trackId, name: 'V1', cuts: [cutOf('a'), cutOf('b')]),
    ],
  );

  Future<EditorSessionManager> pumpPanel(WidgetTester tester) async {
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    await pumpStoryboardHostOn(
      tester,
      session,
      surface: const Size(1400, 760),
      pixelsPerFrame: 12,
    );
    return session;
  }

  Layer row(EditorSessionManager session, String id) {
    for (final cut in session.repository.requireProject().tracks.single.cuts) {
      for (final layer in cut.layers) {
        if (layer.id == LayerId(id)) {
          return layer;
        }
      }
    }
    throw StateError('no row $id');
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  /// The conte row's label at a seat — `conte`, `conte+1`, …
  Finder label(String word) => key('storyboard-$word-label-t1');

  /// The conte row's strip at a seat.
  Finder strip(String word) => key(
    word == 'conte'
        ? 'storyboard-conte-row-t1'
        : 'storyboard-conte-row-t1-$word',
  );

  TimelineLayerControlsRow headOf(WidgetTester tester, String word) =>
      tester.widget<TimelineLayerControlsRow>(
        find.descendant(
          of: label(word),
          matching: find.byType(TimelineLayerControlsRow),
        ),
      );

  /// A row's name on the rail.
  Finder name(String text) => find
      .descendant(
        of: key('storyboard-track-label-rail'),
        matching: find.text(text),
      )
      .first;

  LayerRowAddress seat(int seat) =>
      LayerRowAddress(trackConteRowId(trackId, seat: seat));

  const folderTwirl = 'storyboard-folder-twirl-a-proc';

  testWidgets('the folder stands at its seat over the rows it files — the '
      'timeline\'s head for a folder, its rows one level in', (tester) async {
    await pumpPanel(tester);

    expect(headOf(tester, 'conte+2').layer.id, const LayerId('a-proc'));
    final tops = [
      for (final word in ['conte+3', 'conte+2', 'conte+1', 'conte'])
        tester.getRect(label(word)),
    ];
    for (var index = 1; index < tops.length; index += 1) {
      expect(
        tops[index - 1].bottom,
        tops[index].top,
        reason: 'over2, the folder, over1, the conte — top row first',
      );
    }
    expect(
      [
        for (final word in ['conte+3', 'conte+2', 'conte+1', 'conte'])
          headOf(tester, word).depth,
      ],
      [0, 0, 1, 0],
      reason: 'the row the folder files hangs one level in, as on the '
          'timeline',
    );
    expect(find.named(folderTwirl), findsOneWidget);
    expect(strip('conte+2'), findsOneWidget, reason: 'a strip a seat');
  });

  test('its strip shows its band — the union of the rows it files, as its '
      'timeline row does', () {
    final entries = buildStoryboardTimelineLayout(film());
    Map<int, int> blocksAt(int seat) => {
      for (final entry in trackConteRowShown(
        trackId,
        entries,
        seat: seat,
      ).timeline.entries)
        if (!entry.value.ghost) entry.key: entry.value.length!,
    };

    expect(blocksAt(2), {0: 6, 12: 6}, reason: 'over1\'s block in a and b');
    expect(blocksAt(2), blocksAt(1), reason: '⛔전제: it files over1 alone');
  });

  testWidgets('🚨its fold shuts the rows it files — on this rail, and in '
      'every cut', (tester) async {
    final session = await pumpPanel(tester);

    await tester.tap(find.named(folderTwirl));
    await tester.pumpAndSettle();

    expect(label('conte+1'), findsNothing);
    expect(strip('conte+1'), findsNothing);
    for (final word in ['conte+3', 'conte+2', 'conte']) {
      expect(label(word), findsOneWidget, reason: '$word stays');
    }
    expect(
      [row(session, 'a-proc').collapsed, row(session, 'b-proc').collapsed],
      [true, true],
      reason: 'the head is one: every cut\'s folder shuts',
    );

    await tester.tap(find.named(folderTwirl));
    await tester.pumpAndSettle();

    expect(label('conte+1'), findsOneWidget);
    expect(row(session, 'b-proc').collapsed, isFalse);
  });

  testWidgets('🚨folding the folder while standing on a row it files hands '
      'the stand to the folder, as the timeline\'s fold does', (tester) async {
    final session = await pumpPanel(tester);
    await tester.tap(name('over1'));
    await tester.pumpAndSettle();
    expect(session.currentRow, seat(1), reason: '⛔전제');

    await tester.tap(find.named(folderTwirl));
    await tester.pumpAndSettle();

    expect(session.currentRow, seat(2));
  });

  testWidgets('the conte\'s fold shuts its folder with the rows', (
    tester,
  ) async {
    await pumpPanel(tester);

    await tester.tap(find.named('storyboard-attach-twirl-a-conte'));
    await tester.pumpAndSettle();

    expect(label('conte'), findsOneWidget);
    for (final word in ['conte+3', 'conte+2', 'conte+1']) {
      expect(label(word), findsNothing, reason: '$word folds with its group');
    }
  });

  testWidgets('🚨a row dropped ON the folder is filed in it, in every cut — '
      'the folder lit while the row is held over it', (tester) async {
    final session = await pumpPanel(tester);
    // The first drag selects; the drag that starts inside it moves.
    await tester.dragFrom(
      tester.getCenter(name('over2')),
      const Offset(InstantTapRegion.travelSlop + 2, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    final start = tester.getCenter(name('over2'));
    final to = tester.getCenter(label('conte+2'));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 4; step += 1) {
      await gesture.moveTo(
        Offset.lerp(start, Offset(start.dx, to.dy), step / 4)!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final lit = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'timeline-row-swallow-',
          ),
    );
    expect(lit, findsOneWidget, reason: 'the row the drop goes into lights');
    expect(
      tester.getRect(lit).center.dy,
      closeTo(tester.getRect(label('conte+2')).center.dy, 2),
      reason: 'on the folder\'s row',
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      [row(session, 'a-over2').folderId, row(session, 'b-over2').folderId],
      const [LayerId('a-proc'), LayerId('b-proc')],
    );
  });

  testWidgets('🚨a sweep down the fold column folds the folder and the conte '
      'alike', (tester) async {
    final session = await pumpPanel(tester);
    final start = tester.getCenter(find.named(folderTwirl));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    final to = find.named('storyboard-attach-twirl-a-conte');
    var at = start;
    for (var step = 0; step < 400; step += 1) {
      final gap = tester.getCenter(to).dy - at.dy;
      if (gap.abs() < 1) {
        break;
      }
      at = Offset(start.dx, at.dy + gap.clamp(-8.0, 8.0));
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(row(session, 'a-proc').collapsed, isTrue);
    expect(
      session.railView.collapsedAttachBaseIds.value,
      containsAll(const [LayerId('a-conte'), LayerId('b-conte')]),
    );
  });
}
