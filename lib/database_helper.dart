import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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
      await _seedDefaultCategories(db);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE product (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        volume TEXT NOT NULL DEFAULT '',
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
        finished INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (productId) REFERENCES product(id) ON DELETE CASCADE,
        FOREIGN KEY (categoryId) REFERENCES category(id) ON DELETE SET NULL
      )
    ''');

    await _seedDefaultCategories(db);
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final defaultCategories = [
      {'name': 'Dairy', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Bakery', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Beverages', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Snacks', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Frozen', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Household', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Grains', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Meat & Seafood', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Produce', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Canned Goods', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Pantry', 'createdAt': '2026-06-12T00:00:00.000'},
      {'name': 'Deli', 'createdAt': '2026-06-12T00:00:00.000'},
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

  Future<void> deleteProduct(int productId) async => _withRetry((db) async {
    await db.delete('items', where: 'productId = ?', whereArgs: [productId]);
    await db.delete('product', where: 'id = ?', whereArgs: [productId]);
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
    required this.volume,
    required this.createdAt,
  });

  final int? id;
  final String barcode;
  final String name;
  final double price;
  final String volume;
  final String createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'barcode': barcode,
    'name': name,
    'price': price,
    'volume': volume,
    'createdAt': createdAt,
  }..removeWhere((key, value) => key == 'id' && value == null);

  factory ProductRecord.fromMap(Map<String, dynamic> map) => ProductRecord(
    id: map['id'] as int?,
    barcode: map['barcode'] as String,
    name: map['name'] as String,
    price: (map['price'] as num).toDouble(),
    volume: map['volume'] as String? ?? '',
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
    required this.finished,
    required this.createdAt,
  });

  final int? id;
  final int productId;
  final int? categoryId;
  final String purchaseDate;
  final String entryDate;
  final int finished;
  final String createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'productId': productId,
    'categoryId': categoryId,
    'purchaseDate': purchaseDate,
    'entryDate': entryDate,
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
        finished: map['finished'] as int? ?? 0,
        createdAt: map['createdAt'] as String,
      );
}
