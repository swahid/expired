import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Service to track Daily Active Users (DAU), Monthly Active Users (MAU),
/// and screen page visits via Firebase Analytics.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  FirebaseAnalyticsObserver? _observer;

  bool _initialized = false;

  /// Initializes Firebase Analytics safely.
  Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;

    try {
      if (Firebase.apps.isNotEmpty) {
        _analytics = FirebaseAnalytics.instance;
        _observer = FirebaseAnalyticsObserver(analytics: _analytics!);
        _initialized = true;
      }
    } catch (e) {
      debugPrint('[Analytics] Firebase Analytics offline or not configured yet: $e');
    }
  }

  FirebaseAnalyticsObserver? get navigatorObserver => _observer;

  /// Logs page / screen visits (e.g. dashboard, scanner, paywall).
  Future<void> logScreen(String screenName) async {
    if (_analytics != null) {
      try {
        await _analytics!.logScreenView(screenName: screenName);
      } catch (_) {}
    } else if (kDebugMode) {
      debugPrint('[Analytics Screen] $screenName');
    }
  }

  /// Logs when a food item is added.
  Future<void> logFoodAdded({
    required String storageLocation,
    required bool isHomemade,
    required int daysUntilExpiry,
  }) async {
    if (_analytics != null) {
      try {
        await _analytics!.logEvent(
          name: 'food_added',
          parameters: {
            'storage_location': storageLocation,
            'is_homemade': isHomemade ? 1 : 0,
            'days_until_expiry': daysUntilExpiry,
          },
        );
      } catch (_) {}
    } else if (kDebugMode) {
      debugPrint('[Analytics Event] food_added (location: $storageLocation, homemade: $isHomemade)');
    }
  }

  /// Logs when food is finished (marked used or wasted).
  Future<void> logFoodFinished({
    required String reason,
    required int daysLeft,
  }) async {
    if (_analytics != null) {
      try {
        await _analytics!.logEvent(
          name: 'food_finished',
          parameters: {
            'finish_reason': reason,
            'days_left': daysLeft,
          },
        );
      } catch (_) {}
    } else if (kDebugMode) {
      debugPrint('[Analytics Event] food_finished ($reason, daysLeft: $daysLeft)');
    }
  }

  /// Logs when frozen food is thawed to the fridge.
  Future<void> logFoodThawed() async {
    if (_analytics != null) {
      try {
        await _analytics!.logEvent(name: 'food_thawed_to_fridge');
      } catch (_) {}
    } else if (kDebugMode) {
      debugPrint('[Analytics Event] food_thawed_to_fridge');
    }
  }

  /// Logs Google Drive backup or restore actions.
  Future<void> logDriveSync({required bool isBackup, required bool success}) async {
    if (_analytics != null) {
      try {
        await _analytics!.logEvent(
          name: isBackup ? 'drive_backup' : 'drive_restore',
          parameters: {'success': success ? 1 : 0},
        );
      } catch (_) {}
    } else if (kDebugMode) {
      debugPrint('[Analytics Event] drive_${isBackup ? "backup" : "restore"} (success: $success)');
    }
  }

  /// Logs when user upgrades to Pro.
  Future<void> logProUpgrade() async {
    if (_analytics != null) {
      try {
        await _analytics!.logEvent(name: 'pro_upgrade_success');
      } catch (_) {}
    } else if (kDebugMode) {
      debugPrint('[Analytics Event] pro_upgrade_success');
    }
  }
}

