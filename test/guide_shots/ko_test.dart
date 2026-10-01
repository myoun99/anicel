@Skip('guide screenshots, not a check: how to run them is in guide_shots.dart')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';

import 'guide_shots.dart';

void main() => guideShots(AppLanguage.ko);
