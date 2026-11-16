import 'dart:typed_data';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/tvp_import_planner.dart';
import 'package:anicel/src/ui/session/tvpp_import_door.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/import/tvpp_test_builder.dart';

/// A stop is honoured after the cel in hand (card F-608 ③): once a cel has
/// landed and [TvppImportDoor.decodeEach] hears the stop, no record more is
/// read — the turns still waiting go without one, so a stop costs the cels
/// on their way and no more. What still comes back is given back unlaid.
void main() {
  const width = 64;
  const height = 48;

  test('🚨once a landed cel hears the stop, no record more is read', () async {
    final builder = TvppBuilder()
      ..clipProperties('t')
      ..clipHeader(width: width, height: height)
      ..layerHead('L', end: 3, count: 4);
    for (var cel = 0; cel < 4; cel += 1) {
      final px = List<int>.filled(width * height, 0);
      px[cel * 3] = premulBgra(200, 30, 40, 255);
      builder.zchkSlot(srawRecord(px, width, height));
    }
    builder.clipConfig();
    final file = builder.bytes;
    final slots = parseTvppStructure(file).clips.single.layers.single.slots;
    expect(slots, hasLength(4), reason: 'the fixture holds four drawings');
    final cut = Cut(
      id: const CutId('c'),
      name: 'c',
      layers: const [],
      duration: 4,
      canvasSize: const CanvasSize(width: width, height: height),
    );
    final plan = TvpImportPlan(cut: cut, bakes: const [], warnings: const []);
    const bake = PlannedCelBake(
      cutId: CutId('c'),
      layerId: LayerId('l'),
      frameId: FrameId('f'),
      sourceFile: 's',
    );

    var read = 0;
    var landed = 0;
    await TvppImportDoor.decodeEach(
      [for (final slot in slots) (plan, cut, bake, slot)],
      atOnce: 1,
      windowOf: (slot) async {
        read += 1;
        return Uint8List.sublistView(
          file,
          slot.chunkOffset,
          slot.chunkOffset + slot.chunkLength,
        );
      },
      landed: (index, lay, decoded) async => landed += 1,
      stopped: () => landed > 0,
    );

    expect(landed, 1, reason: 'the cel in hand, then the stop');
    expect(read, 1, reason: 'no record read past it');
  });
}
