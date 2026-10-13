import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/row_berths.dart';

/// [rows] seated in their order — for a test that builds the rows' body
/// alone, without the grid that keeps their berths.
RowBerthMap berthsInOrder(List<TimelineDisplayRow> rows) =>
    RowBerths().berthsFor(rows, world: const Object());
