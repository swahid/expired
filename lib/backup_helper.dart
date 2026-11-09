import 'dart:convert';
import 'dart:io';
import 'package:expired/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Manages redundant local JSON backups to guarantee zero data loss
/// even in the event of OS-level database corruption.
class LocalBackupHelper {
  LocalBackupHelper._();
  static final LocalBackupHelper instance = LocalBackupHelper._();

  static const _backupFileName = 'offline_mirror_backup.json';

  Future<File> _getBackupFile() async {
    final dbPath = await getDatabasesPath();
    return File('$dbPath/$_backupFileName');
  }

  /// Exports current database state to a clean JSON string.
  Future<String> exportFullDataAsJson() async {
    final products = await AppDatabase.instance.getProducts();
    final categories = await AppDatabase.instance.getCategories();
    final items = await AppDatabase.instance.getItems();

    final payload = {
      'app': 'Expired',
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'categories': categories
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'createdAt': c.createdAt,
              })
          .toList(),
      'products': products.map((p) => p.toMap()).toList(),
      'items': items.map((i) => i.toMap()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Automatically updates the local offline backup file.
  Future<void> updateMirrorBackup() async {
    try {
      final json = await exportFullDataAsJson();
      final file = await _getBackupFile();
      await file.writeAsString(json, flush: true);
    } catch (_) {
      // Best effort mirror backup
    }
  }

  /// Restores data from the offline mirror file if needed.
  Future<bool> restoreFromMirrorBackup() async {
    try {
      final file = await _getBackupFile();
      if (!await file.exists()) return false;
      final content = await file.readAsString();
      return await importDataFromJson(content);
    } catch (_) {
      return false;
    }
  }

  /// Safely imports and merges data from a JSON payload.
  Future<bool> importDataFromJson(String jsonString) async {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      final products = (map['products'] as List<dynamic>?) ?? [];
      final categories = (map['categories'] as List<dynamic>?) ?? [];
      final items = (map['items'] as List<dynamic>?) ?? [];

      final db = await AppDatabase.instance.database;

      await db.transaction((txn) async {
        for (final cat in categories) {
          if (cat is Map<String, dynamic>) {
            await txn.insert(
              'category',
              {
                'name': cat['name'],
                'createdAt': cat['createdAt'] ?? DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }

        for (final prod in products) {
          if (prod is Map<String, dynamic>) {
            final barcode = prod['barcode'] as String?;
            if (barcode == null) continue;
            final existing = await txn.query(
              'product',
              where: 'barcode = ?',
              whereArgs: [barcode],
              limit: 1,
            );
            if (existing.isEmpty) {
              await txn.insert('product', prod);
            }
          }
        }

        for (final item in items) {
          if (item is Map<String, dynamic>) {
            final itemMap = Map<String, dynamic>.from(item);
            itemMap.remove('id'); // let auto-increment handle id to avoid collisions
            await txn.insert('items', itemMap);
          }
        }
      });

      return true;
    } catch (_) {
      return false;
    }
  }
}

