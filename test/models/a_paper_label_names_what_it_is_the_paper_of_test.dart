// 🗣️F-578 ⑦ (유저 2026-11-10): 「용지색라벨에도 공정 다 넣고싶거든?
// 용지-레이아웃, 용지-러프원, 용지-작감 이런식으로 … 용지는 용지-소재가 아니라
// 용지-LO 이런식으로」 · 「용지라벨은 권한대로. 모든 공정을 넣음. 앞으로
// 발생하는것도.」 — a 用紙 label is the paper OF a stage or a correction, in
// the one slot a drawing's correction rides; there is no 用紙 소재.
// ↩️유저 08-27: 「용지는 수정공정 존재 안하도록」.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkChipText;

void main() {
  const paperLo = LayerMark.paper(LayerProcess.layout);
  const paperAd = LayerMark.paper(LayerRevise.animationDirector);

  test('a paper of a stage and a paper of a correction each come back as '
      'they were written — the stage under paperOf, the correction under '
      'revise', () {
    expect(paperLo.toJson(), {'process': 'paper', 'paperOf': 'layout'});
    expect(paperAd.toJson(), {
      'process': 'paper',
      'revise': 'animation-director',
    });
    for (final mark in labelsOf(LayerProcess.paper)) {
      expect(LayerMark.fromJson(mark.toJson()), mark, reason: '$mark');
      expect(
        LayerMark.fromJson(mark.withTake(3).toJson()),
        mark.withTake(3),
        reason: '$mark at take 3',
      );
    }
  });

  test('a paper that names nothing it is the paper of is no label — and a '
      'stage\'s word on a drawing\'s label is not read as one', () {
    expect(LayerMark.fromJson({'process': 'paper'}), LayerMark.none);
    expect(
      LayerMark.fromJson({'process': 'paper', 'paperOf': 'paper'}),
      LayerMark.none,
    );
    expect(
      LayerMark.fromJson({'process': 'key', 'paperOf': 'layout'}),
      const LayerMark(process: LayerProcess.key),
    );
  });

  test('its revise is the correction it is the paper of, and none for the '
      'paper of a stage', () {
    expect(paperAd.revise, LayerRevise.animationDirector);
    expect(paperLo.revise, isNull);
    expect(paperLo.step, LayerProcess.layout);
  });

  test('a paper is addressed and sorted by what it is the paper of — 용지-LO '
      'first, before the paper of any other stage', () {
    expect(paperLo.keySlug, 'paper-layout');
    expect(paperAd.keySlug, 'paper-animation-director');
    final papers = labelsOf(LayerProcess.paper);
    expect(
      [...papers.reversed]..sort((a, b) => a.sortKey.compareTo(b.sortKey)),
      papers,
    );
    expect(
      paperLo.sortKey,
      lessThan(const LayerMark.paper(LayerProcess.conte).sortKey),
    );
    expect(
      papers.last.sortKey,
      lessThan(const LayerMark(process: LayerProcess.conte).sortKey),
      reason: 'the papers stay together, ahead of the next stage',
    );
  });

  test('two papers of different things are different labels', () {
    expect(paperLo, isNot(const LayerMark.paper(LayerProcess.key)));
    expect(paperLo, isNot(paperAd));
    expect(paperLo.colorLabel, paperLo);
    expect(paperLo.withTake(2).colorLabel, paperLo);
  });

  test('its chip writes 用紙 over what it is the paper of, in the program '
      'language', () {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );

    expect(layerMarkChipText(paperLo), (process: '용지', step: 'LO'));
    expect(layerMarkChipText(paperAd), (process: '용지', step: '작감'));
    expect(
      layerMarkChipText(const LayerMark.paper(LayerProcess.roughKey)),
      (process: '용지', step: '러프원'),
    );
  });
}
