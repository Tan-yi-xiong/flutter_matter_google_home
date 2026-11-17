import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_matter_google_home_example/main.dart';

void main() {
  testWidgets('renders the commissioning example', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Google Home Matter Example'), findsOneWidget);
    expect(find.text('Commission only'), findsOneWidget);
    expect(find.text('Start handoff session'), findsOneWidget);
  });
}
