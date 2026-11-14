import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// A sound's wave reaches a frame grid's picture through the package's Dart
/// (the-waveform-is-drawn-on-the-cpu-beside-its-kernel ①): its peaks kept
/// once ([GpuWavePeaks]) and drawn ([GpuWave.draw]) straight over a fresh
/// picture's clear, as the strip shows them — each field of the view where
/// the pass takes it.
/// How the band lands on pixels is the crate's to pin, and these are its
/// hand cases (rust/src/kernels/timeline/wave/tests.rs, which writes out
/// their sums) — here, what Dart hands it.
void main() {
  late GpuWave wave;
  const full = 65535;
  const none = [0, 0, 0, 0];
  const all = [255, 255, 255, 255];
  List<int> white(int alpha) => [255, 255, 255, alpha];

  setUpAll(() => wave = GpuWave(appGpuEngine));
  tearDownAll(() => wave.free());

  /// 4 pixels a bucket — a frame a second, a bucket a second, 4 pixels a
  /// frame — on one lane 8 pixels across, white, unless said otherwise.
  GpuWaveView view({
    int along0 = 0,
    int length = 1 << 20,
    bool vertical = false,
    int frameQ8 = 4 * 256,
    int fpsNumerator = 1,
    int fpsDenominator = 1,
    int bucketsPerSecond = 1,
    int leadingFrames = 0,
    int acrossQ8 = 8 * 256,
    int gainQ16 = 65536,
    int rgba = 0xFFFFFFFF,
  }) => (
    along0: along0,
    length: length,
    vertical: vertical,
    frameQ8: frameQ8,
    fpsNumerator: fpsNumerator,
    fpsDenominator: fpsDenominator,
    bucketsPerSecond: bucketsPerSecond,
    leadingFrames: leadingFrames,
    acrossQ8: acrossQ8,
    gainQ16: gainQ16,
    rgba: rgba,
  );

  /// [lanes] drawn as [shown] shows them into a fresh picture [width] ×
  /// [height]: its bytes.
  Uint8List drawn(
    List<List<int>> lanes,
    GpuWaveView shown,
    int width,
    int height,
  ) {
    final picture = GpuGridPicture(appGpuEngine, width, height);
    addTearDown(picture.free);
    final peaks = GpuWavePeaks(appGpuEngine, [
      for (final lane in lanes) Uint16List.fromList(lane),
    ]);
    wave.draw(picture, peaks, shown);
    return picture.read();
  }

  /// Column [x], top to bottom, of a picture [width] × [height].
  List<List<int>> column(Uint8List bytes, int width, int height, int x) => [
    for (var y = 0; y < height; y++)
      bytes.sublist((y * width + x) * 4, (y * width + x) * 4 + 4),
  ];

  // Full scale reaches 3 pixels of the lane's 4: rows 1 to 6 whole. The
  // colour (200, 48, 160) at 128 is kept straight, as a grid's tile is —
  // the screen premultiplies it as it lays it.
  test('a full peak is drawn a pixel short of its share, straight', () {
    final bytes = drawn(
      [List.filled(4, full)],
      view(rgba: 0x80A030C8),
      8,
      8,
    );
    const drawnRow = [200, 48, 160, 128];
    for (var x = 0; x < 8; x++) {
      expect(column(bytes, 8, 8, x), [
        none,
        for (var y = 1; y < 7; y++) drawnRow,
        none,
      ], reason: 'column $x');
    }
  });

  // A frame of trim moves the line 4 pixels left — column 1 shows what
  // column 5 did; a frame before the file moves it 4 right, and the strip
  // before the file shows nothing; a picture further along the strip is the
  // same columns.
  test('the trim and where the picture stands move the line along', () {
    const peaks = [
      [0, full, 0, 0],
    ];
    final falling = [
      none,
      white(64),
      all,
      all,
      all,
      all,
      white(64),
      none,
    ];
    expect(
      column(drawn(peaks, view(leadingFrames: 1), 8, 8), 8, 8, 1),
      falling,
    );
    expect(column(drawn(peaks, view(along0: 5), 4, 8), 4, 8, 0), falling);
    final early = drawn(peaks, view(leadingFrames: -1), 8, 8);
    for (var x = 0; x < 4; x++) {
      expect(column(early, 8, 8, x), List.filled(8, none), reason: '$x');
    }
    expect(column(early, 8, 8, 4), [
      none,
      none,
      none,
      white(191),
      white(191),
      none,
      none,
      none,
    ]);
  });

  // A strip 3 pixels long from the picture's column 2: the sound goes on
  // either side of it, the band only where it is.
  test('a column past either end of the strip is left as it was', () {
    final bytes = drawn(
      [List.filled(8, full)],
      view(along0: -2, length: 3),
      8,
      8,
    );
    final band = [none, for (var y = 1; y < 7; y++) all, none];
    for (var x = 0; x < 8; x++) {
      expect(
        column(bytes, 8, 8, x),
        x >= 2 && x < 5 ? band : List.filled(8, none),
        reason: 'column $x',
      );
    }
  });

  test('running down, the strip is the picture turned', () {
    const peaks = [
      [0, full, 0, 0, 32768, 0],
    ];
    final across = drawn(peaks, view(), 12, 8);
    final down = drawn(peaks, view(vertical: true), 8, 12);
    for (var x = 0; x < 12; x++) {
      for (var y = 0; y < 8; y++) {
        final at = (y * 12 + x) * 4;
        final turned = (x * 8 + y) * 4;
        expect(
          down.sublist(turned, turned + 4),
          across.sublist(at, at + 4),
          reason: '($x, $y)',
        );
      }
    }
    expect(across, isNot(down), reason: 'premise: the strip is not square');
  });

  // Half the gain is half the reach: full scale draws as half scale does.
  // Two lanes on 16 pixels take a share of 8 each.
  test('the gain and the strip across are drawn into the band', () {
    final halfGain = drawn([List.filled(4, full)], view(gainQ16: 32768), 8, 8);
    expect(column(halfGain, 8, 8, 3), [
      none,
      none,
      white(128),
      all,
      all,
      white(128),
      none,
      none,
    ]);
    expect(
      column(
        drawn(
          [List.filled(4, full), List.filled(4, 32768)],
          view(acrossQ8: 16 * 256),
          4,
          16,
        ),
        4,
        16,
        2,
      ),
      [
        none,
        all,
        all,
        all,
        all,
        all,
        all,
        none,
        none,
        none,
        white(128),
        all,
        all,
        white(128),
        none,
        none,
      ],
    );
  });

  // A hundred buckets a pixel: column 1 runs from bucket 100 to 200, so it
  // shows the peak at 105, column 2 the half one at 290, and the edge at 400
  // stands in both of the columns it ends and starts.
  test('the pace puts each column over its buckets', () {
    final peaks = List.filled(501, 0)
      ..[105] = full
      ..[290] = 32768
      ..[400] = full;
    final bytes = drawn(
      [peaks],
      view(frameQ8: 256, bucketsPerSecond: 100),
      6,
      8,
    );
    final whole = [none, all, all, all, all, all, all, none];
    expect(column(bytes, 6, 8, 0), List.filled(8, none));
    expect(column(bytes, 6, 8, 1), whole);
    expect(column(bytes, 6, 8, 2), [
      none,
      none,
      white(128),
      all,
      all,
      white(128),
      none,
      none,
    ]);
    expect(column(bytes, 6, 8, 3), whole);
    expect(column(bytes, 6, 8, 4), whole);
    expect(column(bytes, 6, 8, 5), List.filled(8, none));
  });

  // Two frames a second at two buckets a second is the pace of one at one;
  // a frame a second at half a frame's buckets is not.
  test('the frames a second are a fraction, read as written', () {
    const peaks = [
      [0, full, 0, 0, 32768, 0],
    ];
    final once = drawn(peaks, view(), 24, 8);
    expect(
      drawn(peaks, view(fpsNumerator: 2, bucketsPerSecond: 2), 24, 8),
      once,
    );
    expect(
      drawn(peaks, view(fpsDenominator: 2, bucketsPerSecond: 2), 24, 8),
      isNot(once),
    );
  });

  test('a view the pass refuses is refused with why', () {
    expect(
      () => drawn([List.filled(4, full)], view(frameQ8: 0), 8, 8),
      throwsA(
        isA<GpuRefused>().having(
          (refused) => refused.message,
          'why',
          contains('has no pace'),
        ),
      ),
    );
  });

  test('peaks it cannot keep are refused before or as they are handed', () {
    expect(
      () => GpuWavePeaks(appGpuEngine, [Uint16List(4), Uint16List(3)]),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'lanes of 3 and 4',
        ),
      ),
    );
    expect(
      () => GpuWavePeaks(appGpuEngine, const []),
      throwsA(
        isA<GpuRefused>().having(
          (refused) => refused.message,
          'why',
          contains('no lane'),
        ),
      ),
    );
  });
}
