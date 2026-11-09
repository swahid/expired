import 'dart:convert';
import 'dart:io';
import 'package:expired/backup_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Privacy-First Google Drive Sync Service.
/// Backs up to the user's hidden Google Drive AppData folder.
/// The developer has zero access to user files, zero database liability, and zero hosting costs.
class DriveSyncService {
  DriveSyncService._();
  static final DriveSyncService instance = DriveSyncService._();

  static const _appDataScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _backupFileName = 'expired_backup_v3.json';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [_appDataScope],
  );

  final ValueNotifier<GoogleSignInAccount?> currentUser =
      ValueNotifier<GoogleSignInAccount?>(null);

  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier<DateTime?>(null);

  bool _initialized = false;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;
    _initialized = true;

    _googleSignIn.onCurrentUserChanged.listen((account) {
      currentUser.value = account;
    });

    try {
      await _googleSignIn.signInSilently();
    } catch (_) {
      // Offline or first launch
    }
  }

  /// Prompts Google Sign-In with Drive AppData scope.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      currentUser.value = account;
      return account;
    } catch (e) {
      debugPrint('[DriveSync] Sign in error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      currentUser.value = null;
    } catch (_) {}
  }

  /// Backs up local inventory JSON to user's private Google Drive AppData folder.
  Future<({bool success, String message})> backupToDrive() async {
    final account = currentUser.value ?? await signIn();
    if (account == null) {
      return (success: false, message: 'Google Sign-In required to back up.');
    }

    HttpClient? client;
    try {
      final authHeaders = await account.authHeaders;
      final jsonBackup = await LocalBackupHelper.instance.exportFullDataAsJson();

      client = HttpClient();

      // Check if existing backup file exists in AppData
      final existingFileId = await _findExistingFileId(authHeaders);

      final boundary = '-------ExpiredAppBoundary${DateTime.now().millisecondsSinceEpoch}';

      final metadata = jsonEncode({
        'name': _backupFileName,
        if (existingFileId == null) 'parents': ['appDataFolder'],
      });

      final bodyBuilder = BytesBuilder();
      bodyBuilder.add(utf8.encode('--$boundary\r\n'));
      bodyBuilder.add(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'));
      bodyBuilder.add(utf8.encode(metadata));
      bodyBuilder.add(utf8.encode('\r\n--$boundary\r\n'));
      bodyBuilder.add(utf8.encode('Content-Type: application/json\r\n\r\n'));
      bodyBuilder.add(utf8.encode(jsonBackup));
      bodyBuilder.add(utf8.encode('\r\n--$boundary--\r\n'));

      final bodyBytes = bodyBuilder.toBytes();

      final uri = existingFileId != null
          ? Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$existingFileId?uploadType=multipart')
          : Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');

      final request = existingFileId != null
          ? await client.patchUrl(uri)
          : await client.postUrl(uri);

      authHeaders.forEach((key, val) => request.headers.set(key, val));
      request.headers.set('Content-Type', 'multipart/related; boundary=$boundary');
      request.headers.set('Content-Length', bodyBytes.length.toString());

      request.add(bodyBytes);
      final response = await request.close();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final now = DateTime.now();
        lastSyncTime.value = now;
        return (success: true, message: 'Backed up to Google Drive successfully! ☁️');
      } else {
        return (success: false, message: 'Backup failed (${response.statusCode}).');
      }
    } catch (e) {
      return (success: false, message: 'Unable to connect to Google Drive: $e');
    } finally {
      client?.close(force: true);
    }
  }

  /// Restores food inventory from user's private Google Drive AppData folder.
  Future<({bool success, String message})> restoreFromDrive() async {
    final account = currentUser.value ?? await signIn();
    if (account == null) {
      return (success: false, message: 'Google Sign-In required to restore.');
    }

    HttpClient? client;
    try {
      final authHeaders = await account.authHeaders;
      final fileId = await _findExistingFileId(authHeaders);
      if (fileId == null) {
        return (success: false, message: 'No Expired backup found in this Google account.');
      }

      client = HttpClient();
      final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      final request = await client.getUrl(uri);
      authHeaders.forEach((key, val) => request.headers.set(key, val));

      final response = await request.close();
      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        final ok = await LocalBackupHelper.instance.importDataFromJson(content);
        if (ok) {
          return (success: true, message: 'All food data restored successfully! 🎉');
        } else {
          return (success: false, message: 'Backup format is incompatible.');
        }
      } else {
        return (success: false, message: 'Failed to download backup (${response.statusCode}).');
      }
    } catch (e) {
      return (success: false, message: 'Error restoring from Google Drive: $e');
    } finally {
      client?.close(force: true);
    }
  }

  Future<String?> _findExistingFileId(Map<String, String> authHeaders) async {
    HttpClient? client;
    try {
      client = HttpClient();
      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?spaces=appDataFolder'
        '&q=name%3D%27$_backupFileName%27%20and%20trashed%3Dfalse'
        '&fields=files(id%2Cname)',
      );
      final request = await client.getUrl(uri);
      authHeaders.forEach((key, val) => request.headers.set(key, val));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final files = json['files'] as List<dynamic>?;
        if (files != null && files.isNotEmpty) {
          return files.first['id'] as String?;
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}

