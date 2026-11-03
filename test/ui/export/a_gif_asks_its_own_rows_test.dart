import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/export_format_pick.dart';

/// 🗣️I-152 (유저 2026-11-03): 「색처리든 뭐든 gif에대한 세부설정가능한거
/// 두고싶어」.
///
/// A GIF's own rows stand in the Format module when a GIF is chosen — the
/// palette, its count, the dither and the loop — as the bitrate stands for
/// an H.26x alone, and whether it keeps a clear colour is the channels row
/// a PNG has.
void main() {
  const capabilities = ExportFormatCapabilities(
    stills: ExportStillFormat.values,
    video: {
      ExportVideoContainer.mp4: [ExportVideoCodec.h264],
      ExportVideoContainer.mov: [ExportVideoCodec.prores4444],
      ExportVideoContainer.gif: [ExportVideoCodec.gif],
    },
  );

  const gif = ExportFormatSelection(
    container: ExportVideoContainer.gif,
    videoCodec: ExportVideoCodec.gif,
  );

  const gifRows = [
    'export-format-gif-palette',
    'export-format-gif-colors',
    'export-format-gif-dither',
    'export-format-gif-loop',
  ];

  Finder keyed(String key) => find.byKey(ValueKey<String>(key));

  /// The module over [selection] — what it hands back lands in [changed].
  Future<List<ExportFormatSelection>> pump(
    WidgetTester tester,
    ExportFormatSelection selection, {
    bool enabled = true,
  }) async {
    final changed = <ExportFormatSelection>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportFormatModule(
            selection: selection,
            capabilities: capabilities,
            enabled: enabled,
            onChanged: changed.add,
          ),
        ),
      ),
    );
    return changed;
  }

  /// Which of [keys] the module shows.
  List<String> shown(List<String> keys) => [
    for (final key in keys)
      if (keyed(key).evaluate().isNotEmpty) key,
  ];

  testWidgets('🚨a GIF\'s rows stand where a GIF is chosen, and nowhere '
      'else — beside the channels row of every format that keeps alpha', (
    tester,
  ) async {
    const channels = 'export-format-channels-rgba';
    await pump(tester, gif);
    expect(shown([...gifRows, channels]), [...gifRows, channels]);

    await pump(tester, const ExportFormatSelection());
    expect(shown([...gifRows, channels]), isEmpty, reason: 'an MP4');

    await pump(
      tester,
      const ExportFormatSelection(
        container: ExportVideoContainer.mov,
        videoCodec: ExportVideoCodec.prores4444,
      ),
    );
    expect(
      shown([...gifRows, channels]),
      [channels],
      reason: 'ProRes 4444 keeps alpha, as a GIF does',
    );

    await pump(
      tester,
      const ExportFormatSelection(kind: ExportMediaKind.still),
    );
    expect(shown([...gifRows, channels]), [channels], reason: 'a PNG');
  });

  testWidgets('black and white is two whatever is asked, so it asks no '
      'count', (tester) async {
    await pump(
      tester,
      gif.copyWith(
        gif: const ExportGifSettings(reduction: ExportGifReduction.blackWhite),
      ),
    );
    expect(shown(gifRows), [
      'export-format-gif-palette',
      'export-format-gif-dither',
      'export-format-gif-loop',
    ]);
  });

  testWidgets('each row hands back the GIF it asks for, and the rest of the '
      'choice as it was', (tester) async {
    final rgb = gif.copyWith(channels: ExportChannels.rgb);
    var changed = await pump(tester, rgb);
    await pickFromExportList(
      tester,
      'export-format-gif-palette',
      'export-format-gif-palette-neural',
    );
    expect(
      changed.single,
      rgb.copyWith(
        gif: const ExportGifSettings(reduction: ExportGifReduction.neural),
      ),
    );

    changed = await pump(tester, rgb);
    await pickFromExportList(
      tester,
      'export-format-gif-dither',
      'export-format-gif-dither-atkinson',
    );
    expect(
      changed.single.gif,
      const ExportGifSettings(dither: ExportGifDither.atkinson),
    );

    changed = await pump(tester, rgb);
    FieldSlider bar(String key) => tester.widget<FieldSlider>(keyed(key));
    bar('export-format-gif-colors').onChanged!(16.4);
    bar('export-format-gif-loop').onChanged!(3);
    expect([for (final each in changed) each.gif], [
      const ExportGifSettings(colors: 16),
      const ExportGifSettings(plays: 3),
    ]);
  });

  testWidgets('the rows say what they hold: a kernel by the names of who '
      'made it, none in words, the loop\'s zero as FOREVER', (tester) async {
    await pump(
      tester,
      gif.copyWith(
        gif: const ExportGifSettings(
          reduction: ExportGifReduction.blackWhite,
          dither: ExportGifDither.none,
        ),
      ),
    );
    expect(find.text('Black & white'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    final loop = tester.widget<FieldSlider>(keyed('export-format-gif-loop'));
    expect(loop.valueTextBuilder!(0, '0'), 'Forever');
    expect(loop.valueTextBuilder!(3, '3'), '3×');
    expect((loop.min, loop.max), (0, exportGifMostPlays));
    expect(find.text('Forever'), findsOneWidget);

    await pump(
      tester,
      gif.copyWith(
        gif: const ExportGifSettings(dither: ExportGifDither.floydSteinberg),
      ),
    );
    expect(find.text('Octree'), findsOneWidget);
    expect(find.text('Floyd–Steinberg'), findsOneWidget);
    final colors = tester.widget<FieldSlider>(
      keyed('export-format-gif-colors'),
    );
    expect((colors.min, colors.max), (2, 256));
  });

  testWidgets('⛔a DISABLED module hands a GIF\'s bars no onChanged', (
    tester,
  ) async {
    await pump(tester, gif, enabled: false);
    for (final key in [
      'export-format-gif-colors',
      'export-format-gif-loop',
    ]) {
      expect(tester.widget<FieldSlider>(keyed(key)).onChanged, isNull);
    }
  });
}
