import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdService {
  static final RewardedAdService _instance = RewardedAdService._internal();
  factory RewardedAdService() => _instance;
  RewardedAdService._internal();

  RewardedAd? _rewardedAd;
  bool _isLoaded = false;

  // ID Real do Bloco de Anúncio Premiado
  final String adUnitId = Platform.isAndroid
      ? 'ca-app-pub-7215014769653180/8232114352'
      : 'ca-app-pub-3940256099942544/1712485313'; // Troque pelo ID de iOS real se tiver

  void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('RewardedAd loaded.');
          _rewardedAd = ad;
          _isLoaded = true;

          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isLoaded = false;
              loadRewardedAd(); // Recarrega para o próximo uso
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _isLoaded = false;
              loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd failed to load: $error');
          _isLoaded = false;
        },
      ),
    );
  }

  void showRewardedAd({required void Function(AdWithoutView, RewardItem) onUserEarnedReward}) {
    if (_isLoaded && _rewardedAd != null) {
      _rewardedAd!.show(onUserEarnedReward: onUserEarnedReward);
    } else {
      debugPrint('RewardedAd not loaded yet.');
      loadRewardedAd(); // Tenta carregar se não estiver carregado
    }
  }

  bool get isAdLoaded => _isLoaded;
}
