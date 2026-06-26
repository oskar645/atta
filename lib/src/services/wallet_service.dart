import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/models/wallet_transaction.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/wallet_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';

class WalletService {
  WalletService() : _api = WalletApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);

  final WalletApi _api;
  String? _activeUserId;
  bool _checkedAccrualThisSession = false;
  Wallet? _cachedWallet;
  Future<Wallet>? _accrualFuture;
  Future<Wallet>? _walletFuture;
  Future<List<WalletTransaction>>? _transactionsFuture;
  static const Duration _walletTimeout = Duration(seconds: 10);

  Wallet? get cachedWallet => _cachedWallet;

  void activateSession(String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) return;
    if (_activeUserId == normalized) return;
    _activeUserId = normalized;
    _checkedAccrualThisSession = false;
    _cachedWallet = null;
    _accrualFuture = null;
    _walletFuture = null;
    _transactionsFuture = null;
  }

  void resetSession() {
    _activeUserId = null;
    _checkedAccrualThisSession = false;
    _cachedWallet = null;
    _accrualFuture = null;
    _walletFuture = null;
    _transactionsFuture = null;
  }

  Future<Wallet?> maybeCheckAccrualOncePerSession() async {
    if (!ApiConfig.useTimewebBackend) {
      return _cachedWallet;
    }
    final inFlight = _accrualFuture;
    if (inFlight != null) {
      try {
        return await inFlight;
      } catch (_) {
        return _cachedWallet;
      }
    }
    if (_checkedAccrualThisSession) {
      return _cachedWallet;
    }
    _checkedAccrualThisSession = true;
    final future = _fetchAccrualWallet();
    _accrualFuture = future;
    try {
      return await future;
    } catch (_) {
      return _cachedWallet;
    } finally {
      if (identical(_accrualFuture, future)) {
        _accrualFuture = null;
      }
    }
  }

  Future<Wallet> getWallet() async {
    if (!ApiConfig.useTimewebBackend) {
      return _cachedWallet ??
          const Wallet(
            balance: 0,
            maxBalance: 1000,
            welcomeBonus: 100,
            dailyBonusAmount: 25,
            lastDailyBonusAt: null,
            canClaimDailyBonus: true,
            nextDailyBonusAt: null,
            lastBonusAccrualAt: null,
            nextAccrualAt: null,
            daysUntilNextAccrual: 0,
            secondsUntilNextAccrual: 0,
          );
    }

    final existing = _walletFuture;
    if (existing != null) {
      return existing;
    }

    final future = _fetchWallet();
    _walletFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_walletFuture, future)) {
        _walletFuture = null;
      }
    }
  }

  Future<List<WalletTransaction>> getTransactions() async {
    if (!ApiConfig.useTimewebBackend) return const <WalletTransaction>[];
    final existing = _transactionsFuture;
    if (existing != null) {
      return existing;
    }
    final future = _fetchTransactions();
    _transactionsFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_transactionsFuture, future)) {
        _transactionsFuture = null;
      }
    }
  }

  Future<Wallet> checkAccrual() async {
    if (!ApiConfig.useTimewebBackend) {
      return getWallet();
    }
    final existing = _accrualFuture;
    if (existing != null) {
      return existing;
    }
    final future = _fetchAccrualWallet();
    _accrualFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_accrualFuture, future)) {
        _accrualFuture = null;
      }
    }
  }

  Future<Wallet> _fetchWallet() async {
    final response = await _withTimeout(_api.getWallet());
    final wallet = Wallet.fromMap(response);
    _cachedWallet = wallet;
    return wallet;
  }

  Future<List<WalletTransaction>> _fetchTransactions() async {
    final response = await _withTimeout(_api.getTransactions());
    final walletMap = response['wallet'];
    if (walletMap is Map) {
      _cachedWallet = Wallet.fromMap(
        walletMap.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    final items = response['items'];
    if (items is! List) return const <WalletTransaction>[];
    return items
        .whereType<Map>()
        .map(
          (item) => WalletTransaction.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<Wallet> _fetchAccrualWallet() async {
    final response = await _withTimeout(_api.checkAccrual());
    final walletMap = response['wallet'];
    final normalized = walletMap is Map
        ? walletMap.map((key, value) => MapEntry(key.toString(), value))
        : response;
    final wallet = Wallet.fromMap(Map<String, dynamic>.from(normalized));
    _cachedWallet = wallet;
    return wallet;
  }

  Future<T> _withTimeout<T>(Future<T> future) {
    return future.timeout(
      _walletTimeout,
      onTimeout: () => throw const ApiException(
        'Не удалось загрузить кошелёк. Проверьте интернет или VPN.',
        code: 'timeout',
      ),
    );
  }
}
