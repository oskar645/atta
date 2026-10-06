final RegExp _listingLinkPattern = RegExp(
  r'(?:https?://(?:www\.)?attamarket\.online/listing/|atta://listing/)([^\s/?#]+)',
  caseSensitive: false,
);

String? extractListingIdFromMessage(String text) {
  final match = _listingLinkPattern.firstMatch(text);
  final encodedId = match?.group(1)?.trim() ?? '';
  if (encodedId.isEmpty) return null;

  try {
    final listingId = Uri.decodeComponent(encodedId).trim();
    return listingId.isEmpty ? null : listingId;
  } on FormatException {
    return null;
  }
}
