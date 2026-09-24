import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob banner + interstitial. Currently on Google's public TEST ad unit
/// IDs — swap in real unit IDs from the AdMob console before publishing
/// (and set the ADMOB_APP_ID GitHub secret, see README.md).
///
/// `google_mobile_ads` only supports Android/iOS, so everything here is a
/// no-op on web — keeps `flutter run -d chrome` usable for previewing.
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  static String get bannerAdUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-3940256099942544/6300978111';

  static String get interstitialAdUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-3940256099942544/1033173712';

  InterstitialAd? _interstitialAd;
  int _eventsSinceInterstitial = 0;

  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await MobileAds.instance.initialize();
      _loadInterstitial();
    } catch (_) {
      // Ads failing must never block the game.
    }
  }

  BannerAd? createBannerAd({required void Function() onLoaded}) {
    if (kIsWeb) return null;
    final banner = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded(),
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    banner.load();
    return banner;
  }

  void _loadInterstitial() {
    if (kIsWeb) return;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (_) => _interstitialAd = null,
      ),
    );
  }

  /// Call at natural breaks only (level complete, leaving a level, endless
  /// game over) — never mid-attempt. Shows at most every other break.
  void maybeShowInterstitial() {
    if (kIsWeb) return;
    _eventsSinceInterstitial++;
    if (_eventsSinceInterstitial < 2 || _interstitialAd == null) {
      if (_interstitialAd == null) _loadInterstitial();
      return;
    }
    _eventsSinceInterstitial = 0;
    final ad = _interstitialAd!;
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    ad.show();
  }
}
