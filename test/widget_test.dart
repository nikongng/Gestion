import 'package:flutter_test/flutter_test.dart';

import 'package:gestia_project/app.dart';

void main() {
  testWidgets('Affiche l’écran de configuration si Supabase absent', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GestiaApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('Configurer Supabase'), findsOneWidget);
  });
}
