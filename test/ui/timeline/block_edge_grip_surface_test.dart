import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/theme/conte_ink.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart'
    show TimelineRowGripTarget;

import 'timeline_row_chrome_probe.dart';

/// An edge's ink is decided by the COLOR it sits on, not by the theme
/// (feedback #11 gave it two inks by surface; 2026-08-17 unified the pick
/// with the block text's ground law): a paper block — the purple paper
/// included — takes the black bar, the dark cut-block plate takes the
/// white one, and no bar wears an outline anywhere. A triangle over more
/// than one of them — the storyboard's label bands on its black plate —
/// takes each one's ink where it stands on it (2026-09-26).
const _trackId = TrackId('ink-track');

Project _project() => Project(
  id: const ProjectId('ink-project'),
  name: 'Ink',
  createdAt: DateTime.utc(2026, 7, 28),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut-1'),
          name: 'cut-1',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          // Labelled, so the cut's bands and the conte blocks' differ.
          metadata: const CutMetadata(
            mark: LayerMark(process: LayerProcess.art),
          ),
          layers: [
            Layer(
              id: const LayerId('cut-1-sb'),
              name: 'SB',
              kind: LayerKind.storyboard,
              frames: [
                Frame(id: const FrameId('f0'), duration: 1, strokes: const []),
                Frame(id: const FrameId('f5'), duration: 1, strokes: const []),
              ],
              timeline: const {
                0: TimelineExposure.drawing(FrameId('f0'), length: 5),
                5: TimelineExposure.drawing(FrameId('f5'), length: 5),
              },
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  group('the grip\'s ink is the ground law\'s pick', () {
    test('a dark ground takes the LIGHT ink, a light one the dark ink', () {
      final onPaper = blockEdgeGripColor(BlockEdgeGripInk.rest);
      final onPlate = blockEdgeGripColor(
        BlockEdgeGripInk.rest,
        ground: AppColors.washUp,
      );

      expect(onPaper, isNot(onPlate));
      expect(onPaper.withValues(alpha: 1), timelineTextOnLightGroundColor);
      expect(onPlate.withValues(alpha: 1), timelineTextOnDarkGroundColor);
      // The light bar is genuinely lighter, which is the whole point: the
      // near-black one vanished against a dark cut block.
      expect(
        onPlate.computeLuminance(),
        greaterThan(onPaper.computeLuminance()),
      );
    });

    test('the PURPLE paper takes the dark bar — the same pick its numbers '
        'make, one law for text and edges', () {
      final onPurple = blockEdgeGripColor(
        BlockEdgeGripInk.rest,
        ground: layerMarkColor(const LayerMark(process: LayerProcess.finish)),
      );
      expect(onPurple.withValues(alpha: 1), timelineTextOnLightGroundColor);
      expect(
        onPurple,
        blockEdgeGripColor(BlockEdgeGripInk.rest),
        reason:
            'purple sits on the same side of the crossover as the plain '
            'paper, so the bar does not change weight between them',
      );
    });

    test('the paper default keeps the dark mark\'s weights', () {
      expect(
        blockEdgeGripColor(BlockEdgeGripInk.rest),
        timelineTextOnLightGroundColor.withValues(alpha: 0.38),
      );
      expect(
        blockEdgeGripColor(BlockEdgeGripInk.hovered),
        timelineTextOnLightGroundColor.withValues(alpha: 0.95),
      );
    });

    test('a LIVE drag keeps the accent on both grounds — a drag in flight '
        'must not change colour with its row', () {
      expect(
        blockEdgeGripColor(BlockEdgeGripInk.dragging),
        blockEdgeGripColor(
          BlockEdgeGripInk.dragging,
          ground: AppColors.washUp,
        ),
      );
    });
  });

  Future<void> openStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: HomePage(initialProject: _project()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('🗣️the cut row\'s edges stand on the PLATE — the conte '
      'sheet\'s black, so its ink is the light one — while the timeline row '
      'hands its grips its layer\'s paper', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: HomePage(initialProject: _project()),
      ),
    );
    await tester.pumpAndSettle();

    // The cut-internal timeline's storyboard row: its own (unmarked) paper.
    expect(
      timelineRowChromePainter(tester, 'cut-1-sb')!.gripGround,
      layerMarkColor(LayerMark.none),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    final ground = timelineRowChromePainter(
      tester,
      _trackId.value,
      prefix: 'storyboard',
    )!.gripGround;
    expect(ground, conteSheetInk);
    expect(
      blockEdgeGripColor(
        BlockEdgeGripInk.rest,
        ground: ground,
      ).withValues(alpha: 1),
      timelineTextOnDarkGroundColor,
    );
  });

  testWidgets('🗣️and a triangle that crosses a label band reads THAT band '
      'there — two grounds, two inks (유저 2026-09-26: 「2여도 흰종이부분에 '
      '엣지는 1처럼 제대로 보이게 가능하지?」)', (tester) async {
    await openStoryboard(tester);
    final painter = timelineRowChromePainter(
      tester,
      _trackId.value,
      prefix: 'storyboard',
    )!;
    final end = painter.targets.whereType<TimelineRowGripTarget>().firstWhere(
      (target) => target.edge == TimelineBlockEdge.end,
    );

    // The end triangle hangs from its conte block's top: the conte blocks'
    // top band, in the storyboard layer's label — the paper, unlabelled.
    final band = painter.gripGrounds!()
        .under(end.rect)
        .singleWhere((ground) => ground.rect.top == end.rect.top);
    expect(band.color, layerMarkColor(LayerMark.none));
    expect(band.rect.height, StoryboardCutBlocksPainter.bandHeight);

    // Painted: the band's part in the dark ink, the rest in the plate's
    // light one.
    final spy = _InkSpy();
    painter.paint(
      spy,
      tester.getSize(
        timelineRowChromeFinder(_trackId.value, prefix: 'storyboard'),
      ),
    );
    // As ARGB: a Paint keeps its colour in 32 bits.
    int ink(Color ground) =>
        blockEdgeGripColor(BlockEdgeGripInk.rest, ground: ground).toARGB32();
    bool drawn(int ink, ClipOp op) => spy.draws.any(
      (draw) => draw.ink == ink && draw.clips.contains((band.rect, op)),
    );
    expect(
      drawn(ink(band.color), ClipOp.intersect),
      isTrue,
      reason: 'the band\'s ink, inside the band',
    );
    expect(
      drawn(ink(conteSheetInk), ClipOp.difference),
      isTrue,
      reason: 'the plate\'s ink everywhere but the band — ↩️one ink on both '
          'would lay a light triangle under the band\'s dark one',
    );
  });

  testWidgets('with thumbnails OFF there is no picture under an edge — the '
      'bands over the plate are all it stands on', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = EditorSessionManager(initialProject: _project());
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: manager,
            builder: (context, _) => StoryboardTabHost(
              session: manager,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = timelineRowChromePainter(
      tester,
      _trackId.value,
      prefix: 'storyboard',
    )!;
    expect(painter.gripGround, conteSheetInk);
    final grounds = painter.gripGrounds!();
    for (final grip in painter.targets.whereType<TimelineRowGripTarget>()) {
      expect(
        grounds.under(grip.rect).map((ground) => ground.color).toSet(),
        {layerMarkColor(LayerMark.none)},
        reason: '${grip.id}: its conte block\'s band, and the plate',
      );
    }
  });
}

/// The ink of every mark laid down (ARGB), with the clips it was laid in.
class _InkSpy implements Canvas {
  final draws = <({int ink, List<(Rect, ClipOp)> clips})>[];
  var _clips = <(Rect, ClipOp)>[];
  final _saved = <List<(Rect, ClipOp)>>[];

  @override
  void save() => _saved.add(_clips);

  @override
  void restore() => _clips = _saved.removeLast();

  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) => _clips = [..._clips, (rect, clipOp)];

  @override
  void drawPath(Path path, Paint paint) =>
      draws.add((ink: paint.color.toARGB32(), clips: _clips));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
