import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/export/ae_script.dart';

void main() {
  AeTransform still({
    List<double> anchor = const [4, 4],
    List<double> position = const [4, 4],
  }) => AeTransform(
    anchor: AeChannel.still(anchor),
    position: AeChannel.still(position),
    scale: const AeChannel.still([100, 100]),
    rotation: const AeChannel.still([0]),
    opacity: const AeChannel.still([100]),
  );

  String scriptOf(List<AeComp> comps, {ProjectFrameRate? rate}) =>
      writeAeScript(
        AeScript(
          name: 'Work',
          rate: rate ?? ProjectFrameRate.fps24,
          comps: comps,
        ),
      );

  AeComp compOf(List<AeLayer> layers, {String name = 'c1 canvas'}) => AeComp(
    name: name,
    width: 8,
    height: 8,
    frames: 11,
    layers: layers,
  );

  group('a value that never changes is held, one that does is keyed', () {
    test('a still channel is one value', () {
      expect(AeChannel.sampled(5, (_) => [3, 4]).value, [3, 4]);
      expect(
        AeChannel.sampled(5, (frame) => [frame * 1.0]).frames,
        hasLength(5),
      );
    });

    test('keys stand only where a line through the frames bends', () {
      // 0 → 50 over frames 0..5, then held at 50 to frame 10.
      final rotation = AeChannel.sampled(
        11,
        (frame) => [if (frame <= 5) frame * 10.0 else 50],
      );
      final script = scriptOf([
        compOf([
          AeLayer(
            name: 'A',
            source: const AeNullSource(),
            transform: AeTransform(
              anchor: const AeChannel.still([4, 4]),
              position: const AeChannel.still([4, 4]),
              scale: const AeChannel.still([100, 100]),
              rotation: rotation,
              opacity: const AeChannel.still([100]),
            ),
          ),
        ]),
      ]);
      expect(
        script,
        contains('keys(L[0], "ADBE Rotate Z", [0, 5, 10], [0, 50, 50]);'),
      );
      expect(script, contains('hold(L[0], "ADBE Scale", [100, 100]);'));
    });

    test('a moving anchor is keyed at every frame — it is spatial', () {
      final script = scriptOf([
        compOf([
          AeLayer(
            name: 'A',
            source: const AeNullSource(),
            transform: AeTransform(
              anchor: AeChannel.sampled(3, (frame) => [frame * 2.0, 0]),
              position: const AeChannel.still([4, 4]),
              scale: const AeChannel.still([100, 100]),
              rotation: const AeChannel.still([0]),
              opacity: const AeChannel.still([100]),
            ),
          ),
        ]),
      ]);
      expect(
        script,
        contains(
          'keys(L[0], "ADBE Anchor Point", [0, 1, 2], '
          '[[0, 0], [2, 0], [4, 0]]);',
        ),
      );
    });

    test('a moving position is keyed as its two dimensions apart', () {
      final script = scriptOf([
        compOf([
          AeLayer(
            name: 'A',
            source: const AeNullSource(),
            transform: AeTransform(
              anchor: const AeChannel.still([4, 4]),
              // x runs a line; y holds, then steps once.
              position: AeChannel.sampled(
                5,
                (frame) => [frame * 1.0, if (frame < 3) 0 else 7],
              ),
              scale: const AeChannel.still([100, 100]),
              rotation: const AeChannel.still([0]),
              opacity: const AeChannel.still([100]),
            ),
          ),
        ]),
      ]);
      expect(script, contains('split(L[0]);'));
      expect(
        script,
        contains('keys(L[0], "ADBE Position_0", [0, 4], [0, 4]);'),
      );
      expect(
        script,
        contains('keys(L[0], "ADBE Position_1", [0, 2, 3, 4], [0, 0, 7, 7]);'),
      );
      expect(script, isNot(contains('"ADBE Position",')));
    });
  });

  group('the layers of a comp', () {
    test('a cel comp holds each cel a frame, its file imported once', () {
      const bank = AeComp(
        name: 'A cels',
        width: 8,
        height: 8,
        frames: 3,
        tucked: true,
        layers: [
          AeLayer(name: '1', source: AeStill(path: 'A/A0001.png', frame: 0)),
          AeLayer(name: '2', source: AeStill(path: 'A/A0002.png', frame: 1)),
        ],
      );
      final script = scriptOf([
        bank,
        compOf([
          AeLayer(
            name: 'A',
            source: const AeCompSource(bank),
            timeRemap: const [
              (frame: 0, source: 0),
              (frame: 3, source: 2),
              (frame: 5, source: 1),
            ],
            transform: still(),
          ),
        ]),
      ]);
      expect(script, contains('C[0] = comp("A cels", 8, 8, 3, parts);'));
      expect(script, contains('S[0] = footage("A/A0001.png");'));
      expect(script, contains('L[1] = still(C[0], S[1], 1);'));
      expect(script, contains('C[1] = comp("c1 canvas", 8, 8, 11, bin);'));
      expect(script, contains('L[0] = C[1].layers.add(C[0]);'));
      expect(script, contains('remap(L[0], [0, 3, 5], [0, 2, 1]);'));
      // Measured in AE: a remapped comp left to follow its holder's rate
      // drew the wrong cels; a value between two frames is read as the
      // lower one.
      expect(script, contains('layer.source.preserveNestedFrameRate = true;'));
      expect(script, contains('values.push(t(sources[i]));'));
    });

    test('a layer under a folder is parented to its null, which goes on top',
        () {
      final folder = AeLayer(
        name: 'F',
        source: const AeNullSource(),
        transform: still(),
      );
      final script = scriptOf([
        compOf([
          folder,
          AeLayer(
            name: 'A',
            source: const AeNullSource(),
            parent: folder,
            transform: still(),
          ),
        ]),
      ]);
      expect(script, contains('L[0] = C[0].layers.addNull(C[0].duration);'));
      expect(script, contains('parent(L[1], L[0]);'));
      expect(script, contains('L[0].moveToBeginning();'));
      // The parent is set before the values, which are in its space.
      expect(
        script.indexOf('parent(L[1], L[0]);'),
        lessThan(script.indexOf('hold(L[1], "ADBE Anchor Point"')),
      );
    });

    test('a blend is After Effects\' own name, a hidden row is off', () {
      final script = scriptOf([
        compOf(const [
          AeLayer(
            name: 'A',
            source: AeNullSource(),
            blend: LayerBlendMode.multiply,
            enabled: false,
          ),
          AeLayer(
            name: 'B',
            source: AeNullSource(),
            blend: LayerBlendMode.passThrough,
          ),
        ]),
      ]);
      expect(script, contains('L[0].blendingMode = BlendingMode.MULTIPLY;'));
      expect(script, contains('L[0].enabled = false;'));
      expect(script, isNot(contains('L[1].blendingMode')));
      expect(script, isNot(contains('L[1].enabled')));
    });
  });

  test('a sound is its file beside the script, laid as it is', () {
    final script = scriptOf([
      compOf(const [AeLayer(name: 'C1.wav', source: AeSound('C1.wav'))]),
    ]);
    expect(script, contains('S[0] = footage("C1.wav");'));
    expect(script, contains('L[0] = C[0].layers.add(S[0]);'));
    expect(script, contains('L[0].name = "C1.wav";'));
    expect(script, isNot(contains('hold(L[0]')));
  });

  test('the rate is written as its fraction', () {
    final script = scriptOf([
      compOf(const []),
    ], rate: const ProjectFrameRate.ntsc(24));
    expect(script, contains('var RATE_N = 24000;'));
    expect(script, contains('var RATE_D = 1001;'));
  });

  test('the script is ASCII alone — every other character escaped', () {
    final script = writeAeScript(
      AeScript(
        name: '作品 "1"',
        rate: ProjectFrameRate.fps24,
        comps: [
          compOf(const [], name: 'カット\\1'),
        ],
      ),
    );
    expect(script.codeUnits.every((unit) => unit < 0x80), isTrue);
    // Each character past ASCII as its escape, spelled out here from char
    // codes so the expectation does not go through the same escaping.
    final slash = String.fromCharCode(0x5c);
    String escaped(String text) => [
      for (final unit in text.codeUnits)
        '${slash}u${unit.toRadixString(16).padLeft(4, '0')}',
    ].join();
    expect(
      script,
      contains('addFolder("${escaped('作品')} $slash"1$slash"")'),
    );
    expect(
      script,
      contains('comp("${escaped('カット')}$slash${slash}1", 8, 8, 11, bin)'),
    );
  });

  group('formatAeNumber', () {
    test('integers bare, fractions trimmed to four decimals', () {
      expect(formatAeNumber(960), '960');
      expect(formatAeNumber(-45), '-45');
      expect(formatAeNumber(970.5), '970.5');
      expect(formatAeNumber(150.25), '150.25');
      expect(formatAeNumber(1.23456789), '1.2346');
      expect(formatAeNumber(0.10000), '0.1');
    });
  });
}
