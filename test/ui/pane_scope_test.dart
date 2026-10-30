import 'package:fl_clash/ui/surface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PaneBackdropScope marks its subtree', (tester) async {
    late bool found;
    await tester.pumpWidget(
      PaneBackdropScope(
        child: Builder(
          builder: (context) {
            found = PaneBackdropScope.drawsPageOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(found, isTrue);
  });
}
