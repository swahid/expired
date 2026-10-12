import 'package:expired/database_helper.dart';
import 'package:expired/main.dart';
import 'package:expired/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Lets real DB I/O complete (sqflite ffi runs outside the fake clock), then
/// advances animations. Fixed pumps instead of pumpAndSettle, because a
/// loading spinner never settles while its DB future is still pending.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> addItems({
  required String barcode,
  required String name,
  required DateTime expiry,
  int quantity = 1,
  double price = 0,
}) async {
  final productId = await AppDatabase.instance.upsertProduct(
    ProductRecord(
      barcode: barcode,
      name: name,
      price: price,
      createdAt: DateTime.now().toIso8601String(),
    ),
  );
  final now = DateTime.now().toIso8601String();
  for (var i = 0; i < quantity; i++) {
    await AppDatabase.instance.insertItem(
      InventoryItemRecord(
        productId: productId,
        purchaseDate: now,
        entryDate: now,
        expiryDate: dateOnlyString(expiry),
        finished: 0,
        createdAt: now,
      ),
    );
  }
}

DateTime daysFromToday(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.resetDatabaseFiles();
  });

  testWidgets('shows the empty dashboard with a scan call to action', (
    tester,
  ) async {
    await tester.pumpWidget(const ExpiredApp());
    await settle(tester);

    expect(find.text('Expired'), findsWidgets);
    expect(find.text('No products yet'), findsOneWidget);
    expect(find.text('Scan your first product'), findsOneWidget);
  });

  testWidgets('adds a product without a barcode using a quick expiry chip', (
    tester,
  ) async {
    await tester.pumpWidget(const ExpiredApp());
    await settle(tester);

    // No camera plugin in tests, so the scan flow falls back to manual entry.
    await tester.tap(find.text('Scan / Add'));
    await settle(tester);
    expect(find.text('New Product'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Product name'),
      'Bread',
    );
    await tester.tap(find.text('1 month'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save product'));
    await tester.tap(find.text('Save product'));
    await settle(tester);

    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('30 d left'), findsOneWidget);
  });

  testWidgets('tapping a product opens edit with a delete option', (
    tester,
  ) async {
    await tester.runAsync(
      () => addItems(barcode: '123', name: 'Milk', expiry: daysFromToday(2)),
    );

    await tester.pumpWidget(const ExpiredApp());
    await settle(tester);

    await tester.tap(find.text('Milk'));
    await settle(tester);

    expect(find.text('Edit Product'), findsOneWidget);
    expect(find.text('Delete product'), findsOneWidget);
  });

  testWidgets('swiping right marks one unit used and undo restores it', (
    tester,
  ) async {
    await tester.runAsync(
      () => addItems(
        barcode: '456',
        name: 'Yogurt',
        expiry: daysFromToday(3),
        quantity: 2,
        price: 50,
      ),
    );

    await tester.pumpWidget(const ExpiredApp());
    await settle(tester);
    expect(find.textContaining('Qty 2'), findsOneWidget);

    await tester.drag(find.text('Yogurt'), const Offset(500, 0));
    await settle(tester);

    expect(find.textContaining('Qty 1'), findsOneWidget);
    expect(find.text('Used ৳50'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(find.textContaining('Qty 2'), findsOneWidget);
  });

  testWidgets('expired filter shows only past items', (tester) async {
    await tester.runAsync(
      () =>
          addItems(barcode: '1', name: 'Old cheese', expiry: daysFromToday(-2)),
    );
    await tester.runAsync(
      () => addItems(
        barcode: '2',
        name: 'Fresh juice',
        expiry: daysFromToday(20),
      ),
    );

    await tester.pumpWidget(const ExpiredApp());
    await settle(tester);

    await tester.tap(find.byIcon(Icons.event_busy_rounded));
    await settle(tester);
    expect(find.text('Old cheese'), findsOneWidget);
    expect(find.text('Fresh juice'), findsNothing);
  });

  test('upgrades a v1 database and normalizes expiry dates', () async {
    final path = join(await getDatabasesPath(), 'expired_local.db');
    final v1 = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE product (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'barcode TEXT UNIQUE NOT NULL, name TEXT NOT NULL, '
          'price REAL NOT NULL DEFAULT 0, createdAt TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE category (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'name TEXT UNIQUE NOT NULL, createdAt TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'productId INTEGER NOT NULL, categoryId INTEGER, '
          'purchaseDate TEXT NOT NULL, entryDate TEXT NOT NULL, '
          'expiryDate TEXT NOT NULL DEFAULT "", '
          'finished INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL)',
        );
      },
    );
    await v1.insert('product', {
      'barcode': '789',
      'name': 'Butter',
      'price': 120,
      'createdAt': '2026-01-01T00:00:00.000',
    });
    await v1.insert('items', {
      'productId': 1,
      'purchaseDate': '2026-01-01T00:00:00.000',
      'entryDate': '2026-01-01T00:00:00.000',
      'expiryDate': '2030-05-04T13:45:00.000',
      'createdAt': '2026-01-01T00:00:00.000',
    });
    await v1.close();

    final items = await AppDatabase.instance.getDashboardItems();
    expect(items.single['expiryDate'], '2030-05-04');
    expect(items.single['name'], 'Butter');

    final ids = await AppDatabase.instance.markItemsFinished(
      1,
      '2030-05-04',
      1,
      'used',
    );
    expect(ids, hasLength(1));
  });

  test('notification digests only cover reminder days', () {
    final now = DateTime(2026, 10, 13, 8);
    final digests = NotificationService.buildDigests([
      {'name': 'Milk', 'expiryDate': '2026-10-14'},
      {'name': 'Eggs', 'expiryDate': '2026-10-20'},
      {'name': 'Rice', 'expiryDate': '2027-06-01'},
    ], now);

    // Milk: today (7 days before is past), the 13th (1 day before), the 14th.
    // Eggs: the 13th (7 days before), 19th, 20th. Rice: beyond the window.
    expect(digests.keys, hasLength(4));
    final today = digests[DateTime(2026, 10, 13)]!;
    expect(today.title, '⚠️ 2 products expiring soon');
    expect(today.body, 'Milk expires tomorrow (+1 more)');
    expect(digests[DateTime(2026, 10, 20)]!.body, 'Eggs expires today');
  });
}
