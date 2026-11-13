import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:anicel/src/ui/widgets/named.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

/// 🔬Card timeline-playback-drops-every-row-image-each-frame (11-07): a
/// PLAYING TIMELINE'S ROWS KEEP THEIR IMAGES — between page turns, no row
/// region takes another, and each is drawn from an image: its own, or the
/// dock's above it, which holds its pixels too.
///
/// ↩️Measured as ~9300 drops in 300 frames — every row, every frame — by a
/// measure that read a row not drawn from its own image as one that had
/// dropped it. Under the dock's image a row is not in the scene at all
/// ([RenderStillRaster.debugDrawnFromImage] says so): what this reads is
/// what the scene draws it from ([RenderStillRaster.debugDrawnFrom]).
///
/// The rows a timeline plays past: the drawings' cells and rails, a row
/// twirled open to its keyed lanes — whose values follow the playhead, a
/// tick each region draws live between its strata — and an S row.
void main() {
  const layers = 4;
  const frames = 240;
  const block = 6;

  Layer row(String id, {LayerKind kind = LayerKind.animation}) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: [
      for (var i = 0; i < frames ~/ block; i += 1)
        Frame(
          id: FrameId('$id-$i'),
          duration: 1,
          strokes: const [],
          // 🚨THE FRAMES HOLD NOTHING TO LAY, AN S ROW'S BLOCKS NO WRITING:
          // the run plays in the test's own time. A frame with something on
          // it is laid by the engine in time of its own, which a test's
          // pumps never give, and the run waits on its first frame for it
          // — an S block's name is a row of the frame's picture since the
          // SE name tag went into it (the-flutter-fx-chain-is-a-second-chain
          // ①). 🔬2026-11-13: named, its four pictures landed after the
          // test had ended, the run still on frame 0.
          name: kind == LayerKind.se ? null : '${i + 1}',
        ),
    ],
    timeline: {
      for (var i = 0; i < frames ~/ block; i += 1)
        i * block: TimelineExposure.drawing(FrameId('$id-$i'), length: block),
    },
  );

  Layer keyed(String id) => row(id).copyWith(
    lanesExpanded: true,
    expandedLaneGroups: {transformGroupHeaderLane.laneId},
    transformTrack: TransformTrack.empty().copyWith(
      rotation: PropertyTrack<double>().withKey(0, 0).withKey(frames, 360),
    ),
  );

  Project project() => Project(
    id: const ProjectId('playing-rows'),
    name: 'Playing rows',
    createdAt: DateTime.utc(2026, 11, 7),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-0'),
            name: 'cut-0',
            duration: frames,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              keyed('k0'),
              for (var r = 0; r < layers; r += 1) row('r$r'),
            ],
          ),
        ],
        seLayers: [row('s0', kind: LayerKind.se)],
      ),
    ],
  );

  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    StaticRaster.debugCapturePaysOverride = false;
  });
  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  String rowNameOf(Element element) {
    String? name;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget case Named(name: final named?)) {
        name = named;
        return false;
      }
      return true;
    });
    return name ?? '${element.widget}';
  }

  /// Every row's region the dock built, by the row it stands in.
  Map<String, RenderStillRaster> rowsOf(WidgetTester tester) => {
    for (final element in find.byType(StillRaster).evaluate())
      if (element.renderObject case final RenderStillRaster region
          when region.debugLabel == 'row')
        rowNameOf(element): region,
  };

  /// Whether the scene draws [region] from an image: its own, or that of a
  /// region above it.
  bool drawnFromAnImage(RenderStillRaster region) =>
      region.debugDrawnFrom != null;

  Future<void> tick(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 42));

  testWidgets('a playing timeline\'s rows keep their images between page '
      'turns', (tester) async {
    await tester.binding.setSurfaceSize(const Size(4000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: project()),
      ),
    );
    await tester.pumpAndSettle();
    final playback = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .playbackRig
        .playback;
    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );

    // What playing changes once settles, and every row takes its image.
    var rows = <String, RenderStillRaster>{};
    for (var i = 0; i < 120; i += 1) {
      await tick(tester);
      rows = rowsOf(tester);
      if (rows.values.every(
        (region) => region.rasterBytes > 0 && drawnFromAnImage(region),
      )) {
        break;
      }
    }
    expect(
      rows.keys.where((name) => name.endsWith('-k0-rotation')),
      hasLength(2),
      reason: '⛔premise: the keyed lane\'s rail row and its cells row',
    );
    expect(
      rows.keys.where((name) => name.endsWith('-s0')),
      isNotEmpty,
      reason: '⛔premise: the S row',
    );
    final anImageless = [
      for (final MapEntry(key: name, value: region) in rows.entries)
        if (region.rasterBytes == 0 || !drawnFromAnImage(region))
          '$name (${region.standDown.name})',
    ];
    // Not a premise: a row that never takes its image as it plays is the
    // drop this pins, and each mutant of the region's stillness lands here.
    expect(anImageless, isEmpty, reason: 'a row took no image as it played');

    final taken = {
      for (final MapEntry(key: name, value: region) in rows.entries)
        name: region.debugCaptureCount,
    };
    final standing = {
      for (final MapEntry(key: name, value: region) in rows.entries)
        name: region.localToGlobal(Offset.zero),
    };
    final from = playback.globalFrameIndexListenable.value!;
    final dropped = <String>{};
    for (var i = 0; i < 24; i += 1) {
      await tick(tester);
      for (final MapEntry(key: name, value: region) in rowsOf(tester).entries) {
        if (region.rasterBytes == 0 ||
            !drawnFromAnImage(region) ||
            region.debugCaptureCount != taken[name]) {
          dropped.add('$name (${region.standDown.name}) at tick $i');
        }
      }
    }
    expect(
      playback.globalFrameIndexListenable.value,
      greaterThanOrEqualTo(from + 20),
      reason: '⛔premise: it played',
    );
    expect(
      {
        for (final MapEntry(key: name, value: region) in rowsOf(tester).entries)
          name: region.localToGlobal(Offset.zero),
      },
      standing,
      reason: '⛔premise: no page turned — a turn moves every row',
    );
    expect(dropped, isEmpty, reason: 'a row let its image go as it played');

    playback.stop();
    await tester.pump();
  });
}
