import 'package:flutter/foundation.dart';

String resolveWebSafeImageUrl(String url) {
  if (url.isEmpty) return url;
  if (kIsWeb && (url.startsWith('http://') || url.startsWith('https://'))) {
    return '/img-proxy/?url=${Uri.encodeComponent(url)}';
  }
  return url;
}
