// lib/config/build_config.dart

/// クローズドテスト用に、全ユーザーを強制プレミアム扱いにするフラグ。
/// ビルド時に `--dart-define=FREE_PREMIUM=true` を付けたときだけ true。
const bool kFreePremiumForClosedTest =
    bool.fromEnvironment('FREE_PREMIUM', defaultValue: false);
