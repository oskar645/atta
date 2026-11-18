class MapListing {
  const MapListing({
    required this.id,
    required this.title,
    required this.price,
    required this.city,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.photoUrl,
    this.subcategory = '',
    this.dealType,
  });

  final String id;
  final String title;
  final int price;
  final String city;
  final String address;
  final double latitude;
  final double longitude;
  final String? photoUrl;
  final String subcategory;
  final String? dealType;

  String get locationLabel => address.trim().isNotEmpty ? address : city;

  factory MapListing.fromMap(Map<String, dynamic> map) => MapListing(
        id: (map['id'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        price: map['price'] is num
            ? (map['price'] as num).toInt()
            : int.tryParse((map['price'] ?? '').toString()) ?? 0,
        city: (map['city'] ?? '').toString(),
        address: (map['address'] ?? '').toString(),
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        photoUrl: map['photo_url']?.toString(),
        subcategory: (map['subcategory'] ?? '').toString(),
        dealType: map['deal_type']?.toString(),
      );
}
