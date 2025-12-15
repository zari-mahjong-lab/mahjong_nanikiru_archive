import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class InterstitialAdService {
  InterstitialAd? _interstitialAd;
  bool _isLoading = false;

  InterstitialAdService._internal();
  static final InterstitialAdService instance = InterstitialAdService._internal();

  /// プラットフォーム別のテスト用 adUnitId
  /// TODO: リリース前に本番IDに差し替えてください
  static String get _adUnitId {
    if (Platform.isAndroid) {
      // Android テスト用
      return 'ca-app-pub-3940256099942544/1033173712';
    } else if (Platform.isIOS) {
      // iOS テスト用
      return 'ca-app-pub-3940256099942544/4411468910';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// インタースティシャル広告を事前にロード
  Future<void> preload() async {
    if (_isLoading || _interstitialAd != null) return;

    _isLoading = true;

    await InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (err) {
          _interstitialAd = null;
          _isLoading = false;
          // 必要ならここで debugPrint(err.toString());
        },
      ),
    );
  }

  /// 広告があれば表示して true を返す。なければ false。
  Future<bool> showIfAvailable() async {
    // まだロードされていなければ一度試す
    if (_interstitialAd == null) {
      await preload();
      if (_interstitialAd == null) {
        // ロード失敗
        return false;
      }
    }

    final ad = _interstitialAd;
    _interstitialAd = null; // 一度使ったら破棄しておく

    if (ad == null) return false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        // 次回用にプリロードしておく
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        // 失敗時も次を準備
        preload();
      },
    );

    // show() は同期メソッドなので、呼んだ時点で「表示した」とみなして true を返す
    ad.show();
    return true;
  }
}
