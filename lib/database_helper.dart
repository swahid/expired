import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Formats [date] as a date-only `yyyy-MM-dd` string used for expiry dates.
String dateOnlyString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static Database? _database;

  Future<Database> get database async {
    final current = _database;
    if (current != null) {
      try {
        await current.rawQuery('SELECT 1');
        return current;
      } catch (_) {
        _database = null;
      }
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'expired_local.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async => _seedDefaultCategories(db),
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'product', 'categoryId', 'INTEGER');
      await _addColumnIfMissing(db, 'product', 'defaultShelfDays', 'INTEGER');
      await _addColumnIfMissing(db, 'items', 'finishedAt', 'TEXT');
      await _addColumnIfMissing(db, 'items', 'finishReason', 'TEXT');
      // v1 stored expiry with a time component; normalize to yyyy-MM-dd.
      await db.execute(
        'UPDATE items SET expiryDate = substr(expiryDate, 1, 10) '
        'WHERE length(expiryDate) > 10',
      );
    }
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE product (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        categoryId INTEGER,
        defaultShelfDays INTEGER,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE category (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        productId INTEGER NOT NULL,
        categoryId INTEGER,
        purchaseDate TEXT NOT NULL,
        entryDate TEXT NOT NULL,
        expiryDate TEXT NOT NULL DEFAULT "",
        finished INTEGER NOT NULL DEFAULT 0,
        finishedAt TEXT,
        finishReason TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (productId) REFERENCES product(id) ON DELETE CASCADE,
        FOREIGN KEY (categoryId) REFERENCES category(id) ON DELETE SET NULL
      )
    ''');

    await _seedDefaultCategories(db);
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final defaultCategories = [
      {'name': 'Food', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Dairy', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Meat & Seafood', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Fruits & Vegetables', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Bakery', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Beverages', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Frozen Foods', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Snacks', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Medicine', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Supplements', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Cosmetics', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Baby Care', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Pet Care', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Household', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Other', 'createdAt': '2026-06-13T00:00:00.000'},
    ];

    for (final category in defaultCategories) {
      await db.insert(
        'category',
        category,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<T> _withRetry<T>(Future<T> Function(Database db) action) async {
    try {
      final db = await database;
      return await action(db);
    } catch (_) {
      _database = null;
      final db = await database;
      return await action(db);
    }
  }

  Future<List<CategoryRecord>> getCategories() async => _withRetry((db) async {
    await _seedDefaultCategories(db);
    final rows = await db.query('category', orderBy: 'name ASC');
    return rows.map(CategoryRecord.fromMap).toList();
  });

  Future<List<ProductRecord>> getProducts() async {
    try {
      return await _withRetry((db) async {
        final rows = await db.query('product', orderBy: 'id DESC');
        return rows.map(ProductRecord.fromMap).toList();
      });
    } catch (_) {
      return const <ProductRecord>[];
    }
  }

  Future<List<Map<String, dynamic>>> getDashboardItems() async {
    return _withRetry((db) async {
      return await db.rawQuery('''
        SELECT
          p.id as productId,
          p.barcode,
          p.name,
          p.price,
          MIN(i.purchaseDate) as purchaseDate,
          i.expiryDate as expiryDate,
          COUNT(i.id) as quantity,
          MAX(c.name) as category
        FROM product p
        INNER JOIN items i ON i.productId = p.id
        LEFT JOIN category c ON c.id = i.categoryId
        WHERE i.finished = 0
        GROUP BY p.id, i.expiryDate
        ORDER BY i.expiryDate ASC
      ''');
    });
  }

  Future<ProductRecord?> findProductByBarcode(String barcode) async =>
      _withRetry((db) async {
        final rows = await db.query(
          'product',
          where: 'barcode = ?',
          whereArgs: [barcode],
          limit: 1,
        );

        if (rows.isEmpty) {
          return null;
        }

        return ProductRecord.fromMap(rows.first);
      });

  Future<int> upsertProduct(ProductRecord record) async {
    final existing = await findProductByBarcode(record.barcode);
    return _withRetry((db) async {
      if (existing == null) {
        return db.insert('product', record.toMap());
      }

      await db.update(
        'product',
        record.toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return existing.id!;
    });
  }

  Future<int> insertItem(InventoryItemRecord record) async =>
      _withRetry((db) async {
        return db.insert('items', record.toMap());
      });

  Future<List<InventoryItemRecord>> getItems() async => _withRetry((db) async {
    final rows = await db.query('items', orderBy: 'entryDate DESC');
    return rows.map(InventoryItemRecord.fromMap).toList();
  });

  /// Returns unfinished items with a known expiry date, soonest first.
  Future<List<Map<String, dynamic>>> getUpcomingExpiries() async =>
      _withRetry((db) async {
        return db.rawQuery('''
          SELECT p.name, i.expiryDate, COUNT(i.id) as quantity
          FROM items i
          JOIN product p ON p.id = i.productId
          WHERE i.finished = 0
            AND i.expiryDate != ""
          GROUP BY p.id, i.expiryDate
          ORDER BY i.expiryDate ASC
        ''');
      });

  /// Marks up to [count] unfinished items of a product/expiry group as
  /// finished with [reason] ('used' or 'wasted'). Returns the affected ids so
  /// the action can be undone with [unfinishItems].
  Future<List<int>> markItemsFinished(
    int productId,
    String expiryDate,
    int count,
    String reason,
  ) async => _withRetry((db) async {
    final rows = await db.query(
      'items',
      columns: ['id'],
      where: 'productId = ? AND expiryDate = ? AND finished = 0',
      whereArgs: [productId, expiryDate],
      limit: count,
    );
    final ids = rows.map((row) => row['id'] as int).toList();
    if (ids.isEmpty) return ids;
    await db.update(
      'items',
      {
        'finished': 1,
        'finishedAt': DateTime.now().toIso8601String(),
        'finishReason': reason,
      },
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
    return ids;
  });

  Future<void> unfinishItems(List<int> ids) async => _withRetry((db) async {
    if (ids.isEmpty) return;
    await db.update(
      'items',
      {'finished': 0, 'finishedAt': null, 'finishReason': null},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  });

  /// Total value of items marked used / wasted during [month].
  Future<({double used, double wasted})> getMonthlyStats(
    DateTime month,
  ) async => _withRetry((db) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final rows = await db.rawQuery(
      '''
          SELECT i.finishReason as reason, SUM(p.price) as total
          FROM items i
          JOIN product p ON p.id = i.productId
          WHERE i.finished = 1 AND i.finishedAt >= ? AND i.finishedAt < ?
          GROUP BY i.finishReason
          ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    double totalFor(String reason) =>
        (rows.where((r) => r['reason'] == reason).firstOrNull?['total'] as num?)
            ?.toDouble() ??
        0;
    return (used: totalFor('used'), wasted: totalFor('wasted'));
  });

  Future<CategoryRecord?> getCategoryById(int id) async =>
      _withRetry((db) async {
        final rows = await db.query(
          'category',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        return rows.isEmpty ? null : CategoryRecord.fromMap(rows.first);
      });

  Future<void> deleteItemsByProductAndExpiry(
    int productId,
    String expiryDate,
  ) async => _withRetry((db) async {
    await db.delete(
      'items',
      where: 'productId = ? AND expiryDate = ?',
      whereArgs: [productId, expiryDate],
    );
  });

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }

  Future<void> reset() async {
    await close();
    final dbPath = await getDatabasesPath();
    await deleteDatabase(join(dbPath, 'expired_local.db'));
  }

  Future<void> resetDatabaseFiles() async {
    await close();
    final dbPath = await getDatabasesPath();
    await deleteDatabase(join(dbPath, 'expired_local.db'));
  }
}

