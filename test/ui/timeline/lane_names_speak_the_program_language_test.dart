import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/se_sound.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_sound_lane_policy.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/named_finders.dart';

/// F-37 — a lane's name is read in the program language.
///
/// 유저 2026-09-15 (F-37-Q1): 「전부 번역 — 레인 이름도 한국어로」, and 「ae도
/// 애초에 언어설정따라서 트랜스폼이나 싹 다 번역되있잖아. 그러니 법 하나로 다
/// 번역」. The rail said Transform, Name Tag and Audio — and every member,
/// effect and parameter under them — in English whatever the language, while
/// `tlTransformGroup` and `tlNameTagGroup` sat tabled and read by nobody.
///
/// ⚠️The words are written out rather than read back through AppStrings, so
/// this asks what the RAIL shows, not whether a table agrees with itself.
void main() {
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  void speak(AppLanguage language) =>
      AppText.settings.value = AppLanguageSettings(programLanguage: language);

  List<String> labelsOf(List<PropertyLaneRow> rows) => [
    for (final row in rows) row.label,
  ];

  final effects = [
    LayerEffect.defaults(id: const EffectId('blur'), kind: EffectKind.blur),
    LayerEffect.defaults(
      id: const EffectId('key'),
      kind: EffectKind.colorKey,
    ),
  ];

  for (final MapEntry(key: language, value: words) in _rail.entries) {
    group('in ${language.name}', () {
      setUp(() => speak(language));

      test('the Transform group and its members', () {
        expect(
          labelsOf(
            transformPropertyLanes(
              TransformTrack.empty(),
              scaleForm: const TwoScales(),
              includeAnchorAndOpacity: true,
            ),
          ),
          words.transform,
        );
        expect(
          transformGroupHeader(expanded: true).label,
          words.transform.first,
          reason: 'the header the union summary builds reads the same word',
        );
      });

      test('the Name Tag group and its members', () {
        expect(
          labelsOf(
            seNameTagPropertyLanes(
              const SeNameTag(),
              expanded: true,
              resolveAt: (_) => const SeNameTag(),
            ),
          ),
          words.nameTag,
        );
      });

      test('the 「오디오」 group and its members', () {
        expect(
          labelsOf(
            seSoundPropertyLanes(
              const SeSound(),
              expanded: true,
              volumeAt: null,
            ),
          ),
          words.audio,
        );
      });

      test('each effect and its parameters', () {
        expect(
          labelsOf(effectPropertyLanes(effects, isExpanded: (_) => true)),
          words.effects,
        );
      });
    });
  }

  testWidgets('the fx switch on a group header names the group in the '
      'program language', (tester) async {
    speak(AppLanguage.ko);
    // The WHOLE app, as `rail_column_parity_test` does: lane expansion is
    // HomePage's state, so a bare TimelineTabHost has no twirl to tap.
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final layerId = session.activeLayerId!;
    final laneToggle = find.named('timeline-lane-toggle-$layerId');
    await tester.ensureVisible(laneToggle);
    await tester.pumpAndSettle();
    await tester.tap(laneToggle);
    await tester.pumpAndSettle();

    expect(
      find.named('timeline-lane-group-fx-$layerId-transform-group'),
      findsOneWidget,
      reason: 'fixture premise: the Transform header is on screen',
    );
    expect(find.tooltipSaying('변형 우회'), findsOneWidget);
    expect(find.tooltipSaying('Bypass Transform'), findsNothing);
  });

  test('🗣️I-132-Q7: an effect\'s lanes say the words its name says — '
      'AE\'s', () {
    // 유저 2026-10-27: 「효과 이름의 말을 따른다」 — 輝度＆コントラスト's lanes
    // are 輝度 and コントラスト, 명도 및 대비's 명도 and 대비.
    List<String> lanesIn(AppLanguage language) {
      speak(language);
      return labelsOf(
        effectPropertyLanes([
          LayerEffect.defaults(
            id: const EffectId('bc'),
            kind: EffectKind.brightnessContrast,
          ),
        ], isExpanded: (_) => true),
      );
    }

    expect(lanesIn(AppLanguage.ja), ['輝度＆コントラスト', '輝度', 'コントラスト']);
    expect(lanesIn(AppLanguage.ko), ['명도 및 대비', '명도', '대비']);
  });
}

