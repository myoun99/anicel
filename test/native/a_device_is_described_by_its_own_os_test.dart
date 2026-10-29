import 'dart:io';

import 'package:anicel/src/native/device_description.dart';
import 'package:anicel/src/services/feedback/feedback_forms.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the feedback forms are told about the device (I-139), read from
/// each OS itself.
void main() {
  group('the model', () {
    test('the maker, then the model', () {
      expect(
        DeviceDescriptions.joinedModel(
          'Microsoft Corporation',
          'Surface Pro, 11th Edition',
        ),
        'Microsoft Corporation Surface Pro, 11th Edition',
      );
    });

    test('the maker once, where the model already starts with it', () {
      expect(
        DeviceDescriptions.joinedModel('LENOVO', 'Lenovo TB-X606F'),
        'Lenovo TB-X606F',
      );
    });

    test('a BIOS placeholder is no maker', () {
      // 🧪What the main PC's board reads (2026-10-28).
      expect(
        DeviceDescriptions.joinedModel(
          'To Be Filled By O.E.M.',
          'Z690 Steel Legend/D5',
        ),
        'Z690 Steel Legend/D5',
      );
      expect(
        DeviceDescriptions.joinedModel('System manufacturer', 'Default string'),
        isNull,
      );
    });

    test('either alone, or nothing', () {
      expect(DeviceDescriptions.joinedModel(null, 'SM-X710'), 'SM-X710');
      expect(DeviceDescriptions.joinedModel('samsung', ''), 'samsung');
      expect(DeviceDescriptions.joinedModel(' ', null), isNull);
    });
  });

  group('Windows\' version', () {
    test('a build from 22000 on is 11, though it calls itself 10.0', () {
      expect(
        DeviceDescriptions.windowsVersion(
          build: '26200',
          release: '25H2',
          update: 6899,
        ),
        '11 25H2 (26200.6899)',
      );
      expect(
        DeviceDescriptions.windowsVersion(build: '22000'),
        '11 (22000)',
      );
    });

    test('one before it is 10', () {
      expect(
        DeviceDescriptions.windowsVersion(
          build: '19045',
          release: '22H2',
          update: 5965,
        ),
        '10 22H2 (19045.5965)',
      );
    });

    test('no build, no version', () {
      expect(DeviceDescriptions.windowsVersion(build: null), isNull);
    });
  });

  test('Linux names itself by PRETTY_NAME', () {
    expect(
      DeviceDescriptions.prettyNameIn(
        'NAME="Ubuntu"\nVERSION_ID="24.04"\n'
        'PRETTY_NAME="Ubuntu 24.04.1 LTS"\nID=ubuntu\n',
      ),
      'Ubuntu 24.04.1 LTS',
    );
    expect(DeviceDescriptions.prettyNameIn('ID=arch\n'), isNull);
  });

  test('the machine running this reads itself', () {
    // 🧪The real OS, through the real reads: a wrong HKEY_LOCAL_MACHINE or a
    // wrong flag reads nothing, and nothing says Unknown.
    final device = DeviceDescriptions.read();
    expect(device.osVersion, isNot(DeviceDescriptions.unknown));
    if (Platform.isWindows) {
      expect(device.os, FeedbackOs.windows);
      expect(device.model, isNot(DeviceDescriptions.unknown));
      expect(device.osVersion, matches(RegExp(r'^1[01] .*\(\d+\.\d+\)$')));
    } else if (Platform.isMacOS) {
      expect(device.os, FeedbackOs.macOS);
    } else {
      expect(device.os, FeedbackOs.linux);
    }
  });
}
