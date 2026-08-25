import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/main.dart';

void main() {
  testWidgets('renders the initial app screen', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('Hello World!'), findsOneWidget);
  });
}
