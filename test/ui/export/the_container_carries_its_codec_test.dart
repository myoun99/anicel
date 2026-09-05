import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// 🚨PICKING A CONTAINER MUST NOT LEAVE A CODEC IT CANNOT HOLD.
///
/// MP4 and MOV do not carry the same codecs, and a build can have some of
/// them switched off. Tapping MOV while H.265 is selected has to land on
/// a codec MOV can actually write — otherwise the dialog shows a pairing
/// that fails at the encoder, and the user finds out at render time.
///
/// The dialog test taps the container AND then the codec, so it never
/// asked what the container tap alone does; the whole rule survived
/// mutation (2026-09-05).
void main() {
  ExportFormatCapabilities capabilities({
    bool Function(ExportVideoContainer, ExportVideoCodec)? videoEnabled,
  }) => ExportFormatCapabilities(
    stills: ExportStillFormat.values,
    video: const {
      ExportVideoContainer.mp4: [ExportVideoCodec.h264, ExportVideoCodec.h265],
      ExportVideoContainer.mov: [
        ExportVideoCodec.h264,
        ExportVideoCodec.proresProxy,
        ExportVideoCodec.prores4444,
      ],
    },
    videoEnabled: videoEnabled,
  );

  Future<ExportFormatSelection?> tapChip(
    WidgetTester tester,
    String key, {
    required ExportFormatSelection selection,
    ExportFormatCapabilities? caps,
    bool enabled = true,
  }) async {
    ExportFormatSelection? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportFormatModule(
            selection: selection,
            capabilities: caps ?? capabilities(),
            enabled: enabled,
            onChanged: (next) => changed = next,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
    return changed;
  }

  const onMp4H265 = ExportFormatSelection(
    kind: ExportMediaKind.video,
    container: ExportVideoContainer.mp4,
    videoCodec: ExportVideoCodec.h265,
  );

  testWidgets('the MODEL already refuses an illegal pair: MOV cannot hold '
      'H.265, so the container tap lands on H.264 — legal in both', (
    tester,
  ) async {
    final next = await tapChip(
      tester,
      'export-format-container-mov',
      selection: onMp4H265,
    );

    expect(next, isNotNull);
    expect(next!.container, ExportVideoContainer.mov);
    expect(next.videoCodec, ExportVideoCodec.h264);
  });

  testWidgets('🚨but LEGAL is not WRITABLE — when this build cannot write '
      'H.264 into MOV, the tap walks on to a codec it can', (tester) async {
    final next = await tapChip(
      tester,
      'export-format-container-mov',
      selection: onMp4H265,
      caps: capabilities(
        videoEnabled: (container, codec) =>
            container != ExportVideoContainer.mov ||
            codec != ExportVideoCodec.h264,
      ),
    );

    expect(next!.videoCodec, ExportVideoCodec.proresProxy);
  });

  testWidgets('🚨and it keeps walking — the first WRITABLE codec, not the '
      'first one in the lineup', (tester) async {
    final next = await tapChip(
      tester,
      'export-format-container-mov',
      selection: onMp4H265,
      caps: capabilities(
        videoEnabled: (container, codec) =>
            container != ExportVideoContainer.mov ||
            codec == ExportVideoCodec.prores4444,
      ),
    );

    expect(next!.videoCodec, ExportVideoCodec.prores4444);
  });

  testWidgets('a codec the new container CAN write is left alone', (
    tester,
  ) async {
    final next = await tapChip(
      tester,
      'export-format-container-mov',
      selection: const ExportFormatSelection(
        kind: ExportMediaKind.still,
        container: ExportVideoContainer.mp4,
        videoCodec: ExportVideoCodec.h264,
      ),
    );

    expect(next!.kind, ExportMediaKind.video);
    expect(next.container, ExportVideoContainer.mov);
    expect(
      next.videoCodec,
      ExportVideoCodec.h264,
      reason: 'MOV writes H.264 here — nothing to move',
    );
  });

  testWidgets('⛔a container with NO writable codec is not tappable at all', (
    tester,
  ) async {
    ExportFormatSelection? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportFormatModule(
            selection: onMp4H265,
            capabilities: capabilities(
              videoEnabled: (container, _) =>
                  container != ExportVideoContainer.mov,
            ),
            enabled: true,
            onChanged: (next) => changed = next,
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('export-format-container-mov')),
    );
    await tester.pump();

    expect(changed, isNull);
  });

  testWidgets('🚨BOTH channel chips are offered on a format with alpha — one '
      'of them is the current answer and the other is the choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportFormatModule(
            selection: const ExportFormatSelection(
              kind: ExportMediaKind.still,
              stillFormat: ExportStillFormat.png,
            ),
            capabilities: capabilities(),
            enabled: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    for (final channels in ExportChannels.values) {
      expect(
        find.byKey(
          ValueKey<String>('export-format-channels-${channels.jsonValue}'),
        ),
        findsOneWidget,
        reason: '${channels.name} has no chip',
      );
    }
  });

  testWidgets('🚨bitrate ZERO reads Auto — the encoder picks, and a bare 0 '
      'would read as "no bitrate"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportFormatModule(
            selection: const ExportFormatSelection(
              kind: ExportMediaKind.video,
              videoCodec: ExportVideoCodec.h264,
              videoBitrateMbps: 0,
            ),
            capabilities: capabilities(),
            enabled: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final bar = tester.widget<FieldSlider>(
      find.byKey(const ValueKey<String>('export-format-bitrate')),
    );
    expect(bar.valueText, 'Auto');
    expect(
      bar.valueTextBuilder!(12),
      '12 Mb',
      reason: 'and a real rate says its unit while the bar is dragged',
    );
  });

  testWidgets('⛔a DISABLED module hands the bar no onChanged, so it dims '
      'itself rather than disappearing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportFormatModule(
            selection: const ExportFormatSelection(
              kind: ExportMediaKind.still,
              stillFormat: ExportStillFormat.jpg,
            ),
            capabilities: capabilities(),
            enabled: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final bar = tester.widget<FieldSlider>(
      find.byKey(const ValueKey<String>('export-format-quality')),
    );
    expect(bar.onChanged, isNull);
  });
}
