// IRIS TABLE PROBE — what a camera lens blur's table of its iris's rows
// costs to make on THIS device, and what the gather that reads it costs,
// so that whether to keep it is measured, not guessed.
//
//   flutter run -d windows --release -t tool/probe/iris_table_probe_main.dart \
//     --dart-define=IRIS_OUT=<dir>
//
// Writes `report.txt` into IRIS_OUT and exits. Measurement, not a feature.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:anicel/src/services/shaded_passes.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/canvas/raster_picture.dart';

const _outDir = String.fromEnvironment('IRIS_OUT', defaultValue: '');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    final out = Directory(_outDir.isEmpty ? 'iris_probe_out' : _outDir);
    await out.create(recursive: true);
    final report = StringBuffer();
    try {
      await _measure(report);
      report.writeln('DONE');
    } on Object catch (e, st) {
      report.writeln('FAILED: $e\n$st');
    }
    await File('${out.path}/report.txt').writeAsString(report.toString());
    exit(0);
  }

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: Text('iris probe')));
}

const IrisProperties iris = (
  sides: 6,
  roundness: 0.3,
  aspect: 1,
  rotation: 0.2,
  fringe: 0,
);

const IrisMap map = (
  channel: IrisMapChannel.luminance,
  focal: 128,
  inverts: false,
);

IrisGatherPass passOf(double radius, {required bool mapped}) =>
    IrisGatherPass(
      radius: radius,
      iris: iris,
      paper: null,
      light: null,
      map: mapped ? map : null,
    );

/// Waits until the GPU has drawn every one of [images]: a one-pixel
/// picture over all of them, read back.
Future<void> drawn(List<ui.Image> images) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (final image in images) {
    canvas.drawImageRect(
      image,
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..blendMode = ui.BlendMode.plus,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  picture.dispose();
  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
}

double median(List<double> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

/// Milliseconds a batch of [n] made by [make] takes, drawn — the median of
/// [runs] batches, each after its own warm-up.
Future<({double total, double cpu})> timed(
  ui.Image Function() make, {
  required int n,
  int runs = 5,
}) async {
  final totals = <double>[];
  final cpus = <double>[];
  for (var r = 0; r < runs; r += 1) {
    final warm = [make(), make()];
    await drawn(warm);
    for (final image in warm) {
      image.dispose();
    }
    final clock = Stopwatch()..start();
    final made = [for (var i = 0; i < n; i += 1) make()];
    final cpu = clock.elapsedMicroseconds / 1000;
    await drawn(made);
    totals.add(clock.elapsedMicroseconds / 1000);
    cpus.add(cpu);
    for (final image in made) {
      image.dispose();
    }
  }
  return (total: median(totals), cpu: median(cpus));
}

ui.Image inputOf(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rect = ui.Rect.fromLTWH(0, 0, width * 1.0, height * 1.0);
  canvas.drawRect(
    rect,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        const [ui.Color(0xFF204080), ui.Color(0xFFE0C040)],
      ),
  );
  return rasterPicture(recorder, width, height);
}

Future<void> _measure(StringBuffer report) async {
  await IrisBlurShader.load();
  final baseline = await timed(() => inputOf(1, 1), n: 1);
  report.writeln(
    'baseline (one 1x1 image, drawn and read back): '
    '${baseline.total.toStringAsFixed(2)} ms',
  );

  report.writeln('\n== table alone (tableFor), ms a table ==');
  for (final mapped in [false, true]) {
    // ⚠️No map at 4000: 2048×2049 float texels, past a probe's want.
    final radii = [8.0, 40.0, 150.0, 500.0, 1500.0, if (!mapped) 4000.0];
    for (final radius in radii) {
      final pass = passOf(radius, mapped: mapped);
      final probe = IrisBlurShader.tableFor(pass.rows);
      final size = '${probe.width}x${probe.height}';
      probe.dispose();
      const n = 10;
      final t = await timed(() => IrisBlurShader.tableFor(pass.rows), n: n);
      report.writeln(
        '${mapped ? 'map  ' : 'plain'} r=$radius table=$size '
        'each=${((t.total - baseline.total) / n).toStringAsFixed(3)} '
        '(cpu ${(t.cpu / n).toStringAsFixed(3)})',
      );
      print(report.toString().split('\n').lastWhere((l) => l.isNotEmpty));
    }
  }

  // Its table kept from the first draw on ([IrisBlurShader.tableBytes]).
  report.writeln('\n== whole gather (gatherFor), ms a draw ==');
  for (final (width, height) in [(512, 512), (1920, 1080)]) {
    final input = inputOf(width, height);
    for (final mapped in [false, true]) {
      for (final radius in [8.0, 40.0, 150.0]) {
        final pass = passOf(radius, mapped: mapped);
        const n = 3;
        final t = await timed(() {
          final shader = IrisBlurShader.gatherFor(
            sums: input,
            input: input,
            pass: pass,
            map: mapped ? input : null,
          );
          try {
            return shadedRaster(shader, width, height);
          } finally {
            shader.dispose();
          }
        }, n: n, runs: 3);
        report.writeln(
          '${width}x$height ${mapped ? 'map  ' : 'plain'} r=$radius '
          'each=${((t.total - baseline.total) / n).toStringAsFixed(3)}',
        );
        print(report.toString().split('\n').lastWhere((l) => l.isNotEmpty));
      }
    }
    input.dispose();
  }
}
