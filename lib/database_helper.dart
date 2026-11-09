import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Formats [date] as a date-only `yyyy-MM-dd` string used for expiry dates.
String dateOnlyString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Valid storage locations for food tracking.
class StorageLocation {
  static const fridge = 'fridge';
  static const freezer = 'freezer';
  static const pantry = 'pantry';

  static const all = [fridge, freezer, pantry];

  static String displayName(String location) {
    switch (location.toLowerCase()) {
      case freezer:
        return 'Freezer';
      case pantry:
        return 'Pantry';
      case fridge:
      default:
        return 'Fridge';
    }
  }

  static String emoji(String location) {
    switch (location.toLowerCase()) {
      case freezer:
        return '❄️';
      case pantry:
        return '🧺';
      case fridge:
      default:
        return '🧊';
    }
  }
}

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

    // SAFEGUARD: If the database exists, create a pre-migration snapshot before openDatabase!
    try {
      final dbFile = File(path);
      if (await dbFile.exists()) {
        final backupPath = join(dbPath, 'expired_local_backup_v2.db');
        final backupFile = File(backupPath);
        if (!await backupFile.exists()) {
          await dbFile.copy(backupPath);
        }
      }
    } catch (_) {
      // Best-effort safety snapshot; never crash startup
    }

    return openDatabase(
      path,
      version: 3,
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
    if (oldVersion < 3) {
      // Storage location: 'fridge' (default), 'freezer', 'pantry'
      await _addColumnIfMissing(
        db,
        'items',
        'storageLocation',
        'TEXT NOT NULL DEFAULT "fridge"',
      );
      // Date food was cooked/prepared (ISO-8601 string, defaults to entryDate)
      await _addColumnIfMissing(db, 'items', 'cookedDate', 'TEXT');
      // Portions / servings remaining (default 1)
      await _addColumnIfMissing(
        db,
        'items',
        'portionCount',
        'INTEGER NOT NULL DEFAULT 1',
      );
      // Flags homemade vs store-bought item (1 = homemade, 0 = store-bought)
      await _addColumnIfMissing(
        db,
        'items',
        'isHomemade',
        'INTEGER NOT NULL DEFAULT 1',
      );
      // Optional notes (e.g. "spicy", "reheat to 75C")
      await _addColumnIfMissing(db, 'items', 'notes', 'TEXT');
      await _addColumnIfMissing(
        db,
        'product',
        'isHomemade',
        'INTEGER NOT NULL DEFAULT 1',
      );
      await _addColumnIfMissing(
        db,
        'product',
        'defaultLocation',
        'TEXT NOT NULL DEFAULT "fridge"',
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
        defaultLocation TEXT NOT NULL DEFAULT "fridge",
        isHomemade INTEGER NOT NULL DEFAULT 1,
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
        storageLocation TEXT NOT NULL DEFAULT "fridge",
        cookedDate TEXT,
        portionCount INTEGER NOT NULL DEFAULT 1,
        isHomemade INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
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
      {'name': 'Leftovers', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Meal Prep', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Soups & Stews', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Food', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Dairy', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Meat & Seafood', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Fruits & Vegetables', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Bakery', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Beverages', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Frozen Foods', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Snacks', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Sauces & Condiments', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Ferments & Pickles', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Baby Care', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Medicine', 'createdAt': '2026-06-13T00:00:00.000'},
      {'name': 'Supplements', 'createdAt': '2026-06-13T00:00:00.000'},
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

  Future<List<Map<String, dynamic>>> getDashboardItems({
    String? storageLocation,
  }) async {
    return _withRetry((db) async {
      final hasLocationFilter =
          storageLocation != null && storageLocation.isNotEmpty;
      final whereClause = hasLocationFilter
          ? 'WHERE i.finished = 0 AND i.storageLocation = ?'
          : 'WHERE i.finished = 0';
      final whereArgs = hasLocationFilter ? [storageLocation] : null;

      return await db.rawQuery('''
        SELECT
          p.id as productId,
          p.barcode,
          p.name,
          p.price,
          p.isHomemade as productIsHomemade,
          MIN(i.purchaseDate) as purchaseDate,
          MIN(i.cookedDate) as cookedDate,
          i.expiryDate as expiryDate,
          COALESCE(i.storageLocation, 'fridge') as storageLocation,
          COUNT(i.id) as quantity,
          SUM(COALESCE(i.portionCount, 1)) as totalPortions,
          MAX(COALESCE(i.isHomemade, 1)) as isHomemade,
          MAX(i.notes) as notes,
          MAX(c.name) as category
        FROM product p
        INNER JOIN items i ON i.productId = p.id
        LEFT JOIN category c ON c.id = i.categoryId
        $whereClause
        GROUP BY p.id, i.expiryDate, COALESCE(i.storageLocation, 'fridge')
        ORDER BY i.expiryDate ASC
      ''', whereArgs);
    });
  }

  /// Top frequently/recently cooked homemade foods for the "Cook Again" chip bar.
  Future<List<ProductRecord>> getFrequentDishes({int limit = 8}) async =>
      _withRetry((db) async {
        final rows = await db.rawQuery('''
          SELECT p.*, COUNT(i.id) as usageCount
          FROM product p
          JOIN items i ON i.productId = p.id
          WHERE p.isHomemade = 1
          GROUP BY p.id
          ORDER BY usageCount DESC, p.id DESC
          LIMIT ?
        ''', [limit]);
        return rows.map(ProductRecord.fromMap).toList();
      });

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
    String reason, {
    String? storageLocation,
  }) async => _withRetry((db) async {
    final whereArgs = <dynamic>[productId, expiryDate];
    var where = 'productId = ? AND expiryDate = ? AND finished = 0';
    if (storageLocation != null && storageLocation.isNotEmpty) {
      where += ' AND COALESCE(storageLocation, "fridge") = ?';
      whereArgs.add(storageLocation);
    }
    final rows = await db.query(
      'items',
      columns: ['id'],
      where: where,
      whereArgs: whereArgs,
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

  /// Moves unfinished items from [fromLocation] to [toLocation] and updates their [expiryDate].
  /// Used for "Thaw / Move to Fridge" or "Move to Freezer".
  Future<void> moveItemToStorage({
    required int productId,
    required String expiryDate,
    required String fromLocation,
    required String toLocation,
    required String newExpiryDate,
  }) async => _withRetry((db) async {
    await db.update(
      'items',
      {
        'storageLocation': toLocation,
        'expiryDate': newExpiryDate,
      },
      where:
          'productId = ? AND expiryDate = ? AND COALESCE(storageLocation, "fridge") = ? AND finished = 0',
      whereArgs: [productId, expiryDate, fromLocation],
    );
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
  Future<({double used, double wasted, int usedCount, int wastedCount})>
  getMonthlyStats(DateTime month) async => _withRetry((db) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final rows = await db.rawQuery(
      '''
          SELECT i.finishReason as reason, SUM(p.price) as total, COUNT(i.id) as count
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
    int countFor(String reason) =>
        (rows.where((r) => r['reason'] == reason).firstOrNull?['count']
                as num?)
            ?.toInt() ??
        0;
    return (
      used: totalFor('used'),
      wasted: totalFor('wasted'),
      usedCount: countFor('used'),
      wastedCount: countFor('wasted'),
    );
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
    String expiryDate, {
    String? storageLocation,
  }) async => _withRetry((db) async {
    final whereArgs = <dynamic>[productId, expiryDate];
    var where = 'productId = ? AND expiryDate = ?';
    if (storageLocation != null && storageLocation.isNotEmpty) {
      where += ' AND COALESCE(storageLocation, "fridge") = ?';
      whereArgs.add(storageLocation);
    }
    await db.delete('items', where: where, whereArgs: whereArgs);
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
    this.defaultLocation = StorageLocation.fridge,
    this.isHomemade = 1,
  });

  final int? id;
  final String barcode;
  final String name;
  final double price;
  final String createdAt;
  final int? categoryId;

  /// Days between adding and expiry last time; used to pre-fill re-scans.
  final int? defaultShelfDays;

  /// Default storage location: 'fridge', 'freezer', 'pantry'
  final String defaultLocation;

  /// 1 = homemade, 0 = store bought
  final int isHomemade;

  Map<String, dynamic> toMap() => {
    'id': id,
    'barcode': barcode,
    'name': name,
    'price': price,
    'categoryId': categoryId,
    'defaultShelfDays': defaultShelfDays,
    'defaultLocation': defaultLocation,
    'isHomemade': isHomemade,
    'createdAt': createdAt,
  }..removeWhere((key, value) => key == 'id' && value == null);

  factory ProductRecord.fromMap(Map<String, dynamic> map) => ProductRecord(
    id: map['id'] as int?,
    barcode: map['barcode'] as String,
    name: map['name'] as String,
    price: (map['price'] as num).toDouble(),
    categoryId: map['categoryId'] as int?,
    defaultShelfDays: map['defaultShelfDays'] as int?,
    defaultLocation: map['defaultLocation'] as String? ?? StorageLocation.fridge,
    isHomemade: map['isHomemade'] as int? ?? 1,
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
    this.storageLocation = StorageLocation.fridge,
    this.cookedDate,
    this.portionCount = 1,
    this.isHomemade = 1,
    this.notes,
    required this.finished,
    required this.createdAt,
  });

  final int? id;
  final int productId;
  final int? categoryId;
  final String purchaseDate;
  final String entryDate;
  final String expiryDate;
  final String storageLocation;
  final String? cookedDate;
  final int portionCount;
  final int isHomemade;
  final String? notes;
  final int finished;
  final String createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'productId': productId,
    'categoryId': categoryId,
    'purchaseDate': purchaseDate,
    'entryDate': entryDate,
    'expiryDate': expiryDate,
    'storageLocation': storageLocation,
    'cookedDate': cookedDate,
    'portionCount': portionCount,
    'isHomemade': isHomemade,
    'notes': notes,
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
        storageLocation:
            map['storageLocation'] as String? ?? StorageLocation.fridge,
        cookedDate: map['cookedDate'] as String?,
        portionCount: map['portionCount'] as int? ?? 1,
        isHomemade: map['isHomemade'] as int? ?? 1,
        notes: map['notes'] as String?,
        finished: map['finished'] as int? ?? 0,
        createdAt: map['createdAt'] as String,
      );
}
