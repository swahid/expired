import 'dart:io';
import 'package:expired/subscription_service.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Manages AdMob interstitial full-page ads.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// REPLACE WITH YOUR REAL INTERSTITIAL AD UNIT ID WHEN PUBLISHING:
  /// Get this in https://admob.google.com -> Apps -> Ad Units -> Interstitial
  static const String _productionAndroidInterstitialId = 'ca-app-pub-2088829932165152/9767156218';
  static const String _productionIosInterstitialId = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';

  /// Standard Google Test Interstitial IDs
  static const String _testAndroidInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testIosInterstitialId = 'ca-app-pub-3940256099942544/4411468910';

  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid ? _testAndroidInterstitialId : _testIosInterstitialId;
    }
    final prodId = Platform.isAndroid ? _productionAndroidInterstitialId : _productionIosInterstitialId;
    return prodId.contains('XXXX')
        ? (Platform.isAndroid ? _testAndroidInterstitialId : _testIosInterstitialId)
        : prodId;
  }

  InterstitialAd? _interstitialAd;
  bool _isLoading = false;

  /// Preloads an interstitial ad in background.
  void preloadInterstitial() {
    if (kIsWeb) return;
    if (SubscriptionService.instance.isPro.value) return; // Pro users never load ads
    if (_interstitialAd != null || _isLoading) return;

    _isLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isLoading = false;
        },
      ),
    );
  }

  /// Shows full-page ad after a food item is saved.
  /// If the user is Pro, or if offline, it immediately calls [onComplete].
  void showInterstitialAfterEntry({VoidCallback? onComplete}) {
    // Pro subscribers are 100% ad-free
    if (SubscriptionService.instance.isPro.value) {
      onComplete?.call();
      return;
    }

    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
          preloadInterstitial(); // preload for next entry
          onComplete?.call();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          _interstitialAd = null;
          preloadInterstitial();
          onComplete?.call();
        },
      );
      _interstitialAd!.show();
    } else {
      // If ad was not ready, don't block user
      onComplete?.call();
      preloadInterstitial();
    }
  }
}
