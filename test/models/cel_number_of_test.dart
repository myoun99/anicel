import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/layer_kind.dart';

/// ONE ANSWER TO 「DOES THIS DRAWING HAVE A NAME」 (C-save-percent).
///
/// [Frame.celNumber] answered it for the sheet and the cel export, and seven
/// places on screen answered it again with `name.isEmpty` — so a name of
/// spaces printed as spaces there and as the mark on the sheet. A painter
/// holds a name rather than a frame, so the answer is a function of the
/// name; these pins say what it answers.
void main() {
  const cel = LayerKind.animation;

  test('a name prints trimmed; a blank one is no name', () {
    expect(celNumberOf('12'), '12');
    expect(celNumberOf(' 12 '), '12');
    expect(celNumberOf(null), isNull);
    expect(celNumberOf(''), isNull);
    expect(celNumberOf(' \t'), isNull);
  });

  test('no name wears the in-between mark — one mark as DATA (2026-09-24), '
      'the one its host hands it (F-489)', () {
    // 🗣️유저 2026-09-16: 「일단 이름 없는 기본상태를 속이 찬 동그라미로
    // 통일적용 … 추후 두번째 중간나누기 마크(속이 빈)를 활용할지도
    // 모르겠지만 당장은 제거」. The GLYPHS are pinned here by value — every
    // other test asks the marks, so this is the one place that says what
    // they are. 🗣️I-130 (유저 2026-10-25): 「지금의 속이 찬 점을 마크2, 속이
    // 빈 그냥 선으로 된 원을 마크1」.
    expect(InbetweenMark.one.glyph, '○');
    expect(InbetweenMark.two.glyph, '●');
    // 🗣️유저 2026-09-24: 「데이터적으로도 같은 취급시키는거 맞지? 중간나누기
    // 마크1로서 작동했으면」 — the unnamed head wears a mark as data, the
    // one the dot inside a block wore. 🗣️F-489 (유저 2026-10-27): which of
    // the two is a pick, mark 2 the ● to begin with — 「업계일반적으론
    // 마크2가 보통이라서 기본값은 마크2로 둠」. ↩️Mark 1, the ○, from F-469.
    expect(defaultUnnamedDrawingMark, InbetweenMark.two);
    expect(const AppFrameGridSettings().unnamedMark, InbetweenMark.two);
    for (final mark in InbetweenMark.values) {
      expect(drawingHeadOf('A1', kind: cel, unnamedMark: mark), (
        word: 'A1',
        mark: null,
      ));
      expect(drawingHeadOf(null, kind: cel, unnamedMark: mark), (
        word: '',
        mark: mark,
      ));
      expect(drawingHeadOf('   ', kind: cel, unnamedMark: mark), (
        word: '',
        mark: mark,
      ));
    }
  });

  test('as TEXT the mark is the glyph of the one picked now — a file name, '
      'a notice', () {
    addTearDown(() => AppFrameGridSettings.settings.value =
        const AppFrameGridSettings());
    expect(celNumberOrMark('A1', kind: cel), 'A1');
    expect(celNumberOrMark(null, kind: cel), '●', reason: 'nothing picked');
    AppFrameGridSettings.settings.value = const AppFrameGridSettings(
      unnamedMark: InbetweenMark.one,
    );
    expect(celNumberOrMark(null, kind: cel), '○');
    expect(celNumberOrMark('   ', kind: cel), '○');
    AppFrameGridSettings.settings.value = const AppFrameGridSettings();
    expect(celNumberOrMark('   ', kind: cel), '●');
  });

  test('🗣️an unnamed cel on an IMAGE row wears NOTHING — the layer is the '
      'picture, so there is no run for a mark to claim', () {
    // 🗣️유저 2026-09-25: 「이미지레이어는 프레임 이름 없으면 중간나누기
    // 마크가아니라 이름을 안보이게 하는 상태로」.
    const image = LayerKind.image;
    const mark = defaultUnnamedDrawingMark;
    expect(drawingHeadOf(null, kind: image, unnamedMark: mark), (
      word: '',
      mark: null,
    ));
    expect(drawingHeadOf('  ', kind: image, unnamedMark: mark), (
      word: '',
      mark: null,
    ));
    expect(celNumberOrMark(null, kind: image), '');
    expect(
      drawingHeadOf('BOOK1', kind: image, unnamedMark: mark),
      (word: 'BOOK1', mark: null),
      reason: 'a NAMED cel prints its name on every kind',
    );
  });

  test('🗣️and so does every kind but ANIMATION — the one whose unnamed '
      'drawing is an in-between (유저 2026-09-26: 「애니메이션 이외 레이어는 '
      '이름없으면 진짜 이름없도록 통일」)', () {
    for (final kind in LayerKind.values) {
      expect(
        drawingHeadOf(null, kind: kind, unnamedMark: InbetweenMark.one),
        kind == LayerKind.animation
            ? (word: '', mark: InbetweenMark.one)
            : (word: '', mark: null),
        reason: kind.name,
      );
    }
    // ↩️Every kind but the image one kept the mark until then — the
    // storyboard's panels wore it on their bands.
  });
}
