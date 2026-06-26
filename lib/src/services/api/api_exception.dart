class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final Object? details;

  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.details,
  });

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isServerUnavailable =>
      statusCode == 500 || statusCode == 503 || code == 'server_unavailable';
  bool get isTimeout => code == 'timeout';
  bool get isNetworkError => code == 'network';

  @override
  String toString() => message;
}
