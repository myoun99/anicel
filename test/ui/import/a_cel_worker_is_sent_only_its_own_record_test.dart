import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/tvp_import_planner.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart'
    show AnicelLaidCel, laidCelSurface;
import 'package:anicel/src/ui/session/tvpp_import_door.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/surface_rgba_in_place.dart';
import '../../models/import/tvpp_test_builder.dart';
import '../../services/import/tvpp_slot_rgba.dart';

/// A cel's worker is sent that cel's record and nothing else of the work it
/// is part of.
///
/// `Isolate.run` copies the closure's whole context chain, not only the
/// names the closure reads — so a worker built where the wave is in scope
/// ships the wave: every other worker's record, and every plan and cut the
/// wave holds (tvpp-import-isolate-copies-wave, 2026-09-16).
///
/// 🧪A port is the one thing an isolate message refuses outright, so here
/// everything a worker must NOT receive holds one: the work, the windows,
/// the plan, the cut, the bake. Nothing reads those ports. A message that
/// reaches any of them fails to send, and that failure is the measurement —
/// counting bytes would only be a shadow of the graph this reads directly.
void main() {
  const width = 64;
  const height = 48;

  test('each worker decodes its own record from a message that reaches '
      'nothing else of the work', () async {
    // Two drawings with ink in different places, so a worker handed the
    // other one's record decodes a different picture.
    final builder = TvppBuilder()
      ..clipProperties('t')
      ..clipHeader(width: width, height: height)
      ..layerHead('L', end: 1, count: 2);
    for (final left in const [4, 36]) {
      final px = List<int>.filled(width * height, 0);
      for (var y = 8; y < 20; y++) {
        for (var x = left; x < left + 16; x++) {
          px[y * width + x] = premulBgra(200, 30, 40, 255);
        }
      }
      builder.zchkSlot(srawRecord(px, width, height));
    }
    builder.clipConfig();
    final file = builder.bytes;
    final slots = parseTvppStructure(file).clips.single.layers.single.slots;
    expect(slots, hasLength(2), reason: 'the fixture holds two drawings');

    final port = ReceivePort();
    addTearDown(port.close);
    final cut = _CutHoldingAPort(
      port,
      canvasSize: const CanvasSize(width: width, height: height),
    );
    final plan = _PlanHoldingAPort(port, cut: cut);
    final work =
        _ListHoldingAPort<(TvpImportPlan, Cut, PlannedCelBake, TvppSlot)>(
          port,
          [for (final slot in slots) (plan, cut, _BakeHoldingAPort(port), slot)],
        );
    // Fresh buffers, as the reader hands them over — a VIEW would carry
    // the whole file's buffer with it.
    final windows = _ListHoldingAPort<Uint8List>(port, [
      for (final slot in slots)
        Uint8List.fromList(
          Uint8List.sublistView(
            file,
            slot.chunkOffset,
            slot.chunkOffset + slot.chunkLength,
          ),
        ),
    ]);

    final decoded = <int, Object>{};
    await TvppImportDoor.decodeEach(
      work,
      atOnce: slots.length,
      windowOf: (slot) async => windows[slots.indexOf(slot)],
      landed: (index, lay, cel) async => decoded[index] = cel,
      stopped: () => false,
    );

    expect(decoded.keys, unorderedEquals([0, 1]));
    for (var i = 0; i < slots.length; i++) {
      final expected = tvppSlotRgba(
        recordBytes: file,
        slot: slots[i],
        width: width,
        height: height,
      )!;
      expect(decoded[i], isA<AnicelLaidCel>(), reason: 'cel $i decodes');
      final cel = laidCelSurface(decoded[i]! as AnicelLaidCel);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final at = (y * width + x) * 4;
          expect(
            surfaceRgbaInPlace(cel, x, y),
            (expected[at] << 24) |
                (expected[at + 1] << 16) |
                (expected[at + 2] << 8) |
                expected[at + 3],
            reason: 'cel $i pixel ($x, $y) is its own record\'s',
          );
        }
      }
    }
  });
}

class _ListHoldingAPort<E> extends ListBase<E> {
  _ListHoldingAPort(this.port, this._items);

  final ReceivePort port;
  final List<E> _items;

  @override
  int get length => _items.length;

  @override
  set length(int value) => _items.length = value;

  @override
  E operator [](int index) => _items[index];

  @override
  void operator []=(int index, E value) => _items[index] = value;
}

class _PlanHoldingAPort extends TvpImportPlan {
  _PlanHoldingAPort(this.port, {required super.cut})
    : super(bakes: const [], warnings: const []);

  final ReceivePort port;
}

class _CutHoldingAPort extends Cut {
  _CutHoldingAPort(this.port, {required super.canvasSize})
    : super(id: const CutId('c'), name: 'c', layers: const [], duration: 2);

  final ReceivePort port;
}

class _BakeHoldingAPort extends PlannedCelBake {
  _BakeHoldingAPort(this.port)
    : super(
        cutId: const CutId('c'),
        layerId: const LayerId('l'),
        frameId: const FrameId('f'),
        sourceFile: 's',
      );

  final ReceivePort port;
}
