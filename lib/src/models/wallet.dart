class Wallet {
  final int balance;
  final int maxBalance;
  final int welcomeBonus;
  final int dailyBonusAmount;
  final DateTime? lastDailyBonusAt;
  final bool canClaimDailyBonus;
  final DateTime? nextDailyBonusAt;
  final DateTime? lastBonusAccrualAt;
  final DateTime? nextAccrualAt;
  final int daysUntilNextAccrual;
  final int secondsUntilNextAccrual;

  const Wallet({
    required this.balance,
    required this.maxBalance,
    required this.welcomeBonus,
    required this.dailyBonusAmount,
    required this.lastDailyBonusAt,
    required this.canClaimDailyBonus,
    required this.nextDailyBonusAt,
    required this.lastBonusAccrualAt,
    required this.nextAccrualAt,
    required this.daysUntilNextAccrual,
    required this.secondsUntilNextAccrual,
  });

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  factory Wallet.fromMap(Map<String, dynamic> map) {
    return Wallet(
      balance:
          (map['balance'] ?? 0) is num ? (map['balance'] as num).toInt() : 0,
      maxBalance: (map['maxBalance'] ?? map['max_balance'] ?? 0) is num
          ? ((map['maxBalance'] ?? map['max_balance'] ?? 0) as num).toInt()
          : 0,
      welcomeBonus: (map['welcomeBonus'] ?? map['welcome_bonus'] ?? 500) is num
          ? ((map['welcomeBonus'] ?? map['welcome_bonus'] ?? 500) as num)
              .toInt()
          : 500,
      dailyBonusAmount:
          (map['dailyBonusAmount'] ?? map['daily_bonus_amount'] ?? 25) is num
              ? ((map['dailyBonusAmount'] ?? map['daily_bonus_amount'] ?? 25)
                      as num)
                  .toInt()
              : 25,
      lastDailyBonusAt: _parseDate(
        map['lastDailyBonusAt'] ?? map['last_daily_bonus_at'],
      ),
      canClaimDailyBonus: map['canClaimDailyBonus'] == true ||
          map['can_claim_daily_bonus'] == true,
      nextDailyBonusAt:
          _parseDate(map['nextDailyBonusAt'] ?? map['next_daily_bonus_at']),
      lastBonusAccrualAt: _parseDate(
        map['lastBonusAccrualAt'] ??
            map['last_bonus_accrual_at'] ??
            map['lastDailyBonusAt'] ??
            map['last_daily_bonus_at'],
      ),
      nextAccrualAt: _parseDate(
        map['nextAccrualAt'] ??
            map['next_accrual_at'] ??
            map['nextDailyBonusAt'] ??
            map['next_daily_bonus_at'],
      ),
      daysUntilNextAccrual: (map['daysUntilNextAccrual'] ??
              map['days_until_next_accrual'] ??
              0) is num
          ? ((map['daysUntilNextAccrual'] ??
                  map['days_until_next_accrual'] ??
                  0) as num)
              .toInt()
          : 0,
      secondsUntilNextAccrual: (map['secondsUntilNextAccrual'] ??
              map['seconds_until_next_accrual'] ??
              0) is num
          ? ((map['secondsUntilNextAccrual'] ??
                  map['seconds_until_next_accrual'] ??
                  0) as num)
              .toInt()
          : 0,
    );
  }
}
