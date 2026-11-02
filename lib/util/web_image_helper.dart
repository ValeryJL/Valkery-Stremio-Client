import 'package:flutter/foundation.dart';

String resolveWebSafeImageUrl(String url) {
  if (url.isEmpty) return url;
  if (kIsWeb && (url.startsWith('http://') || url.startsWith('https://'))) {
    // Pass raw unencoded URL so Nginx proxy_pass $arg_url doesn't fail on %3A%2F%2F
    return '/img-proxy/?url=$url';
  }
  return url;
}
