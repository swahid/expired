import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Clean, adaptive bottom AdMob banner widget.
/// Gracefully collapses when offline or when no ad is available.
class BottomAdBanner extends StatefulWidget {
  const BottomAdBanner({super.key});

  /// REPLACE WITH YOUR REAL ADMOB BANNER UNIT ID WHEN PUBLISHING:
  /// Create this in https://admob.google.com -> Apps -> Ad Units -> Banner
  static const String _productionAndroidAdUnitId = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
  static const String _productionIosAdUnitId = 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';

  /// Standard Google Test Ad Unit IDs (guaranteed to work in testing)
  static const String _testAndroidAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testIosAdUnitId = 'ca-app-pub-3940256099942544/2934735716';

  static String get adUnitId {
    if (kDebugMode) {
      return Platform.isAndroid ? _testAndroidAdUnitId : _testIosAdUnitId;
    }
    // Return production ID if configured, otherwise fallback to test ID
    final prodId = Platform.isAndroid ? _productionAndroidAdUnitId : _productionIosAdUnitId;
    return prodId.contains('XXXX')
        ? (Platform.isAndroid ? _testAndroidAdUnitId : _testIosAdUnitId)
        : prodId;
  }

  @override
  State<BottomAdBanner> createState() => _BottomAdBannerState();
}

class _BottomAdBannerState extends State<BottomAdBanner> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    if (kIsWeb) return;

    _bannerAd = BannerAd(
      adUnitId: BottomAdBanner.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isAdLoaded = false;
          });
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdLoaded || _bannerAd == null) {
      // Minimal Pro upgrade teaser when ad is loading or offline
      return Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Ad',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Expired Pro · Go 100% Ad-Free',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: _bannerAd!.size.height.toDouble(),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      alignment: Alignment.center,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

