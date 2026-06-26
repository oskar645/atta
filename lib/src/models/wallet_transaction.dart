class WalletTransaction {
  final String id;
  final String userId;
  final String walletId;
  final String type;
  final int amount;
  final String reason;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.walletId,
    required this.type,
    required this.amount,
    required this.reason,
    required this.metadata,
    required this.createdAt,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? map['userId'] ?? '').toString(),
      walletId: (map['wallet_id'] ?? map['walletId'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      amount: (map['amount'] ?? 0) is num ? (map['amount'] as num).toInt() : 0,
      reason: (map['reason'] ?? '').toString(),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
      createdAt: DateTime.tryParse(
            (map['created_at'] ?? map['createdAt'] ?? '').toString(),
          ) ??
          DateTime.now(),
    );
  }
}
