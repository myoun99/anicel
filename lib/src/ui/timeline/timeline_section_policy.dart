import '../../models/layer_sections.dart';

// The order itself is the MODEL's (F-596): a cut's rows stand in it
// ([Cut.layers]), and the timeline reads them as they stand.
export '../../models/layer_sections.dart';

/// The gutter label — the paper timesheet's column-group headings laid on
/// their side (액션 / SE / CAM as the sheet prints them; CAM matches the
/// printed sheet's group header, user rule).
String timelineSectionLabel(TimelineSection section) {
  return switch (section) {
    TimelineSection.drawing => 'ACTION',
    TimelineSection.se => 'SE',
    TimelineSection.camera => 'CAM',
  };
}
