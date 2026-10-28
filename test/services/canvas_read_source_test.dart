import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/canvas_read_source.dart';

/// I-36 (유저 2026-09-24): 「참조(보이는거 전부) … 현재레이어」 — the one
/// answer the fill, the eyedropper and the fill settings' readout all read.
/// ↩️The middle mode, the flagged layers, went with I-92.
void main() {
  Layer row(String id) => Layer(id: LayerId(id), name: id, frames: const []);

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('c'),
    name: 'c',
    layers: layers,
    duration: 1,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  const paint = LayerId('paint');

  test('both tools offer the same two answers', () {
    expect(CanvasReadSource.values, [
      CanvasReadSource.display,
      CanvasReadSource.layer,
    ]);
  });

  test('「보이는거 전부」 reads every visible layer', () {
    expect(layersReadBy(CanvasReadSource.display, paint), isNull);
    expect(layersReadBy(CanvasReadSource.display, null), isNull);
  });

  test('「현재레이어」 reads the active layer alone', () {
    expect(layersReadBy(CanvasReadSource.layer, paint), {paint});
    expect(
      layersReadBy(CanvasReadSource.layer, null),
      isEmpty,
      reason: 'no active layer, nothing to read',
    );
  });

  test('the readout names what the tool reads', () {
    final cut = cutOf([row('ink'), row('paint'), row('ink2')]);
    expect(layerNamesReadBy(CanvasReadSource.display, cut, paint), isNull);
    expect(layerNamesReadBy(CanvasReadSource.layer, cut, paint), ['paint']);
    expect(
      layerNamesReadBy(CanvasReadSource.layer, null, paint),
      isEmpty,
      reason: 'no cut, nothing read',
    );
  });
}
