import 'dart:convert';
import 'dart:typed_data';

import '../../services/color_palette_file_service.dart';
import '../text/app_strings.dart';

/// The palette file [name], holding [bytes], brought into [palettes]
/// (I-142): the palettes after — none where the file holds none — and what
/// to say of it: a line for each palette it brought.
({ColorPaletteState? palettes, String said}) importPaletteFile(
  ColorPaletteState palettes,
  String name,
  Uint8List bytes,
) {
  final brought = palettesInSettingsFile(
    utf8.decode(bytes, allowMalformed: true),
  );
  if (brought == null) {
    return (palettes: null, said: AppText.strings.imUnreadable(name));
  }
  return (
    palettes: palettes.withBrought(brought),
    said: [
      for (final palette in brought)
        AppText.strings.paletteBrought(palette.name),
    ].join('\n'),
  );
}
