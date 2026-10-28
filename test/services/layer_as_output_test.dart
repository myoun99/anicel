import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart' show ExportLayerFx;
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/layer_as_output.dart';

/// What an output keeps of a row, by the export window's 레이어 FX.
///
/// 🗣️I-65-Q3 (유저 2026-10-25): 「켬이랑 끔은 지금처럼 전부 켜고 끄는거고,
/// 기본만 켬은 지금까지 말햇던 셀번호나 참조fx같은것만 키고 트랜스폼 포함해서
/// 나머지 끄는것」 · Q6 「참조 fx 도 끈다(정말 날 것)」 · Q12 「레이어 행의 fx
/// 머리도 같은 법 — 셀 번호도」(↩️Q5 「출력은 머리를 안 본다」).
void main() {
  LayerEffect link(String id, EffectKind kind, {bool enabled = true}) =>
      LayerEffect(id: EffectId(id), kind: kind, enabled: enabled);

  final laid = TransformPose(center: CanvasPoint(x: 10, y: 10));
  final moved = TransformPose(center: CanvasPoint(x: 40, y: 10));
  final reference = MediaReference(
    assetPath: 'paper.png',
    pose: moved,
    laid: laid,
    pictureSize: const CanvasSize(width: 64, height: 64),
    fx: TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>()
          .withKey(0, CanvasPoint(x: 40, y: 10))
          .withKey(8, CanvasPoint(x: 80, y: 10)),
    ),
  );

  /// A row whose every head is off — its transform's and each link's —
  /// standing a file.
  final row = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: const [],
    transformEnabled: false,
    effects: [
      link('number', EffectKind.celNumber, enabled: false),
      link('blur', EffectKind.blur, enabled: false),
    ],
    mediaReference: reference,
  );

  Map<String, bool> linksOf(Layer layer) => {
    for (final effect in layer.effects) effect.id.value: effect.enabled,
  };

  test('켬 keeps every fx the screen shows', () {
    final output = layerAsOutput(
      row.copyWith(
        transformEnabled: true,
        effects: [
          link('number', EffectKind.celNumber),
          link('blur', EffectKind.blur),
        ],
      ),
      ExportLayerFx.on,
    );
    expect(output.transformEnabled, isTrue);
    expect(linksOf(output), {'number': true, 'blur': true});
    expect(output.mediaReference, reference);
  });

  // 🗣️I-65-Q12 (유저 2026-10-27): 「레이어 행의 fx 머리도 같은 법 — 셀
  // 번호도」. ↩️Q5 kept every fx whatever its own head said.
  test('🚨a head switched off on the timeline is off in the output — the '
      'transform\'s and each link\'s, the cel number\'s too', () {
    for (final fx in ExportLayerFx.values) {
      final output = layerAsOutput(row, fx);
      expect(output.transformEnabled, isFalse, reason: '$fx');
      expect(
        linksOf(output),
        {'number': false, 'blur': false},
        reason: '$fx',
      );
    }
  });

  test('기본만 켬 keeps the cel number and the reference fx — the transform '
      'and every other link off', () {
    final output = layerAsOutput(
      row.copyWith(
        transformEnabled: true,
        effects: [
          link('number', EffectKind.celNumber),
          link('blur', EffectKind.blur),
        ],
      ),
      ExportLayerFx.basic,
    );
    expect(output.transformEnabled, isFalse);
    expect(linksOf(output), {'number': true, 'blur': false});
    expect(output.mediaReference, reference);
  });

  test('끔 keeps none — the file\'s picture stands where its pixels are '
      'laid', () {
    final output = layerAsOutput(
      row.copyWith(
        transformEnabled: true,
        effects: [
          link('number', EffectKind.celNumber),
          link('blur', EffectKind.blur),
        ],
      ),
      ExportLayerFx.off,
    );
    expect(output.transformEnabled, isFalse);
    expect(linksOf(output), {'number': false, 'blur': false});
    final raw = output.mediaReference!;
    expect(raw.assetPath, reference.assetPath);
    for (final frame in [0, 4, 8]) {
      expect(raw.poseAt(frame), laid, reason: 'frame $frame');
    }
    expect(raw.laid, laid);
  });

  // 🗣️I-65-Q11 (유저 2026-10-25): 「켬 · 기본만 켬이면 화면 스위치대로, 끔이면
  // 빠짐 — 카메라 행도 같이」. ↩️Q8 sent the work out whatever both said.
  test('🚨the camera row\'s work goes out as its switch shows it under 켬 '
      'and 기본만 켬 — and not under 끔', () {
    final camera = createCameraLayer(cutId: const CutId('cut'));
    for (final shown in [true, false]) {
      final row = camera.copyWith(transformEnabled: shown);
      for (final fx in ExportLayerFx.values) {
        expect(
          layerAsOutput(row, fx).transformEnabled,
          shown && fx != ExportLayerFx.off,
          reason: '$fx, switched ${shown ? 'on' : 'off'}',
        );
      }
    }
  });
}
