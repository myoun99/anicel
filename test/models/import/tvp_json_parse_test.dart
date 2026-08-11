import 'dart:io';

import 'package:anicel/src/models/import/tvp_json_parse.dart';
import 'package:flutter_test/flutter_test.dart';

/// The TVPaint JSON reader, tested against REAL exports — the three
/// fixtures are unmodified files TVPaint wrote, kept whole (camera
/// `positions` arrays included) because a trimmed export stops being
/// evidence.
///
/// Every expectation below was cross-checked against the CSV export of
/// the same clip before it was written down: the CSV writes one file per
/// instance head INSIDE `[start, end]` and one file per frame outside it,
/// so its file counts are an independent oracle for the block layout this
/// parser derives.
void main() {
  TvpJsonParseResult load(String name) =>
      parseTvpJson(File('test/fixtures/tvpaint/$name.json').readAsStringSync());

  TvpLayer layerNamed(TvpJsonParseResult result, String name) =>
      result.layers.firstWhere((layer) => layer.name == name);

  group('held_instances.json — one instance per layer, three commas each', () {
    test('a lone instance is exposed across the whole layer span', () {
      final result = load('held_instances');
      // Three layers, each `start: 0, end: 2` with a single link entry.
      // TVPaint's timeline showed the block spanning frames 1-3 with a
      // "3" exposure label; the JSON never says 3 anywhere, so this is
      // the derivation under test.
      for (final layer in result.layers) {
        expect(layer.blocks, hasLength(1), reason: layer.name);
        expect(layer.blocks.single.start, 0, reason: layer.name);
        expect(layer.blocks.single.length, 3, reason: layer.name);
        expect(layer.blocks.single.isReexposure, isFalse, reason: layer.name);
      }
    });

    test('layers come out bottom-first — TVPaint numbers the TOP layer 1', () {
      final result = load('held_instances');
      expect(
        result.layers.map((layer) => layer.name),
        ['A', 'B', 'C'],
        reason: 'positions are C=1, B=2, A=3; Cut.layers.first is the bottom',
      );
    });

    test('the edge markers map to behaviours: B holds, A and C stop', () {
      final result = load('held_instances');
      expect(layerNamed(result, 'B').postBehavior, TvpEdgeBehavior.hold);
      expect(layerNamed(result, 'A').postBehavior, TvpEdgeBehavior.none);
      expect(layerNamed(result, 'C').postBehavior, TvpEdgeBehavior.none);
      for (final layer in result.layers) {
        expect(layer.preBehavior, TvpEdgeBehavior.none, reason: layer.name);
      }
    });
  });

  group('edge_behaviors.json — spans, holds and a repeat edge', () {
    test('clip and camera header', () {
      final result = load('edge_behaviors');
      expect(result.width, 2150);
      expect(result.height, 1518);
      expect(result.frameCount, 24);
      expect(result.frameRate, 24.0);
      expect(result.markOut, 23);
      expect(result.markIn, isNull, reason: 'markin status is false');
      expect(result.camera.width, 1920, reason: 'the shooting frame is not '
          'the clip size');
      expect(result.camera.height, 1080);
      expect(result.camera.keyframes, hasLength(2));
      expect(result.camera.positions, hasLength(24));
      expect(result.camera.isAnimated, isTrue);
    });

    test('a layer whose span covers the clip exposes ONE cel over all of '
        'it — the CSV export of this clip wrote TAP exactly once', () {
      final tap = layerNamed(load('edge_behaviors'), 'TAP');
      expect(tap.start, 0);
      expect(tap.end, 23);
      expect(tap.instances, hasLength(1));
      expect(tap.blocks, hasLength(1));
      expect(tap.blocks.single.length, 24);
    });

    test('a one-frame span starting late keeps its offset', () {
      final e = layerNamed(load('edge_behaviors'), 'E');
      expect(e.blocks, hasLength(1));
      expect(e.blocks.single.start, 16);
      expect(e.blocks.single.length, 1);
      expect(e.postBehavior, TvpEdgeBehavior.hold);
    });

    test('three instances three frames apart become three 3-comma cels', () {
      final result = load('edge_behaviors');
      for (final name in ['D', 'C', 'A']) {
        final layer = layerNamed(result, name);
        expect(layer.instances, hasLength(3), reason: name);
        expect(layer.blocks, hasLength(3), reason: name);
        expect(
          layer.blocks.map((block) => block.start),
          [0, 3, 6],
          reason: name,
        );
        expect(
          layer.blocks.map((block) => block.length),
          [3, 3, 3],
          reason: name,
        );
        expect(
          layer.blocks.map((block) => block.name),
          ['1', '2', '3'],
          reason: '$name carries authored cel numbers',
        );
      }
    });

    test('the three post-behaviours of this clip are all distinct', () {
      final result = load('edge_behaviors');
      expect(layerNamed(result, 'D').postBehavior, TvpEdgeBehavior.repeat);
      expect(layerNamed(result, 'C').postBehavior, TvpEdgeBehavior.none);
      expect(layerNamed(result, 'A').postBehavior, TvpEdgeBehavior.hold);
    });

    test('an unnamed instance still arrives named — TVPaint substitutes '
        'the ordinal, and the JSON cannot say it was blank', () {
      final result = load('edge_behaviors');
      // TAP and B were left unnamed in TVPaint; E was named "1" for real.
      // All three report "1". Only the CSV export distinguishes them (it
      // falls back to the LAYER name in the file name), and the import
      // deliberately does not require a second export for it.
      expect(layerNamed(result, 'TAP').instances.single.name, '1');
      expect(layerNamed(result, 'B').instances.single.name, '1');
      expect(layerNamed(result, 'E').instances.single.name, '1');
    });
  });

  group('production_clip.json — a real 159-frame clip', () {
    test('seventeen layers, bottom-first', () {
      final result = load('production_clip');
      expect(result.layers, hasLength(17));
      expect(result.layers.first.name, 'BG', reason: 'position 17 = bottom');
      expect(result.layers.last.name, 'TAP', reason: 'position 1 = top');
      expect(result.frameCount, 159);
    });

    test('a repeat span replays the pattern that precedes it — BG cycles '
        'three 3-comma drawings twice more', () {
      final bg = layerNamed(load('production_clip'), 'BG');
      expect(bg.start, 0);
      expect(bg.end, 26);
      expect(bg.instances, hasLength(3));
      expect(bg.repeats, hasLength(1));
      expect(bg.repeats.single.index, 9);
      expect(bg.repeats.single.value, 9);

      expect(bg.blocks, hasLength(9), reason: '3 authored + 6 replayed');
      expect(
        bg.blocks.map((block) => block.length),
        List<int>.filled(9, 3),
      );
      expect(
        bg.blocks.map((block) => block.sourceIndex),
        [0, 3, 6, 0, 3, 6, 0, 3, 6],
        reason: 'the 9-frame pattern is three drawings, cycled to end 26',
      );
      expect(
        bg.blocks.map((block) => block.isReexposure),
        [false, false, false, true, true, true, true, true, true],
        reason: 'six of the nine blocks re-show a drawing, so the import '
            'mints three cels, not nine',
      );
    });

    test('a repeat span that does not start at the layer start still '
        'anchors on the frames before it — Cst', () {
      final cst = layerNamed(load('production_clip'), 'Cst');
      expect(cst.start, 7);
      expect(cst.end, 33);
      expect(cst.repeats.single.index, 16);
      expect(cst.repeats.single.value, 9);
      expect(cst.blocks, hasLength(9));
      expect(cst.blocks.first.start, 7);
      expect(cst.blocks.last.endExclusive, 34);
      expect(
        cst.blocks.map((block) => block.sourceIndex),
        [7, 10, 13, 7, 10, 13, 7, 10, 13],
      );
    });

    test('a one-frame repeat inside a run merges into that run instead of '
        'splitting it — A', () {
      final a = layerNamed(load('production_clip'), 'A');
      expect(a.instances, hasLength(7));
      expect(a.repeats.single.index, 16);
      expect(a.repeats.single.value, 1);
      // Instance "1.5" starts at 5; the repeat at 16 replays frame 15,
      // which is still "1.5", so the run is one block 5..29 rather than
      // two abutting ones.
      expect(a.blocks, hasLength(7));
      expect(
        a.blocks.map((block) => block.start),
        [0, 1, 5, 30, 151, 152, 153],
      );
      expect(a.blocks.map((block) => block.length), [1, 4, 25, 121, 1, 1, 1]);
      expect(
        a.blocks.map((block) => block.name),
        ['0', '1', '1.5', '15a', '5', '0', '23.5'],
        reason: 'field cel numbers, in-betweens and all, survive verbatim',
      );
    });

    test('instances with no pixels still carry their label — the SE rows '
        'hold their dialogue in the instance name', () {
      final result = load('production_clip');
      final se = result.layers.firstWhere(
        (layer) => layer.name == 'SE' && layer.start == 6,
      );
      expect(
        se.blocks.map((block) => block.name),
        ['arisu,おはよ', '2', 'テスト,あああ'],
      );
      expect(se.blocks.map((block) => block.length), [6, 4, 6]);
      final cam = result.layers.firstWhere(
        (layer) => layer.name == 'CAM' && layer.start == 6,
      );
      expect(cam.blocks.single.name, 'PAN');
    });

    test('gaps between instances are held, not blank — b_W', () {
      final layer = layerNamed(load('production_clip'), 'b_W');
      expect(layer.instances, hasLength(5));
      expect(layer.blocks.map((block) => block.start), [0, 13, 16, 19, 156]);
      expect(layer.blocks.map((block) => block.length), [13, 3, 3, 137, 3]);
      expect(
        layer.blocks.map((block) => block.name),
        ['1', '-', '2', '3', '4'],
      );
    });

    test('every layer covers its whole span with no holes', () {
      for (final layer in load('production_clip').layers) {
        if (layer.blocks.isEmpty) {
          continue;
        }
        expect(layer.blocks.first.start, layer.start, reason: layer.name);
        expect(layer.blocks.last.endExclusive, layer.end + 1,
            reason: layer.name);
        for (var i = 1; i < layer.blocks.length; i += 1) {
          expect(
            layer.blocks[i].start,
            layer.blocks[i - 1].endExclusive,
            reason: '${layer.name} block $i',
          );
        }
      }
    });

    test('opacity, visibility and the colour group come through', () {
      final result = load('production_clip');
      for (final layer in result.layers) {
        expect(layer.opacity, 1.0, reason: layer.name);
        expect(layer.visible, isTrue, reason: layer.name);
        expect(layer.blendingMode, 'Color', reason: layer.name);
      }
      expect(layerNamed(result, 'TAP').groupColor!.red, 255);
      expect(layerNamed(result, 'TAP').groupColor!.green, 102);
      expect(layerNamed(result, 'TAP').groupColor!.blue, 0);
    });

    test('nothing about a real export is worth warning about', () {
      expect(load('production_clip').warnings, isEmpty);
    });
  });

  group('resolveExposureBlocks — the odd cases the field will produce', () {
    List<String> warningsFor(
      List<TvpExposureBlock> Function(List<String> warnings) run,
    ) {
      final warnings = <String>[];
      run(warnings);
      return warnings;
    }

    TvpInstance instance(int index, {List<int>? images}) => TvpInstance(
      index: index,
      name: '$index',
      file: 'x/$index.png',
      images: images ?? [index],
    );

    test('a repeat whose pattern reaches before the layer is ignored, '
        'loudly', () {
      final warnings = warningsFor(
        (warnings) => resolveExposureBlocks(
          layerName: 'L',
          start: 0,
          end: 9,
          frameCount: 24,
          instances: [instance(0)],
          repeats: const [TvpRepeatSpan(index: 3, value: 9, mode: 1)],
          warnings: warnings,
        ),
      );
      expect(warnings.single, contains('repeat'));
    });

    test('an instance outside the layer span is skipped, loudly', () {
      final warnings = warningsFor(
        (warnings) => resolveExposureBlocks(
          layerName: 'L',
          start: 0,
          end: 4,
          frameCount: 24,
          instances: [instance(0), instance(9)],
          repeats: const [],
          warnings: warnings,
        ),
      );
      expect(warnings.single, contains('outside the layer span'));
    });

    test('a span running past the clip end is clipped, loudly', () {
      final warnings = <String>[];
      final blocks = resolveExposureBlocks(
        layerName: 'L',
        start: 0,
        end: 99,
        frameCount: 10,
        instances: [instance(0)],
        repeats: const [],
        warnings: warnings,
      );
      expect(blocks.single.length, 10);
      expect(warnings.single, contains('clipped'));
    });

    test('a linked image listing several positions starts a block at each '
        '— the 「화상の重複」-off shape', () {
      final blocks = resolveExposureBlocks(
        layerName: 'L',
        start: 0,
        end: 8,
        frameCount: 24,
        instances: [
          instance(0, images: [0, 6]),
          instance(3),
        ],
        repeats: const [],
        warnings: <String>[],
      );
      expect(blocks.map((block) => block.start), [0, 3, 6]);
      expect(blocks.map((block) => block.length), [3, 3, 3]);
      expect(
        blocks.map((block) => block.file),
        ['x/0.png', 'x/3.png', 'x/0.png'],
        reason: 'the third block reuses the first image',
      );
      expect(
        blocks.map((block) => block.sourceIndex),
        [0, 3, 0],
        reason: 'the drawing keys on its INSTANCE, so the linked position '
            'shares the first cel instead of minting a copy',
      );
      expect(
        blocks.map((block) => block.isReexposure),
        [false, false, true],
      );
    });

    test('a layer with no instances at all resolves to nothing', () {
      expect(
        resolveExposureBlocks(
          layerName: 'L',
          start: 0,
          end: 8,
          frameCount: 24,
          instances: const [],
          repeats: const [],
          warnings: <String>[],
        ),
        isEmpty,
      );
    });
  });

  group('refusals', () {
    test('a JSON that is not a TVPaint export is refused by name', () {
      expect(
        () => parseTvpJson('{"hello": "world"}'),
        throwsA(
          isA<TvpJsonParseException>().having(
            (error) => error.message,
            'message',
            contains('not a TVPaint JSON export'),
          ),
        ),
      );
      expect(() => parseTvpJson('not json'),
          throwsA(isA<TvpJsonParseException>()));
    });
  });
}
