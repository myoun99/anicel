import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/export_spec.dart';

/// The cel tab used to force FX off with no way to say otherwise — a rule
/// written in R6a (#794) whose stated reason was blur in delivery line art.
/// 유저 2026-08-27: 「셀 출력 강제도 래스터라이즈시키고 출력하면 되는거니까
/// 멋대로 판단하지말고」.
void main() {
  test('the cel tab carries the same switch the other tabs do, default ON', () {
    const spec = CelsExportSpec();
    expect(spec.applyLayerFx, isTrue);
    expect(const SequenceExportSpec().applyLayerFx, isTrue);
    expect(const ImageExportSpec().applyLayerFx, isTrue);
  });

  test('turning it off round-trips through the preset JSON', () {
    const off = CelsExportSpec(applyLayerFx: false);
    final json = off.toJson();
    expect(json['applyLayerFx'], isFalse);
    expect(CelsExportSpec.fromJson(json).applyLayerFx, isFalse);
    // The default says nothing, the way every other default here does.
    expect(const CelsExportSpec().toJson().containsKey('applyLayerFx'), isFalse);
  });

  test('the switch is part of the spec identity, so a preset notices it', () {
    expect(
      const CelsExportSpec(),
      isNot(const CelsExportSpec(applyLayerFx: false)),
    );
    expect(
      const CelsExportSpec().hashCode,
      isNot(const CelsExportSpec(applyLayerFx: false).hashCode),
    );
  });
}
