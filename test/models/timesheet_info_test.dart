import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/timesheet_info.dart';

void main() {
  group('TimesheetInfo', () {
    test('serializes scene and hidden header boxes round-trip', () {
      const info = TimesheetInfo(
        title: 'YOASOBI',
        episode: 'MV',
        scene: 'S12',
        artist: 'MYOUN',
        hiddenFields: {TimesheetHeaderField.scene, TimesheetHeaderField.sheet},
      );

      final restored = TimesheetInfo.fromJson(info.toJson());
      expect(restored, info);
      expect(restored.scene, 'S12');
      expect(restored.hiddenFields, {
        TimesheetHeaderField.scene,
        TimesheetHeaderField.sheet,
      });
    });

    test('older files without the new keys load with everything visible', () {
      final restored = TimesheetInfo.fromJson({
        'title': 'YOASOBI',
        'episode': 'MV',
        'artist': 'MYOUN',
      });

      expect(restored.scene, '');
      expect(restored.hiddenFields, isEmpty);
      expect(restored.visibleFields, TimesheetHeaderField.values);
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
      const defaults = TimesheetInfo();
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
    test('staffFor answers an empty assignee rather than null', () {
      expect(TimesheetInfo.empty.staffFor(ProductionRole.genga).name, '');
      expect(TimesheetInfo.empty.staffFor('anything').isEmpty, isTrue);
    });

    test('withStaff sets a role and DROPS it when emptied', () {
      final assigned = TimesheetInfo.empty.withStaff(
        ProductionRole.genga,
        const ProductionStaff(name: '大川'),
      );
      expect(assigned.staff, hasLength(1));
      expect(assigned.staffFor(ProductionRole.genga).name, '大川');

      final cleared = assigned.withStaff(
        ProductionRole.genga,
        ProductionStaff.empty,
      );
      expect(
        cleared.staff,
        isEmpty,
        reason: 'a blank entry would accumulate for every role ever touched',
      );
    });

    test('a stamp is set and cleared through the nullable closure', () {
      const staff = ProductionStaff(name: '清', stampAssetPath: 'stamps/a.png');
      expect(staff.copyWith(name: '明').stampAssetPath, 'stamps/a.png');
      expect(staff.copyWith(stampAssetPath: () => null).stampAssetPath, isNull);
    });

    test('staff and logo round-trip through JSON', () {
      final info = TimesheetInfo.empty
          .withStaff(
            ProductionRole.genga,
            const ProductionStaff(name: '大川', stampAssetPath: 'stamps/o.png'),
          )
          .withStaff(
            ProductionRole.director,
            const ProductionStaff(name: '清'),
          )
          .copyWith(logoAssetPath: () => 'logos/studio.png');

      final restored = TimesheetInfo.fromJson(info.toJson());

      expect(restored, info);
      expect(restored.staffFor(ProductionRole.genga).stampAssetPath,
          'stamps/o.png');
      expect(restored.staffFor(ProductionRole.director).stampAssetPath, isNull);
      expect(restored.logoAssetPath, 'logos/studio.png');
    });

    test('an old file with no staff loads clean', () {
      final restored = TimesheetInfo.fromJson({'title': 'X'});

      expect(restored.staff, isEmpty);
      expect(restored.logoAssetPath, isNull);
    });
  });
}
