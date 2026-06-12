// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:expired/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:expired/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.resetDatabaseFiles();
  });

  testWidgets('shows the minimalist dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const ExpiredApp());
    await tester.pumpAndSettle();

    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('No products yet'), findsOneWidget);
  });

  testWidgets('shows edit and delete actions for saved products', (
    WidgetTester tester,
  ) async {
    await AppDatabase.instance.upsertProduct(
      ProductRecord(
        barcode: '123',
        name: 'Milk',
        price: 2.5,
        volume: '1',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );

    await tester.pumpWidget(const ExpiredApp());
    await tester.pumpAndSettle();

    expect(find.text('Milk'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });
}
