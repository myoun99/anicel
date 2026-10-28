import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/export_spec.dart';

/// The cel tab used to force FX off with no way to say otherwise — a rule
/// written in R6a (#794) whose stated reason was blur in delivery line art.
/// 유저 2026-08-27: 「셀 출력 강제도 래스터라이즈시키고 출력하면 되는거니까
/// 멋대로 판단하지말고」.
///
/// 🗣️I-65-Q3 (유저 2026-10-25): 「출력창 fx 타입 세개 만들자. 켬, 기본만 켬,
/// 끔」 — the switch became a choice of three, the same on every tab.
void main() {
  test('the cel tab carries the same choice the other tabs do, default ON', () {
    expect(const CelsExportSpec().layerFx, ExportLayerFx.on);
    expect(const SequenceExportSpec().layerFx, ExportLayerFx.on);
    expect(const ImageExportSpec().layerFx, ExportLayerFx.on);
  });

  test('every choice round-trips through the preset JSON', () {
    for (final fx in ExportLayerFx.values) {
      final json = CelsExportSpec(layerFx: fx).toJson();
      expect(CelsExportSpec.fromJson(json).layerFx, fx, reason: '$fx');
    }
    // The default says nothing, the way every other default here does.
    expect(const CelsExportSpec().toJson().containsKey('layerFx'), isFalse);
  });

  test('the choice is part of the spec identity, so a preset notices it', () {
    for (final fx in [ExportLayerFx.basic, ExportLayerFx.off]) {
      expect(const CelsExportSpec(), isNot(CelsExportSpec(layerFx: fx)));
      expect(
        const CelsExportSpec().hashCode,
        isNot(CelsExportSpec(layerFx: fx).hashCode),
      );
    }
  });
}
