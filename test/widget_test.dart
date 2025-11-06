// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart'; // 相対importでOK

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ZariMahjongApp());
    expect(find.byType(ZariMahjongApp), findsOneWidget);
  });
}
