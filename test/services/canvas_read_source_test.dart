import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/canvas_read_source.dart';

/// I-36 (유저 2026-09-24): 「모드 세개. 참조(보이는거 전부), 참조(참조 설정한
/// 레이어만, 없으면 현재), 현재레이어」 — the one answer the fill, the
/// eyedropper and the fill settings' readout all read.
void main() {
  Layer row(String id, {bool reference = false}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    isFillReference: reference,
  );

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('c'),
    name: 'c',
    layers: layers,
    duration: 1,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  const ink = LayerId('ink');
  const paint = LayerId('paint');

  test('「보이는거 전부」 reads every visible layer, flag or no flag', () {
    for (final flagged in [false, true]) {
      expect(
        layersReadBy(
          CanvasReadSource.display,
          cutOf([row('ink', reference: flagged), row('paint')]),
          paint,
        ),
        isNull,
      );
    }
  });

  test('「현재레이어」 reads the active layer alone, flags or not', () {
    final cut = cutOf([row('ink', reference: true), row('paint')]);
    expect(layersReadBy(CanvasReadSource.layer, cut, paint), {paint});
    expect(
      layersReadBy(CanvasReadSource.layer, cut, null),
      isEmpty,
      reason: 'no active layer, nothing to read',
    );
  });

  test('「참조 설정한 레이어만」 reads the flagged layers, whichever is '
      'active', () {
    final cut = cutOf([
      row('ink', reference: true),
      row('ink2', reference: true),
      row('paint'),
    ]);
    expect(layersReadBy(CanvasReadSource.references, cut, paint), {
      ink,
      const LayerId('ink2'),
    });
  });

  test('「없으면 현재」 — no layer flagged, the active layer is read', () {
    final cut = cutOf([row('ink'), row('paint')]);
    expect(layersReadBy(CanvasReadSource.references, cut, paint), {paint});
    expect(layersReadBy(CanvasReadSource.references, cut, ink), {ink});
  });

  test('the readout names what the tool reads, in the stack\'s order', () {
    final cut = cutOf([
      row('ink', reference: true),
      row('paint'),
      row('ink2', reference: true),
    ]);
    expect(layerNamesReadBy(CanvasReadSource.display, cut, paint), isNull);
    expect(layerNamesReadBy(CanvasReadSource.references, cut, paint), [
      'ink',
      'ink2',
    ]);
    expect(layerNamesReadBy(CanvasReadSource.layer, cut, paint), ['paint']);
    expect(
      layerNamesReadBy(CanvasReadSource.layer, null, paint),
      isEmpty,
      reason: 'no cut, nothing read',
    );
  });
}
