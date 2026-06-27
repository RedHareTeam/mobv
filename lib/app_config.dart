import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

class AppConfig {
  static String get kakaoJsKey {
    const v = String.fromEnvironment('KAKAO_JS_KEY');
    return v.isNotEmpty ? v : (dotenv.env['KAKAO_JS_KEY'] ?? '');
  }

  static String get kakaoRestKey {
    const v = String.fromEnvironment('KAKAO_REST_KEY');
    return v.isNotEmpty ? v : (dotenv.env['KAKAO_REST_KEY'] ?? '');
  }

  static String get baseUrl {
    const v = String.fromEnvironment('BASE_URL');
    if (v.isNotEmpty) return v;
    final envUrl = dotenv.env['BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) return 'http://localhost:5000';
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:5000';
    return 'http://127.0.0.1:5000';
  }
}
