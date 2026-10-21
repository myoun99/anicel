import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/export_format_pick.dart';

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

  /// The module over [selection], with [row] picked from the list behind
  /// [button] — what the module hands back, or null.
  Future<ExportFormatSelection?> pick(
    WidgetTester tester,
    String row, {
    required ExportFormatSelection selection,
    ExportFormatCapabilities? caps,
    String button = 'export-format-file',
  }) async {
    ExportFormatSelection? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportFormatModule(
            selection: selection,
            capabilities: caps ?? capabilities(),
            enabled: true,
            onChanged: (next) => changed = next,
          ),
        ),
      ),
    );
    await pickFromExportList(tester, button, row);
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
    final next = await pick(
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
    final next = await pick(
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
    final next = await pick(
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
    final next = await pick(
      tester,
      'export-format-container-mov',
      selection: const ExportFormatSelection(
        kind: ExportMediaKind.video,
        container: ExportVideoContainer.mp4,
        videoCodec: ExportVideoCodec.h264,
      ),
    );

    expect(next!.container, ExportVideoContainer.mov);
    expect(
      next.videoCodec,
      ExportVideoCodec.h264,
      reason: 'MOV writes H.264 here — nothing to move',
    );
  });

  testWidgets('⛔a container with NO writable codec is not pickable at all', (
    tester,
  ) async {
    final next = await pick(
      tester,
      'export-format-container-mov',
      selection: onMp4H265,
      caps: capabilities(
        videoEnabled: (container, _) => container != ExportVideoContainer.mov,
      ),
    );

    expect(next, isNull);
  });

  // 🗣️I-117 (유저 2026-10-21): 「동영상이랑 이미지 둘다있으면 먼저 둘중하나
  // 리스트팝오버로 고르고, 그 옆에 해당에 맞는 팝오버 버튼 뜸」.
  group('동영상 or 이미지 is picked first, and lands on a format of its own', () {
    testWidgets('이미지 lands on the still format it last stood on', (
      tester,
    ) async {
      final next = await pick(
        tester,
        'export-format-kind-still',
        button: 'export-format-kind',
        selection: const ExportFormatSelection(
          kind: ExportMediaKind.video,
          stillFormat: ExportStillFormat.tiff,
        ),
      );

      expect(next!.kind, ExportMediaKind.still);
      expect(next.stillFormat, ExportStillFormat.tiff);
    });

    testWidgets('🚨동영상 lands on the container it last stood on — with a '
        'codec that container can hold', (tester) async {
      final next = await pick(
        tester,
        'export-format-kind-video',
        button: 'export-format-kind',
        selection: const ExportFormatSelection(
          kind: ExportMediaKind.still,
          container: ExportVideoContainer.mov,
          videoCodec: ExportVideoCodec.h265,
        ),
      );

      expect(next!.kind, ExportMediaKind.video);
      expect(next.container, ExportVideoContainer.mov);
      expect(next.videoCodec, ExportVideoCodec.h264);
    });

    testWidgets('a format this build cannot write is passed over for the '
        'first one it can', (tester) async {
      final stillOff = await pick(
        tester,
        'export-format-kind-still',
        button: 'export-format-kind',
        selection: const ExportFormatSelection(
          kind: ExportMediaKind.video,
          stillFormat: ExportStillFormat.jpg,
        ),
        caps: ExportFormatCapabilities(
          stills: ExportStillFormat.values,
          video: const {
            ExportVideoContainer.mp4: [ExportVideoCodec.h264],
          },
          stillEnabled: (format) => format != ExportStillFormat.jpg,
        ),
      );
      expect(stillOff!.stillFormat, ExportStillFormat.png);

      final movOff = await pick(
        tester,
        'export-format-kind-video',
        button: 'export-format-kind',
        selection: const ExportFormatSelection(
          kind: ExportMediaKind.still,
          container: ExportVideoContainer.mov,
        ),
        caps: capabilities(
          videoEnabled: (container, _) => container != ExportVideoContainer.mov,
        ),
      );
      expect(movOff!.container, ExportVideoContainer.mp4);
    });

    testWidgets('a kind with nothing this build can write stays in the list, '
        'off and saying why — and takes no pick', (tester) async {
      ExportFormatSelection? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportFormatModule(
              selection: const ExportFormatSelection(
                kind: ExportMediaKind.still,
              ),
              capabilities: capabilities(videoEnabled: (_, _) => false),
              enabled: true,
              onChanged: (next) => changed = next,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('export-format-kind')));
      await tester.pumpAndSettle();
      final video = find.byKey(const ValueKey<String>('export-format-kind-video'));
      final row = tester.widget<PopupMenuItem<PanelFlyoutItem>>(video);
      expect(row.enabled, isFalse);
      expect(row.value!.warning, AppText.strings.exNotInThisBuild);

      await tester.tap(video, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(changed, isNull);
    });

    testWidgets('a tab that writes no movie has no 동영상 · 이미지 list — only '
        'the formats', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportFormatModule(
              selection: const ExportFormatSelection(
                kind: ExportMediaKind.still,
              ),
              capabilities: const ExportFormatCapabilities(
                stills: ExportStillFormat.values,
              ),
              enabled: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey<String>('export-format-kind')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('export-format-file')),
          findsOneWidget);
    });
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
    expect(find.text('Auto'), findsOneWidget);
    expect(
      bar.valueTextBuilder!(12, '12 Mb'),
      '12 Mb',
      reason: 'and a real rate keeps the number the bar wrote, unit and all',
    );
    expect(bar.unit, ' Mb');
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
