const connectionErrorMessage =
    'Erreur de connexion. Vérifiez votre connexion internet, puis réessayez.';

String userFacingErrorMessage(Object error, {String? prefix}) {
  final rawMessage = error.toString().trim();
  final message = _cleanErrorMessage(rawMessage);
  final haystack = '$rawMessage $message'.toLowerCase();

  if (_looksLikeConnectionError(haystack)) {
    return connectionErrorMessage;
  }

  if (_looksLikeTaxpayerLinkRuleError(haystack)) {
    return 'La base Supabase doit etre migree pour accepter une reference contribuable sans profil. Appliquez la migration 20260527103000_allow_collection_identifier_without_profile.sql.';
  }

  final fallback = message.isEmpty
      ? 'Une erreur est survenue. Veuillez reessayer.'
      : message;
  final cleanPrefix = prefix?.trim();
  if (cleanPrefix == null || cleanPrefix.isEmpty) {
    return fallback;
  }
  return '$cleanPrefix : $fallback';
}

String _cleanErrorMessage(String message) {
  var cleaned = message;
  const prefixes = ['Exception: ', 'Bad state: ', 'Invalid argument(s): '];
  for (final prefix in prefixes) {
    if (cleaned.startsWith(prefix)) {
      cleaned = cleaned.substring(prefix.length).trim();
    }
  }

  final supabaseMatch = RegExp(
    r'^(?:AuthException|PostgrestException|StorageException|FunctionException)\(message: ([^,)]+)',
  ).firstMatch(cleaned);
  if (supabaseMatch != null) {
    return supabaseMatch.group(1)?.trim() ?? cleaned;
  }

  return cleaned;
}

bool _looksLikeConnectionError(String message) {
  const markers = [
    'failed to fetch',
    'networkerror',
    'network error',
    'xmlhttprequest error',
    'socketexception',
    'clientexception',
    'failed host lookup',
    'host lookup',
    'no address associated with hostname',
    'network is unreachable',
    'software caused connection abort',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection terminated',
    'connection timed out',
    'timed out',
    'timeout',
    'connection failed',
    'unable to connect',
    'internetdisconnected',
    'err_internet_disconnected',
    'could not resolve host',
    'name or service not known',
    'impossible de joindre',
    'offline',
  ];
  return markers.any(message.contains);
}

bool _looksLikeTaxpayerLinkRuleError(String message) {
  return message.contains('collections_taxpayer_link_rule') ||
      message.contains('collection tax payer link rules') ||
      (message.contains('taxpayer_profile_id') &&
          message.contains('taxpayer_identifier') &&
          message.contains('violates'));
}
