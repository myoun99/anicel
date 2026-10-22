import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart' show AppColors;

/// The border a place a file can be dropped on lights while one is over
/// it — a pool row's (`MediaAssetDropTarget`) and a file's from the OS
/// (`OsFileDropEntrance`) alike: one entrance, one light.
///
/// Its room is always there; [lit] changes only what is in it.
class DropEntranceFrame extends StatelessWidget {
  const DropEntranceFrame({super.key, required this.lit});

  final bool lit;

  @override
  Widget build(BuildContext context) => lit
      ? DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accent, width: 2),
          ),
        )
      : const SizedBox.expand();
}
