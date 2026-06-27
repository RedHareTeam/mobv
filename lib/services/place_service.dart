import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../app_config.dart';

class PlaceService {
  static String get _kakaoRestKey => AppConfig.kakaoRestKey;

  // 교집합 중심점 근처 장소 카카오에서 바로 검색
  Future<List<Map<String, dynamic>>> searchNearby({
    required double lat,
    required double lng,
    String category = 'CE7', // CE7=카페, FD6=음식점, CT1=문화시설
    int radius = 2000, // 미터
  }) async {
    final url = Uri.parse(
      'https://dapi.kakao.com/v2/local/search/category.json'
      '?category_group_code=$category'
      '&x=$lng&y=$lat'
      '&radius=$radius'
      '&sort=distance'
      '&size=10',
    );

    final res = await http.get(
      url,
      headers: {'Authorization': 'KakaoAK $_kakaoRestKey'},
    );

    if (res.statusCode != 200) {
      debugPrint('카카오 API 에러: ${res.statusCode}');
      return [];
    }

    final data = jsonDecode(res.body);
    final docs = data['documents'] as List;

    return docs
        .map(
          (d) => {
            'name': d['place_name'],
            'lat': double.parse(d['y']),
            'lng': double.parse(d['x']),
            'address': d['road_address_name'] ?? d['address_name'],
            'distance': d['distance'],
            'kakaoUrl': d['place_url'],
            'category': d['category_name'],
            'phone': d['phone'],
          },
        )
        .toList();
  }
}
