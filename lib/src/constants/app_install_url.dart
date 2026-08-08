const String appInstallUrl =
    'https://apps.apple.com/us/app/atta/id6762604298?l=ru';
const String appInviteLandingUrl = 'https://attamarket.online/invite';
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

String? resolveConfiguredInviteShareUrl({String? overrideUrl}) {
  final overrideCandidate = overrideUrl?.trim() ?? '';
  if (overrideCandidate.isNotEmpty) {
    return resolveConfiguredAppInstallUrl(overrideUrl: overrideCandidate);
  }

  final inviteUri = Uri.tryParse(appInviteLandingUrl);
  if (inviteUri != null &&
      inviteUri.scheme == 'https' &&
      inviteUri.host.trim().isNotEmpty) {
    return appInviteLandingUrl;
  }

  return resolveConfiguredAppInstallUrl();
}
