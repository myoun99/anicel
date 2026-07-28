import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';

void main() {
  List<String> args({
    ExportVideoContainer container = ExportVideoContainer.mp4,
    ExportVideoCodec codec = ExportVideoCodec.h264,
    bool alpha = false,
    int bitrateBps = 0,
    String? audioMixPath,
    String output = 'out.mp4',
  }) => VideoExportService.buildFfmpegArguments(
    frameRate: ProjectFrameRate.fps24,
    outputFilePath: output,
    audioMixPath: audioMixPath,
    container: container,
    codec: codec,
    alpha: alpha,
    bitrateBps: bitrateBps,
  );

  String joined(List<String> arguments) => arguments.join(' ');

  test('H.264 keeps the original shape (regression pin)', () {
    final arguments = args();
    expect(joined(arguments), contains('-c:v libx264 -pix_fmt yuv420p'));
    expect(joined(arguments), contains('-crf 18'));
    expect(joined(arguments), contains('color=white'));
  });

  test('H.265 = the confirmed software libx265', () {
    final arguments = args(codec: ExportVideoCodec.h265);
    expect(joined(arguments), contains('-c:v libx265 -pix_fmt yuv420p'));
    expect(joined(arguments), contains('-crf 20'));
  });

  test('a bitrate target replaces CRF', () {
    final arguments = args(codec: ExportVideoCodec.h265, bitrateBps: 16000000);
    expect(joined(arguments), contains('-b:v 16000000'));
    expect(joined(arguments), isNot(contains('-crf')));
  });

  test('ProRes flavors map to prores_ks profiles in 10-bit 4:2:2', () {
    final byCodec = {
      ExportVideoCodec.proresProxy: 0,
      ExportVideoCodec.proresLt: 1,
      ExportVideoCodec.prores422: 2,
      ExportVideoCodec.proresHq: 3,
    };
    byCodec.forEach((codec, profile) {
      final arguments = args(
        container: ExportVideoContainer.mov,
        codec: codec,
        output: 'out.mov',
      );
      expect(
        joined(arguments),
        contains('-c:v prores_ks -profile:v $profile -vendor apl0'),
      );
      expect(joined(arguments), contains('-pix_fmt yuv422p10le'));
    });
  });

  test('4444 with alpha: yuva444p10le, transparent pad, PCM audio', () {
    final arguments = args(
      container: ExportVideoContainer.mov,
      codec: ExportVideoCodec.prores4444,
      alpha: true,
      audioMixPath: 'mix.wav',
      output: 'out.mov',
    );
    expect(joined(arguments), contains('-profile:v 4'));
    expect(joined(arguments), contains('-pix_fmt yuva444p10le'));
    expect(joined(arguments), contains('color=black@0.0'));
    expect(joined(arguments), contains('-c:a pcm_s16le'));
    expect(joined(arguments), isNot(contains('aac')));
  });

  test('4444 without alpha stays opaque 4:4:4', () {
    final arguments = args(
      container: ExportVideoContainer.mov,
      codec: ExportVideoCodec.prores4444,
      output: 'out.mov',
    );
    expect(joined(arguments), contains('-pix_fmt yuv444p10le'));
    expect(joined(arguments), contains('color=white'));
  });

  test('H.26x with audio keeps AAC', () {
    final arguments = args(audioMixPath: 'mix.wav');
    expect(joined(arguments), contains('-c:a aac'));
  });
}
