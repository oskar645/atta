// TODO: Replace with the exact App Store URL when the production app id is known.
const String appInstallUrl = 'https://apps.apple.com/search?term=ATTA';
const String _appInstallUrlPlaceholder =
    'PASTE_APP_STORE_OR_TESTFLIGHT_LINK_HERE';

String? resolveConfiguredAppInstallUrl({String? overrideUrl}) {
  final rawCandidate = (overrideUrl ?? appInstallUrl).trim();
  final candidate =
      rawCandidate == _appInstallUrlPlaceholder ? appInstallUrl : rawCandidate;
  if (candidate.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.scheme != 'https' || uri.host.trim().isEmpty) {
    return null;
  }

  return candidate;
}
