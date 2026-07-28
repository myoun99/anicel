import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/color_palette_file_service.dart';

void main() {
  test('recent colors dedupe to the front and cap at the limit', () {
    var state = const ColorPaletteState();
    for (var i = 0; i < 14; i += 1) {
      state = state.withRecentColor(0xFF000000 + i);
    }
    expect(state.recent, hasLength(ColorPaletteState.maxRecent));
    expect(state.recent.first, 0xFF000000 + 13);

    // Re-using an old color promotes it without duplicating.
    state = state.withRecentColor(0xFF000000 + 10);
    expect(state.recent.first, 0xFF000000 + 10);
    expect(state.recent.where((c) => c == 0xFF000000 + 10), hasLength(1));

    // The current front is a no-op (wheel drags won't churn the row).
    final same = state.withRecentColor(state.recent.first);
    expect(identical(same, state), isTrue);
  });

  test('palette persists through the file service; corrupt files yield '
      'defaults', () async {
    final directory = await Directory.systemTemp.createTemp('palette-test');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/palette.json';

    final service = ColorPaletteFileService(filePath: path);
    await service.save(
      const ColorPaletteState(pinned: [0xFF112233], recent: [0xFFAABBCC]),
    );
    final restored = await ColorPaletteFileService(
      filePath: path,
    ).loadOrDefaults();
    expect(restored.pinned, [0xFF112233]);
    expect(restored.recent, [0xFFAABBCC]);

    File(path).writeAsStringSync('not json');
    final fallback = await ColorPaletteFileService(
      filePath: path,
    ).loadOrDefaults();
    expect(fallback.pinned, ColorPaletteState.defaultPinned);
  });
}
