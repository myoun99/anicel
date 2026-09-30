/// The store cases raster tiles for real and wait for the landing off-frame
/// — the same bound as `a_content_bump_rerasters_only_the_tiles_it_reached`
/// and for the same reason (under load the 30s default dies bare).
@Timeout(Duration(minutes: 3))
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/exposure_instruction.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_cells_agreement.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/native_engine_path.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🚨F-244 (유저 2026-09-30: 「타임라인 블록 관련 조작이 너무 느림 … 무거운
/// 컷일수록 심해짐」): A TILE KEEPS WHAT AN EDIT LEFT ALONE.
///
/// A comma drag makes a new layer at every step, and the tiles, keyed on the
/// instance, baked every visible span of the row again at every step — 40 a
/// step on FU 301 with its attach mirror, the last landing 25–57ms after the
/// step. What an edit can change starts where the two instances' timelines
/// first part ([firstCellThatMayDiffer]); the spans before it keep their
/// tiles.
///
/// The rule is PROVEN here against the painter itself: for random rows and
/// random edits, every span the rule keeps bakes the same paper and the
/// same ink from the old layer as from the new one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The session's reading of a drawing row's cells
  // (`ExposureVerbs.exposureStateForLayer`), line for line.
  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (frameIndex >= 0 && (layer.timeline[frameIndex]?.isDrawing ?? false)) {
      return TimelineCellExposureState.drawingStart;
    }
    final held =
        frameIndex >= 0 &&
        coveringDrawingBlockAt(layer.timeline, frameIndex) != null;
    if (held && hasBreakdownDotAt(layer.timeline, frameIndex)) {
      return TimelineCellExposureState.markHeld;
    }
    return held
        ? TimelineCellExposureState.held
        : TimelineCellExposureState.uncovered;
  }

  // And its names (`FrameVerbs.frameNameForLayer`, a row that mirrors
  // nothing): the cel the block at [frameIndex] exposes.
  String? nameFor(Layer layer, int frameIndex) {
    final cel = exposedFrameIdAt(layer.timeline, frameIndex);
    return cel == null ? null : layer.frameById(cel)?.name;
  }

  // The cels are named short and long, and one is unnamed (a mark).
  const names = ['1', '12', 'A', 'B3', 'Background', '', '240'];
  List<Frame> cels() => [
    for (var i = 0; i < names.length; i += 1)
      Frame(
        id: FrameId('c$i'),
        duration: 1,
        strokes: const [],
        name: names[i],
      ),
  ];

  group('where two instances of a row may first show different cells', () {
    Layer row(Map<int, TimelineExposure> timeline) => Layer(
      id: const LayerId('r'),
      name: 'R',
      frames: cels(),
      timeline: timeline,
    );
    TimelineExposure block(int cel, int length) =>
        TimelineExposure.drawing(FrameId('c$cel'), length: length);

    test('nowhere, for the same cells in a new instance', () {
      final a = row({0: block(0, 4), 6: block(1, 3)});
      expect(firstCellThatMayDiffer(a, a), isNull);
      expect(firstCellThatMayDiffer(a, a.copyWith(timeline: {...a.timeline})),
          isNull);
    });

    test('everywhere, when anything beside the timeline moved', () {
      final a = row({0: block(0, 4)});
      expect(firstCellThatMayDiffer(a, a.copyWith(name: 'S')), 0);
      expect(
        firstCellThatMayDiffer(
          a,
          a.copyWith(frames: [...a.frames.take(1), ...cels().skip(1)]),
        ),
        isNull,
        reason: 'premise: equal cels are the same cels',
      );
    });

    test('from the first entry the two timelines part at', () {
      final a = row({0: block(0, 3), 4: block(1, 3), 7: block(2, 2)});
      // The block at 4 grows by two, and the one after it rides along.
      final b = row({0: block(0, 3), 4: block(1, 5), 9: block(2, 2)});
      expect(firstCellThatMayDiffer(a, b), 4);
      // A block running right up to the edit ends there in both.
      final c = row({0: block(0, 4), 4: block(1, 3)});
      final d = row({0: block(0, 4), 4: block(1, 4)});
      expect(firstCellThatMayDiffer(c, d), 4);
      // An entry only one of them has.
      expect(firstCellThatMayDiffer(c, row({0: block(0, 4)})), 4);
      expect(firstCellThatMayDiffer(row({0: block(0, 4)}), c), 4);
      expect(
        firstCellThatMayDiffer(c, row({0: block(0, 4), 5: block(1, 3)})),
        4,
      );
    });

    test('a direction row\'s spans are its blocks — a row whose blocks moved '
        'is the same row beside its timeline', () {
      final direction = LayerKind.values.firstWhere(
        (kind) => kind.spansRideBlocks,
      );
      TimelineExposure pan(int length) => TimelineExposure.drawing(
        const FrameId('c1'),
        length: length,
        instruction: const ExposureInstruction(instructionId: 'pan'),
      );
      final a = row({0: block(0, 3), 4: pan(3)}).copyWith(kind: direction);
      // The pan's block grows — and with it the span it IS.
      final b = a.copyWith(timeline: {0: block(0, 3), 4: pan(5)});
      expect(
        a.instructions[4]?.length,
        isNot(b.instructions[4]?.length),
        reason: 'premise: the spans read off the blocks differ',
      );
      expect(a.sameBesideTimeline(b), isTrue);
      expect(a == b, isFalse);
      expect(firstCellThatMayDiffer(a, b), 4);
    });

    test('a mirror follows its base\'s cels, which its row prints', () {
      final base = row({0: block(0, 3), 4: block(1, 4)});
      // The mirror's own cels, each linked to the base's it mirrors.
      final attached = Layer(
        id: const LayerId('m'),
        name: 'M',
        frames: [
          for (final cel in const ['m0', 'm1'])
            Frame(id: FrameId(cel), duration: 1, strokes: const []),
        ],
        attachedToLayerId: base.id,
        attachedMode: AttachedMode.synced,
        baseFrameLinks: {
          const FrameId('c0'): const FrameId('m0'),
          const FrameId('c1'): const FrameId('m1'),
        },
      );
      final mirror = attachedDisplayLayer(attached: attached, base: base);
      expect(attachedDisplayBaseOf(mirror), same(base));
      final renamed = base.copyWith(
        frames: [
          for (final cel in base.frames)
            if (cel.id == const FrameId('c0'))
              cel.copyWith(name: '7')
            else
              cel,
        ],
      );
      final mirrorOfRenamed = attachedDisplayLayer(
        attached: attached,
        base: renamed,
      );
      expect(
        firstCellThatMayDiffer(mirror, mirrorOfRenamed),
        0,
        reason: 'the same mirrored cells, printed with another name',
      );
      final moved = base.copyWith(
        timeline: {0: block(0, 3), 4: block(1, 6)},
      );
      expect(
        firstCellThatMayDiffer(
          mirror,
          attachedDisplayLayer(attached: attached, base: moved),
        ),
        4,
        reason: 'a base that only moved a block keeps the cells before it',
      );
    });
  });

  group('the rule, against the painter', () {
    // A random row: blocks of every length, gaps, dots, hold and repeat
    // ghosts, cels named short, long and not at all.
    Layer randomRow(math.Random random) {
      final timeline = <int, TimelineExposure>{};
      var at = random.nextInt(3);
      while (at < 58) {
        final length = 1 + random.nextInt(8);
        final ghost = random.nextInt(6) == 0
            ? TimelineRunEdgeGhost(
                side: TimelineRunEdgeSide.end,
                mode: random.nextBool()
                    ? TimelineRunEdgeMode.hold
                    : TimelineRunEdgeMode.repeat,
              )
            : null;
        timeline[at] = TimelineExposure.drawing(
          FrameId('c${random.nextInt(names.length)}'),
          length: length,
          ghostOf: ghost,
          breakdownOffsets: [
            if (length > 2 && ghost == null && random.nextBool())
              1 + random.nextInt(length - 1),
          ],
        );
        at += length + (random.nextInt(3) == 0 ? 1 + random.nextInt(3) : 0);
      }
      return Layer(
        id: const LayerId('row'),
        name: 'Row',
        frames: cels(),
        timeline: timeline,
      );
    }

    // A random edit, as the verbs make them: a new timeline on a copy that
    // keeps every other field.
    Layer randomEdit(Layer layer, math.Random random) {
      final entries = layer.timeline.entries.toList();
      final pick = entries[random.nextInt(entries.length)];
      final edited = <int, TimelineExposure>{};
      switch (random.nextInt(5)) {
        case 0: // A comma: the block grows or shrinks, the rest ride along.
          final length = pick.value.length!;
          final delta = math.max(1 - length, random.nextInt(7) - 3);
          for (final entry in entries) {
            if (entry.key < pick.key) {
              edited[entry.key] = entry.value;
            } else if (entry.key == pick.key) {
              edited[entry.key] = TimelineExposure.drawing(
                entry.value.frameId!,
                length: length + delta,
                ghostOf: entry.value.ghostOf,
              );
            } else {
              edited[entry.key + delta] = entry.value;
            }
          }
        case 1: // A block goes.
          edited
            ..addAll(layer.timeline)
            ..remove(pick.key);
        case 2: // A block shows another cel.
          edited.addAll(layer.timeline);
          edited[pick.key] = TimelineExposure.drawing(
            FrameId('c${random.nextInt(names.length)}'),
            length: pick.value.length!,
          );
        case 3: // A dot comes or goes.
          edited.addAll(layer.timeline);
          final length = pick.value.length!;
          edited[pick.key] = TimelineExposure.drawing(
            pick.value.frameId!,
            length: length,
            breakdownOffsets: pick.value.breakdownOffsets.isEmpty && length > 1
                ? [length - 1]
                : const [],
          );
        default: // A ghost comes or goes.
          edited.addAll(layer.timeline);
          edited[pick.key] = TimelineExposure.drawing(
            pick.value.frameId!,
            length: pick.value.length!,
            ghostOf: pick.value.ghost
                ? null
                : const TimelineRunEdgeGhost(
                    side: TimelineRunEdgeSide.end,
                    mode: TimelineRunEdgeMode.hold,
                  ),
          );
      }
      return layer.copyWith(timeline: edited);
    }

    for (final cellExtent in [9.0, 24.0]) {
      test('every span it keeps bakes alike from either layer '
          '(${cellExtent}px cells)', () async {
        final store = TimelineGridTileStore.instance;
        final celContent = TimelineCelContentSource(
          // Two cels have no picture yet: their blocks are grey paper.
          hasContent: (layer, frameIndex) {
            final cel = exposedFrameIdAt(layer.timeline, frameIndex);
            return cel != const FrameId('c1') && cel != const FrameId('c4');
          },
          revision: ValueNotifier<int>(0),
        );
        TimelineRowCellsPainter painterFor(Layer layer) =>
            TimelineRowCellsPainter(
              layer: layer,
              geometry: testFrameGeometry(
                frameCellExtent: cellExtent,
                frameEndIndexExclusive: 64,
              ),
              crossAxisExtent: 28,
              exposureStateForLayer: stateFor,
              frameNameForLayer: nameFor,
              celContent: celContent,
              colorScheme: const ColorScheme.dark(),
              baseTextStyle: const TextStyle(fontSize: 11),
              paperGround: const Color(0xFF202124),
              blockFrameLines: true,
              framesPerSecond: 24,
            );

        final random = math.Random(244);
        var kept = 0;
        var parted = 0;
        for (var round = 0; round < 200; round += 1) {
          final before = randomRow(random);
          final after = randomEdit(before, random);
          final differs = firstCellThatMayDiffer(before, after);
          final old = painterFor(before);
          final fresh = painterFor(after);
          for (final span in [4, 7]) {
            for (var start = 0; start < 64; start += span) {
              final end = math.min(start + span, 64);
              if (differs != null && differs <= end) {
                parted += 1;
                continue;
              }
              kept += 1;
              final at = 'round $round, span [$start, $end), '
                  'the rule said ${differs ?? 'nowhere'}';
              expect(
                fresh.substrateIn(start, end).paper,
                old.substrateIn(start, end).paper,
                reason: 'paper — $at',
              );
              expect(
                fresh.substrateIn(start, end).lines,
                old.substrateIn(start, end).lines,
                reason: 'lines — $at',
              );
              expect(
                await store.debugForegroundOps(
                  painter: fresh,
                  spanStartIndex: start,
                  spanEndIndexExclusive: end,
                  devicePixelRatio: 1.5,
                ),
                await store.debugForegroundOps(
                  painter: old,
                  spanStartIndex: start,
                  spanEndIndexExclusive: end,
                  devicePixelRatio: 1.5,
                ),
                reason: 'ink — $at',
              );
            }
          }
        }
        // Not a vacuous pass: the rule kept real spans and parted others.
        expect(kept, greaterThan(200));
        expect(parted, greaterThan(200));
      });
    }
  });

  group('the store', () {
    final dllPath = nativeEngineLibraryPathOrNull();

    setUp(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      TimelineGridTileStore.instance.clear();
    });

    tearDown(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
      QaNativeEngine.debugForceDartFallback = false;
      TimelineGridTileStore.instance.clear();
    });

    test('a comma step bakes again only the spans that reach the edit — the '
        'ones before it keep their pixels', () async {
      if (dllPath == null) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final store = TimelineGridTileStore.instance;
      var landings = 0;
      store.revision.addListener(() => landings += 1);
      Future<void> waitIdle() async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        await Future<void>.delayed(Duration.zero);
        while (store.debugBusy) {
          if (DateTime.now().isAfter(deadline)) {
            fail('timed out waiting for the drain ($landings landings)');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      TimelineExposure block(int cel, int length) =>
          TimelineExposure.drawing(FrameId('c$cel'), length: length);
      // Three blocks, a gap, and at 16 — a span's edge — the block the
      // comma drags.
      final before = Layer(
        id: const LayerId('row'),
        name: 'Row',
        frames: cels(),
        timeline: {
          0: block(0, 5),
          6: block(1, 5),
          12: block(2, 3),
          16: block(3, 4),
          20: block(4, 6),
        },
      );
      // The comma at 16 grows by two; the block after it rides along.
      final after = before.copyWith(
        timeline: {
          0: block(0, 5),
          6: block(1, 5),
          12: block(2, 3),
          16: block(3, 6),
          22: block(4, 6),
        },
      );
      expect(
        firstCellThatMayDiffer(before, after),
        16,
        reason: 'premise: the comma is where the two may part',
      );
      TimelineRowCellsPainter painterFor(Layer layer) =>
          TimelineRowCellsPainter(
            layer: layer,
            geometry: testFrameGeometry(
              frameCellExtent: 24,
              frameEndIndexExclusive: 40,
            ),
            crossAxisExtent: 28,
            exposureStateForLayer: stateFor,
            frameNameForLayer: nameFor,
            colorScheme: const ColorScheme.dark(),
            baseTextStyle: const TextStyle(fontSize: 11),
            tileStore: store,
            substrateGeneration: 'p:cut',
          );
      // 24px cells: a span is four of them.
      const spans = [
        (0, 4), (4, 8), (8, 12), (12, 16), (16, 20),
        (20, 24), (24, 28), (28, 32), (32, 36), (36, 40),
      ];
      Map<(int, int), Object?> paint(TimelineRowCellsPainter painter) => {
        for (final span in spans)
          span: store.tileFor(
            painter: painter,
            spanStartIndex: span.$1,
            spanEndIndexExclusive: span.$2,
            devicePixelRatio: 1.0,
          ),
      };

      expect(paint(painterFor(before)).values, everyElement(isNull));
      await waitIdle();
      final warm = paint(painterFor(before));
      expect(warm.values, everyElement(isNotNull));
      final baked = landings;

      final stepped = paint(painterFor(after));
      for (final span in spans) {
        if (span.$2 < 16) {
          expect(
            identical(stepped[span], warm[span]),
            isTrue,
            reason: 'span $span ends before the comma can show: kept',
          );
        }
      }
      await waitIdle();
      expect(
        landings - baked,
        spans.where((span) => span.$2 >= 16).length,
        reason: 'exactly the spans that reach the comma bake again — '
            '(12, 16) among them: its last paper asks cell 16',
      );
      final settled = paint(painterFor(after));
      for (final span in spans.where((span) => span.$2 < 16)) {
        expect(identical(settled[span], warm[span]), isTrue);
      }

      // A second edit that parts EARLIER than the first: what the first
      // kept is asked again, of the newest layer — not answered by the pair
      // the first one asked about.
      final again = after.copyWith(
        timeline: {
          0: block(0, 5),
          6: block(2, 5),
          12: block(2, 3),
          16: block(3, 6),
          22: block(4, 6),
        },
      );
      expect(firstCellThatMayDiffer(before, again), 6, reason: 'premise');
      final landed = landings;
      final second = paint(painterFor(again));
      expect(identical(second[(0, 4)], warm[(0, 4)]), isTrue);
      await waitIdle();
      expect(
        landings - landed,
        spans.where((span) => span.$2 >= 6).length,
        reason: 'the spans the first edit kept and this one reaches',
      );
    });
  });
}
