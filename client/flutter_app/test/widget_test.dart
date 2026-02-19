import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aioc_client/main.dart';

void main() {
  testWidgets('AIOC app renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AIOCApp()));

    // Verify AIOC title appears
    expect(find.text('AIOC'), findsWidgets);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
