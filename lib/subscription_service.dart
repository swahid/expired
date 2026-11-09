import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Manages Google Play billing and subscriptions via RevenueCat.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  /// REPLACE WITH YOUR REVENUECAT PUBLIC API KEYS:
  /// Get these from: https://app.revenuecat.com -> Project Settings -> API Keys
  static const String _androidApiKey = 'goog_YOUR_REVENUECAT_ANDROID_PUBLIC_KEY';
  static const String _iosApiKey = 'appl_YOUR_REVENUECAT_IOS_PUBLIC_KEY';

  /// Your RevenueCat Entitlement ID (typically "pro" or "premium")
  static const String entitlementId = 'pro';

  /// ValueNotifier holding whether the user currently has an active Pro subscription.
  /// Listen to this in UI to automatically hide ads and unlock features.
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  bool _initialized = false;

  /// Initializes RevenueCat SDK. Call once at app startup before runApp.
  Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;

    final apiKey = Platform.isAndroid ? _androidApiKey : _iosApiKey;
    if (apiKey.contains('YOUR_REVENUECAT')) {
      debugPrint('[RevenueCat] Placeholder API key detected. Add your real key to test real purchases.');
      return;
    }

    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }

      final configuration = PurchasesConfiguration(apiKey);
      await Purchases.configure(configuration);

      _initialized = true;

      // Check current customer entitlement status
      final customerInfo = await Purchases.getCustomerInfo();
      _updateEntitlementStatus(customerInfo);

      // Listen to real-time subscription changes (renewals, cancellations)
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        _updateEntitlementStatus(customerInfo);
      });
    } catch (e) {
      debugPrint('[RevenueCat] Initialization warning: $e');
    }
  }

  void _updateEntitlementStatus(CustomerInfo customerInfo) {
    final active = customerInfo.entitlements.all[entitlementId]?.isActive ?? false;
    isPro.value = active;
  }

  /// Fetches available packages (Monthly, Yearly, Lifetime) configured in RevenueCat.
  Future<Offerings?> getOfferings() async {
    if (!_initialized) {
      await init();
      if (!_initialized) return null;
    }

    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('[RevenueCat] Failed to fetch offerings: $e');
      return null;
    }
  }

  /// Purchases a selected package via Google Play Billing.
  Future<bool> purchasePackage(Package package) async {
    try {
      final customerInfo = await Purchases.purchasePackage(package);
      _updateEntitlementStatus(customerInfo);
      return isPro.value;
    } catch (e) {
      debugPrint('[RevenueCat] Purchase failed or cancelled: $e');
      return false;
    }
  }

  /// Restores previous purchases (e.g., when moving to a new phone).
  Future<bool> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      _updateEntitlementStatus(customerInfo);
      return isPro.value;
    } catch (e) {
      debugPrint('[RevenueCat] Restore failed: $e');
      return false;
    }
  }
}

