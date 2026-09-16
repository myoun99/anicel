import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_audio_lane.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

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

  final seLayer = Layer(
    id: const LayerId('se'),
    name: 'S1',
    kind: LayerKind.se,
    frames: [Frame(id: const FrameId('se-f'), duration: 1, strokes: const [])],
    timeline: const {2: TimelineExposure.drawing(FrameId('se-f'), length: 8)},
    audioClips: [
      const AudioClip(filePath: 'steps.wav', frameId: FrameId('se-f')),
    ],
  );
  final effects = [
    LayerEffect.defaults(id: const EffectId('blur'), kind: EffectKind.blur),
    LayerEffect.defaults(
      id: const EffectId('key'),
      kind: EffectKind.deleteColor,
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

      test('the Audio lane', () {
        expect(labelsOf(seAudioLanesFor(seLayer)), [words.audio]);
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
    final laneToggle = find.byKey(
      ValueKey<String>('timeline-lane-toggle-$layerId'),
    );
    await tester.ensureVisible(laneToggle);
    await tester.pumpAndSettle();
    await tester.tap(laneToggle);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ValueKey<String>('timeline-lane-group-fx-$layerId-transform-group'),
      ),
      findsOneWidget,
      reason: 'fixture premise: the Transform header is on screen',
    );
    expect(find.byTooltip('변형 우회'), findsOneWidget);
    expect(find.byTooltip('Bypass Transform'), findsNothing);
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

  /// The Name Tag header and its seven members, top to bottom.
  final List<String> nameTag;

  final String audio;

  /// A Blur and a Delete Color, each header followed by its parameters.
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
      'Name Ink',
      'Box Colour',
      'Dialogue Ink',
      'Show Dialogue',
    ],
    audio: 'Audio',
    effects: [
      'Blur',
      'Blur Width',
      'Blur Height',
      'Delete Color',
      'Key Red',
      'Key Green',
      'Key Blue',
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
      '名前の色',
      'ボックスの色',
      'セリフの色',
      'セリフを表示',
    ],
    audio: '音声',
    effects: [
      'ぼかし',
      'ぼかしの幅',
      'ぼかしの高さ',
      '色削除',
      'キー色の赤',
      'キー色の緑',
      'キー色の青',
      '許容値',
      '適用量',
    ],
  ),
  AppLanguage.ko: _RailWords(
    transform: ['변형', '기준점', '위치', '비율', '회전', '불투명도'],
    nameTag: ['이름표', '크기', '자간', '굵게', '이름 잉크', '박스 색', '대사 잉크', '대사 표시'],
    audio: '오디오',
    effects: [
      '흐림 효과',
      '흐림 너비',
      '흐림 높이',
      '색 삭제',
      '키 색 빨강',
      '키 색 초록',
      '키 색 파랑',
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
      'Encre du nom',
      'Couleur de la boîte',
      'Encre du dialogue',
      'Afficher le dialogue',
    ],
    audio: 'Audio',
    effects: [
      'Flou',
      'Largeur du flou',
      'Hauteur du flou',
      'Supprimer la couleur',
      'Rouge de la clé',
      'Vert de la clé',
      'Bleu de la clé',
      'Tolérance',
      'Quantité',
    ],
  ),
  AppLanguage.zhHans: _RailWords(
    transform: ['变换', '锚点', '位置', '缩放', '旋转', '不透明度'],
    nameTag: ['名字条', '大小', '字距', '加粗', '名字颜色', '底框颜色', '台词颜色', '显示台词'],
    audio: '音频',
    effects: ['模糊', '模糊宽度', '模糊高度', '删除颜色', '键色红', '键色绿', '键色蓝', '容差', '数量'],
  ),
};