class ProductRecord {
  ProductRecord({
    this.id,
    required this.barcode,
    required this.name,
    required this.price,
    required this.createdAt,
    this.categoryId,
    this.defaultShelfDays,
  });

  final int? id;
  final String barcode;
  final String name;
  final double price;
  final String createdAt;
  final int? categoryId;

  /// Days between adding and expiry last time; used to pre-fill re-scans.
  final int? defaultShelfDays;

  Map<String, dynamic> toMap() => {
    'id': id,
    'barcode': barcode,
    'name': name,
    'price': price,
    'categoryId': categoryId,
    'defaultShelfDays': defaultShelfDays,
    'createdAt': createdAt,
  }..removeWhere((key, value) => key == 'id' && value == null);

  factory ProductRecord.fromMap(Map<String, dynamic> map) => ProductRecord(
    id: map['id'] as int?,
    barcode: map['barcode'] as String,
    name: map['name'] as String,
    price: (map['price'] as num).toDouble(),
    categoryId: map['categoryId'] as int?,
    defaultShelfDays: map['defaultShelfDays'] as int?,
    createdAt: map['createdAt'] as String,
  );
}

class CategoryRecord {
  CategoryRecord({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String createdAt;

  factory CategoryRecord.fromMap(Map<String, dynamic> map) => CategoryRecord(
    id: map['id'] as int,
    name: map['name'] as String,
    createdAt: map['createdAt'] as String,
  );
}

class InventoryItemRecord {
  InventoryItemRecord({
    this.id,
    required this.productId,
    this.categoryId,
    required this.purchaseDate,
    required this.entryDate,
    required this.expiryDate,
    required this.finished,
    required this.createdAt,
  });

  final int? id;
  final int productId;
  final int? categoryId;
  final String purchaseDate;
  final String entryDate;
  final String expiryDate;
  final int finished;
  final String createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'productId': productId,
    'categoryId': categoryId,
    'purchaseDate': purchaseDate,
    'entryDate': entryDate,
    'expiryDate': expiryDate,
    'finished': finished,
    'createdAt': createdAt,
  }..removeWhere((key, value) => key == 'id' && value == null);

  factory InventoryItemRecord.fromMap(Map<String, dynamic> map) =>
      InventoryItemRecord(
        id: map['id'] as int?,
        productId: map['productId'] as int,
        categoryId: map['categoryId'] as int?,
        purchaseDate: map['purchaseDate'] as String,
        entryDate: map['entryDate'] as String,
        expiryDate: map['expiryDate'] as String? ?? '',
        finished: map['finished'] as int? ?? 0,
        createdAt: map['createdAt'] as String,
      );
}
