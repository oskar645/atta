import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/models/wallet_transaction.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/wallet_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';

void _debugWalletLog(String message) {
  assert(() {
    // ignore: avoid_print
    print(message);
    return true;
  }());
}

class WalletService {
  WalletService({
    WalletApi? api,
  }) : _api = api ?? WalletApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);

  final WalletApi _api;
  String? _activeUserId;
  bool _checkedAccrualThisSession = false;
  final Map<String, Wallet> _walletCache = <String, Wallet>{};
  final Map<String, List<WalletTransaction>> _transactionsCache =
      <String, List<WalletTransaction>>{};
  final Map<String, Future<Wallet>> _accrualFutures =
      <String, Future<Wallet>>{};
  final Map<String, Future<Wallet>> _walletFutures = <String, Future<Wallet>>{};
  final Map<String, Future<List<WalletTransaction>>> _transactionsFutures =
      <String, Future<List<WalletTransaction>>>{};
  bool _lastAccrualAwarded = false;

  bool get lastAccrualAwarded => _lastAccrualAwarded;
  Wallet? get cachedWallet {
    final userId = _currentUserId;
    if (userId == null) {
      return null;
    }
    return _walletCache[userId];
  }

  List<WalletTransaction> get cachedTransactions {
    final userId = _currentUserId;
    if (userId == null) {
      return const <WalletTransaction>[];
    }
    return _transactionsCache[userId] ?? const <WalletTransaction>[];
  }

  void updateCachedBalance(int balance) {
    final userId = _currentUserId;
    final cached = userId == null ? null : _walletCache[userId];
    if (userId == null || cached == null) return;
    _walletCache[userId] = Wallet(
      balance: balance,
      maxBalance: cached.maxBalance,
      welcomeBonus: cached.welcomeBonus,
      dailyBonusAmount: cached.dailyBonusAmount,
      lastDailyBonusAt: cached.lastDailyBonusAt,
      canClaimDailyBonus: cached.canClaimDailyBonus,
      nextDailyBonusAt: cached.nextDailyBonusAt,
      lastBonusAccrualAt: cached.lastBonusAccrualAt,
      nextAccrualAt: cached.nextAccrualAt,
      daysUntilNextAccrual: cached.daysUntilNextAccrual,
      secondsUntilNextAccrual: cached.secondsUntilNextAccrual,
    );
  }

  String? get _currentUserId {
    final normalized = _activeUserId?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void activateSession(String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) return;
    if (_activeUserId == normalized) return;
    _activeUserId = normalized;
    _checkedAccrualThisSession = false;
  }

  void resetSession() {
    _activeUserId = null;
    _checkedAccrualThisSession = false;
  }

  Future<Wallet?> maybeCheckAccrualOncePerSession() async {
    if (!ApiConfig.useTimewebBackend) {
      return cachedWallet;
    }
    final userId = _currentUserId;
    if (userId == null) {
      return cachedWallet;
    }
    final inFlight = _accrualFutures[userId];
    if (inFlight != null) {
      try {
        return await inFlight;
      } catch (_) {
        return _walletCache[userId];
      }
    }
    if (_checkedAccrualThisSession) {
      final cached = _walletCache[userId];
      return cached ?? await getWallet();
    }
    _checkedAccrualThisSession = true;
    final future = _fetchAccrualWallet(userId);
    _accrualFutures[userId] = future;
    try {
      final wallet = await future;
      return wallet;
    } catch (_) {
      return _walletCache[userId];
    } finally {
      if (identical(_accrualFutures[userId], future)) {
        _accrualFutures.remove(userId);
      }
    }
  }

  Future<Wallet> getWallet({bool forceRefresh = false}) async {
    if (!ApiConfig.useTimewebBackend) {
      return cachedWallet ??
          const Wallet(
            balance: 0,
            maxBalance: 0,
            welcomeBonus: 500,
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
    final userId = _currentUserId;
    if (userId == null) {
      return cachedWallet ??
          const Wallet(
            balance: 0,
            maxBalance: 0,
            welcomeBonus: 500,
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
    final cached = _walletCache[userId];
    if (!forceRefresh && cached != null) {
      return cached;
    }

    final existing = _walletFutures[userId];
    if (existing != null) {
      return await existing;
    }

    final future = _fetchWallet(userId);
    _walletFutures[userId] = future;
    try {
      return await future;
    } finally {
      if (identical(_walletFutures[userId], future)) {
        _walletFutures.remove(userId);
      }
    }
  }

  Future<List<WalletTransaction>> getTransactions(
      {bool forceRefresh = false}) async {
    if (!ApiConfig.useTimewebBackend) return const <WalletTransaction>[];
    final userId = _currentUserId;
    if (userId == null) {
      return const <WalletTransaction>[];
    }
    final cached = _transactionsCache[userId];
    if (!forceRefresh && cached != null) {
      return List<WalletTransaction>.from(cached);
    }
    final existing = _transactionsFutures[userId];
    if (existing != null) {
      return await existing;
    }
    final future = _fetchTransactions(userId);
    _transactionsFutures[userId] = future;
    try {
      return await future;
    } finally {
      if (identical(_transactionsFutures[userId], future)) {
        _transactionsFutures.remove(userId);
      }
    }
  }

  Future<Wallet> checkAccrual({bool forceRefresh = false}) async {
    if (!ApiConfig.useTimewebBackend) {
      return getWallet(forceRefresh: forceRefresh);
    }
    final userId = _currentUserId;
    if (userId == null) {
      return getWallet(forceRefresh: forceRefresh);
    }
    if (!forceRefresh) {
      final cached = _walletCache[userId];
      if (cached != null) {
        return cached;
      }
    }
    final existing = _accrualFutures[userId];
    if (existing != null) {
      return await existing;
    }
    final future = _fetchAccrualWallet(userId);
    _accrualFutures[userId] = future;
    try {
      return await future;
    } finally {
      if (identical(_accrualFutures[userId], future)) {
        _accrualFutures.remove(userId);
      }
    }
  }

  Future<Wallet> _fetchWallet(String userId) async {
    _debugWalletLog('Wallet refresh start user=$userId');
    try {
      final response = await _api.getWallet();
      final wallet = Wallet.fromMap(response);
      _walletCache[userId] = wallet;
      _debugWalletLog(
        'Wallet refresh success balance=${wallet.balance} user=$userId',
      );
      return wallet;
    } catch (error) {
      _debugWalletLog('Wallet refresh error message=$error user=$userId');
      rethrow;
    } finally {
      _debugWalletLog('Wallet finally loading=false user=$userId');
    }
  }

  Future<List<WalletTransaction>> _fetchTransactions(String userId) async {
    final response = await _api.getTransactions();
    final walletMap = response['wallet'];
    if (walletMap is Map) {
      _walletCache[userId] = Wallet.fromMap(
        walletMap.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    final items = response['items'];
    if (items is! List) return const <WalletTransaction>[];
    final transactions = items
        .whereType<Map>()
        .map(
          (item) => WalletTransaction.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
    _transactionsCache[userId] = transactions;
    return transactions;
  }

  Future<Wallet> _fetchAccrualWallet(String userId) async {
    _debugWalletLog('Wallet accrue check start user=$userId');
    try {
      final response = await _api.checkAccrual();
      _lastAccrualAwarded = response['awarded'] == true;
      final walletMap = response['wallet'];
      final normalized = walletMap is Map
          ? walletMap.map((key, value) => MapEntry(key.toString(), value))
          : response;
      final wallet = Wallet.fromMap(Map<String, dynamic>.from(normalized));
      _walletCache[userId] = wallet;
      _debugWalletLog(
        'Wallet accrue check success balance=${wallet.balance} user=$userId',
      );
      return wallet;
    } catch (error) {
      _lastAccrualAwarded = false;
      _debugWalletLog('Wallet refresh error message=$error user=$userId');
      rethrow;
    } finally {
      _debugWalletLog('Wallet finally loading=false user=$userId');
    }
  }
}
