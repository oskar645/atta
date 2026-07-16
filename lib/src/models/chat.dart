// lib/src/models/chat.dart
class Chat {
  final String id;

  final String listingId;
  final String listingTitle;
  final String listingPhotoUrl;

  final String buyerId;
  final String sellerId;
  final String buyerName;
  final String sellerName;
  final String buyerAvatar;
  final String sellerAvatar;

  final String lastMessage;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int unreadCount;
  final int unreadForBuyer;
  final int unreadForSeller;

  Chat({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    this.listingPhotoUrl = '',
    required this.buyerId,
    required this.sellerId,
    this.buyerName = '',
    this.sellerName = '',
    this.buyerAvatar = '',
    this.sellerAvatar = '',
    required this.lastMessage,
    required this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
    this.unreadCount = 0,
    required this.unreadForBuyer,
    required this.unreadForSeller,
  });

  String otherUserId(String myUid) {
    if (myUid == buyerId) return sellerId;
    return buyerId;
  }

  int unreadFor(String myUid) {
    if (unreadCount > 0) return unreadCount;
    if (myUid == buyerId) return unreadForBuyer;
    if (myUid == sellerId) return unreadForSeller;
    return 0;
  }

  String otherUserName(String myUid) {
    if (myUid == buyerId) return sellerName;
    return buyerName;
  }

  String otherUserAvatar(String myUid) {
    if (myUid == buyerId) return sellerAvatar;
    return buyerAvatar;
  }

  static DateTime _parseDt(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  static DateTime? _parseNullableDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static String _pickListingPhotoUrl(Map<String, dynamic> listingPreview) {
    final direct = [
      listingPreview['photo_url'],
      listingPreview['photoUrl'],
      listingPreview['main_photo'],
      listingPreview['mainPhoto'],
    ];
    for (final candidate in direct) {
      final text = (candidate ?? '').toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }

    final photoUrls =
        listingPreview['photo_urls'] ?? listingPreview['photoUrls'];
    if (photoUrls is List) {
      for (final candidate in photoUrls) {
        final text = (candidate ?? '').toString().trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }

    final photoItems =
        listingPreview['photo_items'] ?? listingPreview['photoItems'];
    if (photoItems is List) {
      for (final item in photoItems) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final text = (map['url'] ?? map['public_url'] ?? map['publicUrl'] ?? '')
            .toString()
            .trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }

    return '';
  }

  factory Chat.fromMap(Map<String, dynamic> row) {
    final listingPreview = row['listingPreview'] is Map
        ? Map<String, dynamic>.from(row['listingPreview'] as Map)
        : row['listing_preview'] is Map
            ? Map<String, dynamic>.from(row['listing_preview'] as Map)
            : const <String, dynamic>{};
    final buyerPreview = row['buyerPreview'] is Map
        ? Map<String, dynamic>.from(row['buyerPreview'] as Map)
        : row['buyer_preview'] is Map
            ? Map<String, dynamic>.from(row['buyer_preview'] as Map)
            : const <String, dynamic>{};
    final sellerPreview = row['sellerPreview'] is Map
        ? Map<String, dynamic>.from(row['sellerPreview'] as Map)
        : row['seller_preview'] is Map
            ? Map<String, dynamic>.from(row['seller_preview'] as Map)
            : const <String, dynamic>{};

    final unreadRaw = row['unread_count'] ?? row['unreadCount'];

    return Chat(
      id: (row['id'] ?? '').toString(),
      listingId:
          (row['listing_id'] ?? row['listingId'] ?? listingPreview['id'] ?? '')
              .toString(),
      listingTitle: (row['listing_title'] ??
              row['listingTitle'] ??
              listingPreview['title'] ??
              '')
          .toString(),
      listingPhotoUrl: _pickListingPhotoUrl(listingPreview),
      buyerId: (row['buyer_id'] ?? row['buyerId'] ?? '').toString(),
      sellerId: (row['seller_id'] ?? row['sellerId'] ?? '').toString(),
      buyerName: (buyerPreview['display_name'] ??
              buyerPreview['displayName'] ??
              row['buyer_name'] ??
              '')
          .toString(),
      sellerName: (sellerPreview['display_name'] ??
              sellerPreview['displayName'] ??
              row['seller_name'] ??
              '')
          .toString(),
      buyerAvatar: (buyerPreview['avatar_url'] ??
              buyerPreview['avatarUrl'] ??
              row['buyer_avatar'] ??
              '')
          .toString(),
      sellerAvatar: (sellerPreview['avatar_url'] ??
              sellerPreview['avatarUrl'] ??
              row['seller_avatar'] ??
              '')
          .toString(),
      lastMessage: (row['last_message'] ?? row['lastMessage'] ?? '').toString(),
      lastMessageAt:
          _parseNullableDt(row['last_message_at'] ?? row['lastMessageAt']),
      createdAt: _parseDt(row['created_at'] ?? row['createdAt']),
      updatedAt: _parseDt(row['updated_at'] ?? row['updatedAt']),
      unreadCount: (unreadRaw as num?)?.toInt() ?? 0,
      unreadForBuyer: (row['unread_for_buyer'] as num?)?.toInt() ?? 0,
      unreadForSeller: (row['unread_for_seller'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'listing_id': listingId,
      'listing_title': listingTitle,
      'listing_preview': {
        'id': listingId,
        'title': listingTitle,
        'photo_url': listingPhotoUrl,
      },
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'buyer_preview': {
        'id': buyerId,
        'display_name': buyerName,
        'avatar_url': buyerAvatar,
      },
      'seller_preview': {
        'id': sellerId,
        'display_name': sellerName,
        'avatar_url': sellerAvatar,
      },
      'last_message': lastMessage,
      'last_message_at': lastMessageAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'unread_count': unreadCount,
      'unread_for_buyer': unreadForBuyer,
      'unread_for_seller': unreadForSeller,
    };
  }
}