/// What the rail shows, per language.
class _RailWords {
  const _RailWords({
    required this.transform,
    required this.nameTag,
    required this.audio,
    required this.effects,
  });

  /// The Transform header and its five members, top to bottom.
  final List<String> transform;

  /// The Name Tag header and its ten members, top to bottom.
  final List<String> nameTag;

  /// The 「오디오」 header and its two members, top to bottom (I-140).
  final List<String> audio;

  /// A Gaussian Blur and a Color Key, each header followed by its
  /// parameters.
  final List<String> effects;
}

const _rail = <AppLanguage, _RailWords>{
  AppLanguage.en: _RailWords(
    transform: [
      'Transform',
      'Anchor Point',
      'Position',
      'Scale',
      'Rotation',
      'Opacity',
    ],
    nameTag: [
      'Name Tag',
      'Size',
      'Tracking',
      'Bold',
      'Italic',
      'Underline',
      'Strikethrough',
      'Name Ink',
      'Box Colour',
      'Dialogue Ink',
      'Show Dialogue',
    ],
    audio: ['Audio', 'Volume', 'Total volume', 'Pan'],
    effects: [
      'Gaussian Blur',
      'Blurriness',
      'Blur Dimensions',
      'Repeat Edge Pixels',
      'Color Key',
      'Key Operation',
      'Key Color',
      'Tolerance',
      'Amount',
    ],
  ),
  AppLanguage.ja: _RailWords(
    transform: ['トランスフォーム', 'アンカーポイント', '位置', 'スケール', '回転', '不透明度'],
    nameTag: [
      'ネームタグ',
      'サイズ',
      '字間',
      '太字',
      '斜体',
      '下線',
      '取り消し線',
      '名前の色',
      'ボックスの色',
      'セリフの色',
      'セリフを表示',
    ],
    audio: ['音声', '音量', '全体の音量', 'パン'],
    effects: [
      'ブラー（ガウス）',
      'ブラー',
      'ブラーの方向',
      'エッジピクセルを繰り返す',
      'カラーキー',
      'キー操作',
      'キー色',
      '許容値',
      '適用量',
    ],
  ),
  AppLanguage.ko: _RailWords(
    transform: ['변형', '기준점', '위치', '비율', '회전', '불투명도'],
    nameTag: [
      '이름표',
      '크기',
      '자간',
      '굵게',
      '기울임',
      '밑줄',
      '취소선',
      '이름 잉크',
      '박스 색',
      '대사 잉크',
      '대사 표시',
    ],
    audio: ['오디오', '볼륨', '총 볼륨', '팬'],
    effects: [
      '가우시안 흐림',
      '흐림 정도',
      '흐림 방향',
      '가장자리 픽셀 반복',
      '색상 키',
      '키 작업',
      '키 색',
      // I-8-Q2 — the user's word for this knob.
      '허용차',
      '적용량',
    ],
  ),
  AppLanguage.fr: _RailWords(
    transform: [
      'Transformation',
      "Point d'ancrage",
      'Position',
      'Échelle',
      'Rotation',
      'Opacité',
    ],
    nameTag: [
      'Étiquette',
      'Taille',
      'Interlettrage',
      'Gras',
      'Italique',
      'Souligné',
      'Barré',
      'Encre du nom',
      'Couleur de la boîte',
      'Encre du dialogue',
      'Afficher le dialogue',
    ],
    audio: ['Audio', 'Volume', 'Volume global', 'Panoramique'],
    effects: [
      'Flou gaussien',
      'Flou',
      'Dimensions du flou',
      'Répéter les pixels du contour',
      'Masquage par couleur',
      'Opération',
      'Couleur de la clé',
      'Tolérance',
      'Quantité',
    ],
  ),
  AppLanguage.zhHans: _RailWords(
    transform: ['变换', '锚点', '位置', '缩放', '旋转', '不透明度'],
    nameTag: [
      '名字条',
      '大小',
      '字距',
      '加粗',
      '倾斜',
      '下划线',
      '删除线',
      '名字颜色',
      '底框颜色',
      '台词颜色',
      '显示台词',
    ],
    audio: ['音频', '音量', '总音量', '声像'],
    effects: [
      '高斯模糊',
      '模糊度',
      '模糊方向',
      '重复边缘像素',
      '颜色键',
      '主要操作',
      '键色',
      '容差',
      '数量',
    ],
  ),
};
