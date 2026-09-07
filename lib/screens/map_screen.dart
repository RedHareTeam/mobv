import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mobv/app_theme.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../app_config.dart';
import '../services/appointment_service.dart';
import '../services/auth_service.dart';
import '../services/circle_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/kakao_map_webview.dart';
import '../widgets/no_intersection_sheet.dart';
import 'place_screen.dart';

class MapScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;
  final List<String> members;

  const MapScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.members,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _authService = AuthService();
  final _circleService = CircleService();
  final _roomService = AppointmentService();
  final _mapKey = GlobalKey<KakaoMapWebViewState>();

  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;

  // 내 원
  double _myLat = 37.5665;
  double _myLng = 126.9780;
  double _myRadius = 3000;
  bool _myCircleDrawn = false;
  bool _circleChecked = false; // getMyCircle 완료 후 true

  // 파트너 원 (memberId → {lat, lng, radius, userName})
  final Map<String, Map<String, dynamic>> _partnerCircles = {};

  // 약속 날짜 + 날씨
  DateTime? _appointmentDate;
  Map<String, dynamic>? _weatherInfo;
  Map<String, dynamic>? _lastRoom;
  int? _myProfileColorValue;

  bool _isDrawMode = false;
  bool _isRequesting = false;
  bool _isNavigating = false;
  bool _mapReady = false;
  bool _hasIntersection = false;

  @override
  void initState() {
    super.initState();
    _watchMyProfileColor();
    _watchAppointment();
    _watchPartners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _saveTimer?.cancel();
    super.dispose();
  }

  // ── 약속 상태 감지 ──────────────────────────────────────────

  void _watchMyProfileColor() {
    final sub = _authService.watchUserInfo(widget.myUserId).listen((info) {
      final colorValue = (info?['profileColor'] as num?)?.toInt();
      if (colorValue == null || colorValue == _myProfileColorValue) return;
      setState(() => _myProfileColorValue = colorValue);
      _syncMyColorToMap();
    });
    _subs.add(sub);
  }

  void _watchAppointment() {
    final sub = _roomService.watchAppointment(widget.roomId).listen((room) {
      if (!mounted || _isNavigating) return;
      if (room == null) {
        _isNavigating = true;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('약속이 삭제되어 홈으로 돌아갑니다')));
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      _lastRoom = room;
      final status = room['status'] as String? ?? '';
      final members = List<String>.from(room['members'] ?? []);
      _syncMyColorToMap();

      // 약속 날짜 업데이트
      final dateTs = room['appointmentDate'];
      if (dateTs != null) {
        final date = ((dateTs as dynamic).toDate() as DateTime).toLocal();
        if (_appointmentDate != date) {
          setState(() => _appointmentDate = date);
        }
      }

      if (status == 'voting') {
        _isNavigating = true;
        final places = List<Map<String, dynamic>>.from(room['places'] ?? []);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlaceScreen(
              roomId: widget.roomId,
              userId: widget.myUserId,
              userName: widget.myUserName,
              members: members,
              places: places,
              appointmentDate: _appointmentDate,
            ),
          ),
        );
      } else if (status == 'waiting') {
        _isNavigating = true;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('멤버가 나가 처음으로 돌아갑니다')));
        Navigator.pop(context);
      }
    });
    _subs.add(sub);
  }

  // 약속 날짜의 날씨 조회 (백엔드 forecast 엔드포인트)
  Future<void> _fetchWeather(Map<String, dynamic> room) async {
    final dateTs = room['appointmentDate'];
    if (dateTs == null) return;
    final dateUtc = ((dateTs as dynamic).toDate() as DateTime).toUtc();

    // 만남 구역 중심 = 모든 원 중심의 평균
    double centerLat = _myLat;
    double centerLng = _myLng;
    if (_partnerCircles.isNotEmpty) {
      for (final c in _partnerCircles.values) {
        centerLat += c['lat'] as double;
        centerLng += c['lng'] as double;
      }
      centerLat /= (_partnerCircles.length + 1);
      centerLng /= (_partnerCircles.length + 1);
    }

    try {
      final res = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/weather/forecast'
              '?date=${Uri.encodeComponent(dateUtc.toIso8601String())}'
              '&lat=$centerLat&lng=$centerLng',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _weatherInfo = data as Map<String, dynamic>);
      }
    } catch (_) {
      // 날씨 조회 실패 시 날짜만 표시 (무시)
    }
  }

  // ── 파트너 원 구독 ────────────────────────────────────────

  void _watchPartners() {
    for (final memberId in widget.members) {
      if (memberId == widget.myUserId) continue;
      final sub = _circleService
          .watchPartnerCircle(roomId: widget.roomId, partnerId: memberId)
          .listen((data) {
            if (data != null) {
              setState(() {
                _partnerCircles[memberId] = {
                  'lat': (data['lat'] as num).toDouble(),
                  'lng': (data['lng'] as num).toDouble(),
                  'radius': (data['radius'] as num).toDouble(),
                  'userName': data['userName'] as String? ?? '상대방',
                };
              });
              _updateIntersectionState();
              if (_mapReady) {
                _mapKey.currentState?.updatePartnerCircle(
                  memberId,
                  _partnerCircles[memberId]!['lat'] as double,
                  _partnerCircles[memberId]!['lng'] as double,
                  _partnerCircles[memberId]!['radius'] as double,
                  _partnerCircles[memberId]!['userName'] as String,
                  _memberColorHex(memberId),
                );
              }
            } else {
              // 원이 삭제됨 (다시 그리기 / 다시 만들기)
              setState(() => _partnerCircles.remove(memberId));
              _updateIntersectionState();
              if (_mapReady) _mapKey.currentState?.clearPartnerCircle(memberId);
            }
          });
      _subs.add(sub);
    }
  }

  String get _myColorHex => _memberColorHex(widget.myUserId);

  String _memberName(String userId) {
    if (userId == widget.myUserId) {
      final myName = widget.myUserName.trim();
      return myName.isEmpty ? '나' : myName;
    }

    final memberProfiles = Map<String, dynamic>.from(
      _lastRoom?['memberProfiles'] as Map? ?? {},
    );
    final profile = Map<String, dynamic>.from(
      memberProfiles[userId] as Map? ?? {},
    );
    final legacyNames = Map<String, dynamic>.from(
      _lastRoom?['memberNames'] as Map? ?? {},
    );
    final profileName = profile['name']?.toString().trim();
    if (profileName != null && profileName.isNotEmpty) return profileName;

    final legacyName = legacyNames[userId]?.toString().trim();
    if (legacyName != null && legacyName.isNotEmpty) return legacyName;

    final circleName = _partnerCircles[userId]?['userName']?.toString().trim();
    if (circleName != null && circleName.isNotEmpty) return circleName;

    return '멤버';
  }

  String _memberColorHex(String userId) {
    if (userId == widget.myUserId && _myProfileColorValue != null) {
      return _colorValueToHex(_myProfileColorValue!);
    }

    final memberProfiles = Map<String, dynamic>.from(
      _lastRoom?['memberProfiles'] as Map? ?? {},
    );
    final profile = Map<String, dynamic>.from(
      memberProfiles[userId] as Map? ?? {},
    );
    final legacyColors = Map<String, dynamic>.from(
      _lastRoom?['memberColors'] as Map? ?? {},
    );
    final stored = profile['color'] ?? legacyColors[userId];
    final value = stored is num
        ? stored.toInt()
        : _authService.fallbackProfileColor(userId);
    return _colorValueToHex(value);
  }

  String _colorValueToHex(int value) {
    final rgb = value & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _syncMyColorToMap() {
    if (!_mapReady) return;
    _mapKey.currentState?.setMyColor(_myColorHex);
    if (_myCircleDrawn) {
      _mapKey.currentState?.updateMyCircle(
        _myLat,
        _myLng,
        _myRadius,
        widget.myUserName,
        _myColorHex,
      );
    }
  }

  // ── 지도 준비 완료 콜백 ───────────────────────────────────

  Future<void> _onMapReady() async {
    setState(() => _mapReady = true);
    _syncMyColorToMap();

    // 내 원 복원
    final myData = await _circleService.getMyCircle(
      roomId: widget.roomId,
      userId: widget.myUserId,
    );
    if (myData != null && mounted) {
      final lat = (myData['lat'] as num).toDouble();
      final lng = (myData['lng'] as num).toDouble();
      final radius = (myData['radius'] as num).toDouble();
      setState(() {
        _myLat = lat;
        _myLng = lng;
        _myRadius = radius;
        _myCircleDrawn = true;
        _circleChecked = true;
      });
      _mapKey.currentState?.updateMyCircle(
        lat,
        lng,
        radius,
        widget.myUserName,
        _myColorHex,
      );
      _mapKey.currentState?.setCenter(lat, lng);
      _showLocationDot();
    } else {
      if (mounted) setState(() => _circleChecked = true);
      _moveToCurrentLocation();
    }

    // 파트너 원 복원
    final partnerIds = widget.members
        .where((id) => id != widget.myUserId)
        .toList();
    for (int i = 0; i < partnerIds.length; i++) {
      final id = partnerIds[i];
      final data = _partnerCircles[id];
      if (data != null) {
        _mapKey.currentState?.updatePartnerCircle(
          id,
          data['lat'] as double,
          data['lng'] as double,
          data['radius'] as double,
          data['userName'] as String,
          _memberColorHex(id),
        );
      }
    }

    _updateIntersectionState();
  }

  Future<({double lat, double lng})?> _fetchGpsPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final inKorea =
          pos.latitude >= 33.0 &&
          pos.latitude <= 38.9 &&
          pos.longitude >= 124.5 &&
          pos.longitude <= 131.0;
      if (!inKorea) return null;
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _moveToCurrentLocation({bool showFeedback = false}) async {
    final pos = await _fetchGpsPosition();
    if (!mounted) return;
    if (pos == null) {
      if (showFeedback) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('현재 위치를 가져올 수 없어요')));
      }
      return;
    }
    _mapKey.currentState?.setCenter(pos.lat, pos.lng, level: 5);
    _mapKey.currentState?.showCurrentLocationDot(pos.lat, pos.lng);
  }

  Future<void> _showLocationDot() async {
    final pos = await _fetchGpsPosition();
    if (pos == null || !mounted) return;
    _mapKey.currentState?.showCurrentLocationDot(pos.lat, pos.lng);
  }

  // ── 원 그리기 ─────────────────────────────────────────────

  void _onCircleDrawn(double lat, double lng, double radius) {
    setState(() {
      _myLat = lat;
      _myLng = lng;
      _myRadius = radius;
      _isDrawMode = false;
      _myCircleDrawn = true;
    });
    _mapKey.currentState?.setDrawMode(false);
    _mapKey.currentState?.updateMyCircle(
      lat,
      lng,
      radius,
      widget.myUserName,
      _myColorHex,
    );

    _updateIntersectionState();

    _saveTimer?.cancel();
    _circleService.saveMyCircle(
      roomId: widget.roomId,
      userId: widget.myUserId,
      userName: widget.myUserName,
      lat: lat,
      lng: lng,
      radius: radius,
    );
  }

  void _toggleDrawMode() {
    setState(() => _isDrawMode = !_isDrawMode);
    _mapKey.currentState?.setDrawMode(_isDrawMode);
  }

  // ── 교집합 체크 ───────────────────────────────────────────

  void _updateIntersectionState() {
    final prev = _hasIntersection;
    setState(() => _hasIntersection = _checkIntersection());
    // 교집합이 처음 생겼을 때 날씨를 올바른 만남 지점으로 재조회
    if (!prev &&
        _hasIntersection &&
        _lastRoom != null &&
        _appointmentDate != null) {
      _fetchWeather(_lastRoom!);
    }
  }

  bool _checkIntersection() {
    if (!_myCircleDrawn) return false;

    final partnerIds = widget.members
        .where((id) => id != widget.myUserId)
        .toList();

    // 혼자일 때는 교집합 계산 및 장소 추천 불가 (최소 2인 이상 참여 필요)
    if (partnerIds.isEmpty) return false;
    if (_partnerCircles.length < partnerIds.length) return false;

    final circles = <Map<String, double>>[
      {'lat': _myLat, 'lng': _myLng, 'radius': _myRadius},
      ...partnerIds.map(
        (id) => {
          'lat': _partnerCircles[id]!['lat'] as double,
          'lng': _partnerCircles[id]!['lng'] as double,
          'radius': _partnerCircles[id]!['radius'] as double,
        },
      ),
    ];

    // 모든 쌍(pair) 교집합 확인
    for (int i = 0; i < circles.length; i++) {
      for (int j = i + 1; j < circles.length; j++) {
        final dist = _haversine(
          circles[i]['lat']!,
          circles[i]['lng']!,
          circles[j]['lat']!,
          circles[j]['lng']!,
        );
        if (dist >= circles[i]['radius']! + circles[j]['radius']!) return false;
      }
    }

    // 3명 이상: 공통 교집합 후보점 검증
    // 각 원 쌍의 교선 위의 점들을 후보로 사용해 하나라도 전체 원 안에 있으면 교집합 존재
    if (circles.length >= 3) {
      // 후보1: 모든 원 중심의 단순 평균
      final avgLat =
          circles.map((c) => c['lat']!).reduce((a, b) => a + b) /
          circles.length;
      final avgLng =
          circles.map((c) => c['lng']!).reduce((a, b) => a + b) /
          circles.length;
      final candidates = <Map<String, double>>[
        {'lat': avgLat, 'lng': avgLng},
      ];

      // 후보2: 각 쌍의 중심 간 내분점(반지름 비율)
      for (int i = 0; i < circles.length; i++) {
        for (int j = i + 1; j < circles.length; j++) {
          final ri = circles[i]['radius']!, rj = circles[j]['radius']!;
          candidates.add({
            'lat':
                (circles[i]['lat']! * rj + circles[j]['lat']! * ri) / (ri + rj),
            'lng':
                (circles[i]['lng']! * rj + circles[j]['lng']! * ri) / (ri + rj),
          });
        }
      }

      // 후보 중 하나라도 모든 원 안에 있으면 공통 교집합 존재
      final hasCommon = candidates.any(
        (pt) => circles.every(
          (c) =>
              _haversine(pt['lat']!, pt['lng']!, c['lat']!, c['lng']!) <
              c['radius']!,
        ),
      );
      if (!hasCommon) return false;
    }

    return true;
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── 장소 추천 요청 ────────────────────────────────────────

  Future<void> _requestPlaces() async {
    if (_isRequesting || !_hasIntersection) return;
    setState(() => _isRequesting = true);

    try {
      final roomData = await _roomService.getAppointment(widget.roomId) ?? {};
      final category =
          roomData['category'] ?? roomData['searchQuery'] ?? 'cafe';
      final mood = List<String>.from(roomData['mood'] ?? []);

      // 참여자별 원 데이터 구성 (1명일 때는 본인 원만 전달)
      final partnerIds = widget.members
          .where((id) => id != widget.myUserId)
          .toList();

      final myCircleMap = {'lat': _myLat, 'lng': _myLng, 'radius': _myRadius};
      final usersList = <Map<String, dynamic>>[
        myCircleMap,
        ...partnerIds.map((id) {
          final d = _partnerCircles[id]!;
          return {'lat': d['lat'], 'lng': d['lng'], 'radius': d['radius']};
        }),
      ];

      final Map<String, dynamic> requestBody = {
        'users': usersList,
        'category': category,
        'mood': mood,
      };

      if (partnerIds.isNotEmpty) {
        final firstPartnerId = partnerIds.first;
        final firstPartnerData = _partnerCircles[firstPartnerId];
        if (firstPartnerData != null) {
          requestBody['user1'] = myCircleMap;
          requestBody['user2'] = {
            'lat': firstPartnerData['lat'],
            'lng': firstPartnerData['lng'],
            'radius': firstPartnerData['radius'],
          };
        }
      } else {
        // 혼자일 때 호환 필드
        requestBody['user1'] = myCircleMap;
      }

      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/recommend'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 422) {
        // 추천 장소 2개 미만 - 인터랙티브 복구 바텀시트 제공
        if (mounted) {
          NoIntersectionSheet.show(
            context: context,
            onExpandRadius: () {
              final expandedRadius = _myRadius * 1.2;
              _onCircleDrawn(_myLat, _myLng, expandedRadius);
              Future.delayed(const Duration(milliseconds: 400), () {
                if (mounted) _requestPlaces();
              });
            },
            onRedraw: () {
              setState(() => _isDrawMode = true);
              _mapKey.currentState?.setDrawMode(true);
            },
          );
        }
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final places = List<Map<String, dynamic>>.from(data['places'] ?? []);
        await _circleService.savePlaces(widget.roomId, places);
      } else {
        throw Exception('statusCode: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('장소 추천 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('장소 추천 중 오류가 발생했어요')));
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  // ── 날짜/날씨 포맷 ────────────────────────────────────────

  String _formatAppointmentDate(DateTime dt) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[dt.weekday - 1];
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? '오전' : '오후';
    final dh = h % 12 == 0 ? 12 : h % 12;
    return '${dt.month}/${dt.day}($wd) $ampm $dh:$m';
  }

  IconData? _weatherIconData() {
    if (_weatherInfo == null) return null;
    return switch (_weatherInfo!['condition']) {
      'clear' => Icons.wb_sunny,
      'clouds' => Icons.cloud,
      'rain' => Icons.water_drop,
      'snow' => Icons.ac_unit,
      'thunder' => Icons.thunderstorm,
      _ => null,
    };
  }

  // ── 빌드 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 전체 화면 지도
          Positioned.fill(
            child: KakaoMapWebView(
              key: _mapKey,
              kakaoApiKey: AppConfig.kakaoJsKey,
              myCircleColor: _myColorHex,
              onCenterChanged: (lat, lng) {},
              onCircleDrawn: _onCircleDrawn,
              onMapReady: _onMapReady,
            ),
          ),

          // ── 상단 오버레이 ──────────────────────────────────
          Positioned(
            top: topPad + 8,
            left: 16,
            right: 16,
            child: PointerInterceptor(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 헤더 행: 뒤로가기 + 타이틀 + 날짜
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        AppCircleIconButton(
                          icon: Icons.chevron_left_rounded,
                          size: 38,
                          iconSize: 22,
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '만날 범위 그리기',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '내가 괜찮은 지역을 원으로 선택해요',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_appointmentDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.event_rounded,
                                  size: 13,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatAppointmentDate(_appointmentDate!),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                if (_weatherIconData() != null) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    _weatherIconData()!,
                                    size: 13,
                                    color: AppTheme.primary,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${_weatherInfo!['temp']}°',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (_circleChecked) ...[
                    const SizedBox(height: 8),
                    _MemberStatusHorizontalBar(
                      members: widget.members,
                      myUserId: widget.myUserId,
                      myDrawn: _myCircleDrawn,
                      partnerCircles: _partnerCircles,
                      nameForUser: _memberName,
                      colorForUser: _memberColorHex,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── 우측 플로팅 컨트롤 버튼 (세로형 FAB 세트) ───────────
          Positioned(
            right: 16,
            bottom: bottomPad + 16,
            child: PointerInterceptor(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapFloatingActionButton(
                    icon: Icons.my_location_rounded,
                    onTap: () => _moveToCurrentLocation(showFeedback: true),
                  ),
                  const SizedBox(height: 10),
                  _MapFloatingActionButton(
                    icon: _isDrawMode
                        ? Icons.open_with_rounded
                        : Icons.gesture_rounded,
                    active: _isDrawMode,
                    onTap: _toggleDrawMode,
                  ),
                  const SizedBox(height: 10),
                  _MapRecommendFloatingButton(
                    hasIntersection: _hasIntersection,
                    isRequesting: _isRequesting,
                    myDrawn: _myCircleDrawn,
                    drawnCount:
                        (_myCircleDrawn ? 1 : 0) + _partnerCircles.length,
                    totalCount: widget.members.isEmpty
                        ? 1
                        : widget.members.length,
                    onTap: _requestPlaces,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapFloatingActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  const _MapFloatingActionButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? AppTheme.primary : AppTheme.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              icon,
              color: active ? Colors.white : AppTheme.textDark,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// 장소 추천 플로팅 아이콘 버튼
/// 상태(대기 중 / 추천 가능 / 로딩 중)에 따라 색상과 툴팁이 변화하여 직관적 피드백 제공
class _MapRecommendFloatingButton extends StatelessWidget {
  final bool hasIntersection;
  final bool isRequesting;
  final bool myDrawn;
  final int drawnCount;
  final int totalCount;
  final VoidCallback onTap;

  const _MapRecommendFloatingButton({
    required this.hasIntersection,
    required this.isRequesting,
    required this.myDrawn,
    required this.drawnCount,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canRecommend = hasIntersection && !isRequesting;

    // 색상 상태 정의:
    // 1. 추천 가능 (교집합 완료): AppTheme.primary (모던 블랙) + 반짝임(화이트)
    // 2. 대기/그리기 중: 연한 그레이 배경 + 흐린 아이콘
    final Color bgColor = canRecommend
        ? AppTheme.primary
        : const Color(0xFFF4F4F5);
    final Color iconColor = canRecommend
        ? Colors.white
        : const Color(0xFFA1A1AA);
    final Color borderColor = canRecommend
        ? AppTheme.primary
        : const Color(0xFFE4E4E7);

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: canRecommend ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: canRecommend
                    ? Colors.black.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: canRecommend ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: isRequesting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : Icon(
                    hasIntersection
                        ? Icons.auto_awesome_rounded
                        : Icons.auto_awesome_outlined,
                    color: iconColor,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MemberStatusHorizontalBar extends StatelessWidget {
  final List<String> members;
  final String myUserId;
  final bool myDrawn;
  final Map<String, Map<String, dynamic>> partnerCircles;
  final String Function(String userId) nameForUser;
  final String Function(String userId) colorForUser;

  const _MemberStatusHorizontalBar({
    required this.members,
    required this.myUserId,
    required this.myDrawn,
    required this.partnerCircles,
    required this.nameForUser,
    required this.colorForUser,
  });

  @override
  Widget build(BuildContext context) {
    final orderedMembers = members.isEmpty ? [myUserId] : members;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: orderedMembers.map((uid) {
          final isMe = uid == myUserId;
          final done = isMe ? myDrawn : partnerCircles.containsKey(uid);
          final label = nameForUser(uid);
          final hex = colorForUser(uid).replaceFirst('#', '');
          final color = Color(int.parse('FF$hex', radix: 16));

          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      done ? Icons.check_rounded : Icons.edit_location_outlined,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label.isEmpty ? (isMe ? '나' : '멤버') : label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                    color: done ? AppTheme.textDark : AppTheme.textMuted,
                  ),
                ),
                if (done) ...[
                  const SizedBox(width: 4),
                  const Text(
                    '완료',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.confirmed,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
