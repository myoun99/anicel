import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timesheet_info.dart';

void main() {
  group('TimesheetInfo', () {
    test('serializes the hidden header boxes round-trip', () {
      const info = TimesheetInfo(
        title: 'YOASOBI',
        episode: 'MV',
        hiddenFields: {TimesheetHeaderField.scene, TimesheetHeaderField.sheet},
      );

      final restored = TimesheetInfo.fromJson(info.toJson());
      expect(restored, info);
      expect(restored.hiddenFields, {
        TimesheetHeaderField.scene,
        TimesheetHeaderField.sheet,
      });
    });

    test('older files without the new keys load with everything visible', () {
      final restored = TimesheetInfo.fromJson({
        'title': 'YOASOBI',
        'episode': 'MV',
      });

      expect(restored.hiddenFields, isEmpty);
      expect(restored.visibleFields, TimesheetHeaderField.values);
    });

    test('⛔an old file\'s scene and artist are not the work\'s any more', () {
      // 유저 09-25: 「씬은 작품설정에선 필요없어」 · 「작품설정 작업자랑
      // 원화랑 겹치니까 … 스태프의 원화 이름 인식하게하고」.
      final restored = TimesheetInfo.fromJson({
        'title': 'YOASOBI',
        'scene': 'S12',
        'artist': 'MYOUN',
      });

      expect(restored.toJson().keys, isNot(contains('scene')));
      expect(restored.toJson().keys, isNot(contains('artist')));
      expect(restored, const TimesheetInfo(title: 'YOASOBI'));
    });

    test('unknown hidden-field names from newer files drop silently', () {
      final restored = TimesheetInfo.fromJson({
        'hiddenFields': ['scene', 'holographic-box'],
      });

      expect(restored.hiddenFields, {TimesheetHeaderField.scene});
    });

    test('visibleFields keeps the printing order minus hidden boxes', () {
      const info = TimesheetInfo(hiddenFields: {TimesheetHeaderField.episode});

      expect(info.visibleFields, const [
        TimesheetHeaderField.title,
        TimesheetHeaderField.scene,
        TimesheetHeaderField.cut,
        TimesheetHeaderField.time,
        TimesheetHeaderField.name,
        TimesheetHeaderField.sheet,
      ]);
    });

    test('notation settings default to bar-off / SE-fill-on, round-trip and '
        'stay absent from default JSON', () {
      const defaults = TimesheetInfo.empty;
      expect(defaults.exposureBarThreshold, isNull);
      expect(defaults.seEmptyFill, isTrue);
      expect(defaults.toJson().containsKey('exposureBarThreshold'), isFalse);
      expect(defaults.toJson().containsKey('seEmptyFill'), isFalse);

      const custom = TimesheetInfo(exposureBarThreshold: 3, seEmptyFill: false);
      final restored = TimesheetInfo.fromJson(custom.toJson());
      expect(restored, custom);
      expect(restored.exposureBarThreshold, 3);
      expect(restored.seEmptyFill, isFalse);
    });

    test('copyWith keeps and clears the exposure-bar threshold via the '
        'nullable closure', () {
      const info = TimesheetInfo(exposureBarThreshold: 3);
      expect(info.copyWith(seEmptyFill: false).exposureBarThreshold, 3);
      expect(
        info.copyWith(exposureBarThreshold: () => null).exposureBarThreshold,
        isNull,
      );
      expect(
        info.copyWith(exposureBarThreshold: () => 5).exposureBarThreshold,
        5,
      );
    });
  });

  group('production staff', () {
    // The stages the work keeps: the conte's (F-291-Q1).
    const conte = LayerMark(process: LayerProcess.conte);
    const conteDirector = LayerMark(
      process: LayerProcess.conte,
      revise: LayerRevise.director,
    );

    test('staffNameFor answers an empty name rather than null', () {
      expect(TimesheetInfo.empty.staffNameFor(conte), '');
    });

    test('a stage and its correction are two names, keyed by the label', () {
      // 유저 답 staff-roles-from-labels: 「공정별 묶음 — 작업자 + 그 공정의
      // 수정 담당」.
      final info = TimesheetInfo.empty
          .withStaffName(conte, '大川')
          .withStaffName(conteDirector, '清');

      expect(info.staffNameFor(conte), '大川');
      expect(info.staffNameFor(conteDirector), '清');
      expect(info.staff, {
        conte.keySlug: '大川',
        conteDirector.keySlug: '清',
      });
    });

    test('the take is not part of whose work it is', () {
      final info = TimesheetInfo.empty.withStaffName(conte, '大川');
      expect(info.staffNameFor(conte.withTake(2)), '大川');
    });

    test('withStaffName DROPS a name when emptied', () {
      final cleared = TimesheetInfo.empty
          .withStaffName(conte, '大川')
          .withStaffName(conte, '');
      expect(
        cleared.staff,
        isEmpty,
        reason: 'a blank entry would accumulate for every role ever touched',
      );
    });

    test('staff and logo round-trip through JSON', () {
      final info = TimesheetInfo.empty
          .withStaffName(conte, '大川')
          .withStaffName(conteDirector, '清')
          .copyWith(logoAssetPath: () => 'logos/studio.png');

      final restored = TimesheetInfo.fromJson(info.toJson());

      expect(restored, info);
      expect(restored.staffNameFor(conteDirector), '清');
      expect(restored.logoAssetPath, 'logos/studio.png');
    });

    // ↩️Two pins stood here for what the reader dropped from a file: a staff
    // value that was a name-and-stamp object (before the labels vocabulary),
    // and a stage the work no longer keeps (before F-291-Q1, 유저 2026-10-08:
    // 「스태프는 콘티만 남겨둠. 나머진 삭제. 나머진 컷마다 스태프설정」 — the
    // rule itself lives on in `staffHolderOf`). Both shapes are only in
    // formats refused by their number now (the save law, 유저 2026-10-06).
    test('an old file with no staff loads clean', () {
      final restored = TimesheetInfo.fromJson({'title': 'X'});

      expect(restored.staff, isEmpty);
      expect(restored.logoAssetPath, isNull);
      expect(restored.coverImagePath, isNull);
      expect(restored.envelopeFormId, CutEnvelopePresets.analogId);
      expect(
        (restored.conteCover, restored.conteBlankPage),
        (true, true),
        reason: 'a conte book has its cover and blank back unless taken out',
      );
    });
  });

  group('the work\'s paper choices', () {
    test('the cover picture and the envelope form travel with the work', () {
      // 유저 답 conte-cover-image: 「표지 그림 칸을 따로」 · 유저 답
      // sheet-form-choice-home: 「해당 패널에 지금처럼 두고싶고, 그
      // 상태에서 작품에 저장되도록」.
      final info = TimesheetInfo.empty.copyWith(
        coverImagePath: () => 'media/cover.png',
        envelopeFormId: CutEnvelopePresets.digitalId,
      );

      final restored = TimesheetInfo.fromJson(info.toJson());

      expect(restored, info);
      expect(restored.coverImagePath, 'media/cover.png');
      expect(restored.envelopeFormId, CutEnvelopePresets.digitalId);
      expect(
        restored.copyWith(coverImagePath: () => null).coverImagePath,
        isNull,
        reason: 'a cover picture can be cleared',
      );
    });

    test('the conte book\'s front travels with the work — each of its two '
        'pages on its own — and a whole front writes nothing', () {
      // 유저 2026-10-02 (I-59): 「1페이지 헤더 넣기/빼기, 2페이지 빈용지
      // 넣기빼기 … 이게 내보내기시에도 연동」.
      final whole = TimesheetInfo.empty.toJson();
      expect(whole.containsKey('conteCover'), isFalse);
      expect(whole.containsKey('conteBlankPage'), isFalse);
      for (final (cover, blank) in [
        (false, true),
        (true, false),
        (false, false),
      ]) {
        final info = TimesheetInfo.empty.copyWith(
          conteCover: cover,
          conteBlankPage: blank,
        );

        final restored = TimesheetInfo.fromJson(info.toJson());

        expect(restored, info);
        expect((restored.conteCover, restored.conteBlankPage), (cover, blank));
      }
      expect(
        TimesheetInfo.empty.copyWith(conteCover: false),
        isNot(TimesheetInfo.empty),
        reason: 'a change of front is a change of the work — one undo step',
      );
    });
  });
}
