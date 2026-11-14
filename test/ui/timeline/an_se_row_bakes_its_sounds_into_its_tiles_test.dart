/// These cases raster tiles for real and wait for landings off-frame — the
/// bound the other store files state, for their reason (under load the
/// 30s default dies bare).
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import '../../helpers/exposure_of.dart';
import 'tile_store_idle.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🗣️the-waveform-is-drawn-on-the-cpu-beside-its-kernel-Q2 (유저 2026-11-14
/// 「(가) SE 행의 셀 타일에 굽는다」): AN SE ROW'S SOUNDS ARE IN ITS CELLS'
/// OWN PICTURE. A screen copies what it lays, so a wave laid as a picture
/// of its own would clear the paper under it: the tile bakes the wave over
/// its paper, the canvas paints it there where no tile holds the span, and
/// a sound that moves with no layer of the row moving — its peaks arriving
/// — bakes the tile again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(openAppGpuEngine);

  final store = TimelineGridTileStore.instance;

  /// Four frames at 128px, one span, a 28px row: a sound heard over its
  /// first two frames covers columns [0, 256) of the span's 512.
  const frames = 4;
  const cell = 128.0;
  const across = 28;
  const heard = 2;

  /// An SE row with one block over its four frames.
  Layer seLayer(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.se,
    frames: [Frame(id: FrameId('$id-f'), duration: 4, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 4)},
  );

  // Two seconds at full scale: louder than the band can reach, so every
  // column of the strip stands as high as its lane lets it.
  final peaks = AudioPeaks(
    bucketsPerSecond: 80,
    peaks: Float32List.fromList(List.filled(160, 1.0)),
  );

  /// The row's sounds: [heard] frames of [peaks] from frame 0 — none
  /// while they are still extracting.
  TimelineRowSounds soundsOf({required bool landed}) => (
    sounds: [
      if (landed)
        (
          startFrame: 0,
          audibleFrames: heard,
          keyName: 'se-0-b0',
          peaks: peaks,
          leadingFrames: 0,
          gain: 1.0,
        ),
    ],
    frameRate: ProjectFrameRate.fps24,
    ink: timelineSeWaveformInk,
  );

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    TimelineRowSounds? sounds,
    String generation = 'wave-q2',
  }) => TimelineRowCellsPainter(
    layer: layer,
    geometry: testFrameGeometry(
      frameCellExtent: cell,
      frameEndIndexExclusive: frames,
    ),
    crossAxisExtent: across.toDouble(),
    exposureStateForLayer: exposureOf,
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: const TextStyle(fontSize: 11),
    tileStore: store,
    substrateGeneration: generation,
    sounds: sounds,
  );

  /// What a paint asks of the store for the row's one span.
  TimelineGridTilePicture? ask(TimelineRowCellsPainter painter) =>
      store.tileFor(
        painter: painter,
        spanStartIndex: 0,
        spanEndIndexExclusive: frames,
        devicePixelRatio: 1.0,
      );

  /// The row's span, cold, landed off-frame.
  Future<TimelineGridTilePicture> landed(
    TimelineRowCellsPainter painter,
  ) async {
    expect(ask(painter), isNull, reason: 'premise: cold');
    await tileStoreIdle(store);
    return ask(painter)!;
  }

  /// The pixel at (x, y) of a picture [width] across.
  List<int> at(Uint8List bytes, int width, int x, int y) =>
      bytes.sublist((y * width + x) * 4, (y * width + x) * 4 + 4);

  /// Where [waved] and [plain] — the same row's span with its sound and
  /// without — tell apart: every column past the strip, and the rows
  /// past the band's reach of every column, are the paper alone; the
  /// band's middle across the strip is the ink laid OVER the paper.
  void expectTheWaveOverThePaper(Uint8List waved, Uint8List plain) {
    const width = frames * 128;
    for (var x = heard * 128; x < width; x += 1) {
      for (var y = 0; y < across; y += 1) {
        expect(
          at(waved, width, x, y),
          at(plain, width, x, y),
          reason: 'past the strip ($x, $y) is the paper',
        );
      }
    }
    // One lane across 28: its reach 28 / 2 − 1 = 13 either side of 14,
    // rows 1 to 26.
    for (var x = 0; x < heard * 128; x += 1) {
      for (final y in const [0, across - 1]) {
        expect(
          at(waved, width, x, y),
          at(plain, width, x, y),
          reason: 'past the band ($x, $y) is the paper',
        );
      }
      final ink = at(waved, width, x, 14);
      final paper = at(plain, width, x, 14);
      expect(ink, isNot(paper), reason: 'the band crosses column $x');
      expect(
        ink[3],
        greaterThanOrEqualTo(paper[3]),
        reason: 'laid over the paper, not in its place, at column $x',
      );
    }
    expect(
      at(plain, width, 0, 14)[3],
      greaterThan((0.22 * 255).round()),
      reason: '⛔전제: the paper is more opaque than the ink alone',
    );
  }

  test('a sound\'s wave is baked into its cells\' tile, over their paper, '
      'where it is heard', () async {
    final waved = await landed(
      painterFor(seLayer('se-waved'), sounds: soundsOf(landed: true)),
    );
    final plain = await landed(painterFor(seLayer('se-plain')));
    expectTheWaveOverThePaper(waved.picture.read(), plain.picture.read());
  });

  test('🚨peaks landing on the same layer bake its tile again — and the '
      'same sounds again keep it', () async {
    final layer = seLayer('se-late');
    final before = await landed(
      painterFor(layer, sounds: soundsOf(landed: false), generation: 'late'),
    );
    final bare = before.picture.read();

    final after = ask(
      painterFor(layer, sounds: soundsOf(landed: true), generation: 'late'),
    );
    expect(
      identical(after, before),
      isFalse,
      reason:
          'the layer did not move, its sounds did: the tile from before the '
          'peaks showed the row without its wave',
    );
    expectTheWaveOverThePaper(after!.picture.read(), bare);
    expect(
      identical(
        ask(
          painterFor(
            layer,
            sounds: soundsOf(landed: true),
            generation: 'late',
          ),
        ),
        after,
      ),
      isTrue,
      reason: 'equal sounds in a new list bake the same pixels',
    );
  });

  test('where no tile holds the span, the canvas paints the wave over the '
      'paper there, as the tile bakes it', () async {
    Future<Uint8List> painted(TimelineRowCellsPainter painter) async {
      final recorder = ui.PictureRecorder();
      // No grid's screen to lay on: the row paints its cells on the canvas.
      painter.paint(
        Canvas(recorder),
        const Size(frames * cell, across + 0.0),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(frames * 128, across);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      return bytes;
    }

    final layer = seLayer('se-canvas');
    expectTheWaveOverThePaper(
      await painted(painterFor(layer, sounds: soundsOf(landed: true))),
      await painted(painterFor(layer)),
    );
  });
}
