import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../app_config.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../constants.dart';
import '../widgets/app_dialog.dart';
import '../widgets/kakao_map_webview.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/gradient_button.dart';
import '../services/circle_service.dart';
import '../services/room_service.dart';
import 'place_screen.dart';
import 'package:mobv/app_theme.dart';

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
  final _circleService = CircleService();
  final _roomService = RoomService();
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

  bool _isDrawMode = false;
  bool _isRequesting = false;
  bool _isNavigating = false;
  bool _mapReady = false;
  bool _hasIntersection = false;

  int _processedMsgCount = 0;
  final List<Map<String, dynamic>> _pendingMessages = [];

  // 파트너 색상 (최대 3명 추가 지원)
  static const List<String> _partnerColors = [
    '#FF9BDE',
    '#34D399',
    '#FBBF24',
    '#60A5FA',
  ];

  @override
  void initState() {
    super.initState();
    _watchRoom();
    _watchPartners();
    _watchMessages();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _saveTimer?.cancel();
    super.dispose();
  }

  // ── 방 상태 감지 ──────────────────────────────────────────

  void _watchRoom() {
    final sub = _roomService.watchRoom(widget.roomId).listen((room) {
      if (room == null || !mounted || _isNavigating) return;
      _lastRoom = room;
      final status = room['status'] as String? ?? '';
      final members = List<String>.from(room['members'] ?? []);

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
              '${AppConstants.baseUrl}/weather/forecast'
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
                final colorIdx =
                    widget.members
                        .where((id) => id != widget.myUserId)
                        .toList()
                        .indexOf(memberId) %
                    _partnerColors.length;
                _mapKey.currentState?.updatePartnerCircle(
                  memberId,
                  _partnerCircles[memberId]!['lat'] as double,
                  _partnerCircles[memberId]!['lng'] as double,
                  _partnerCircles[memberId]!['radius'] as double,
                  _partnerCircles[memberId]!['userName'] as String,
                  _partnerColors[colorIdx],
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

  void _watchMessages() {
    final sub = _circleService.watchMessages(roomId: widget.roomId).listen((
      messages,
    ) {
      if (_processedMsgCount > messages.length)
        _processedMsgCount = messages.length;
      final newMessages = messages.sublist(_processedMsgCount);
      _processedMsgCount = messages.length;
      for (final msg in newMessages) {
        if (msg['userId'] == widget.myUserId) continue;
        if (_mapReady) {
          _mapKey.currentState?.addMessage(
            msg['userId'],
            msg['userName'],
            msg['message'],
          );
        } else {
          _pendingMessages.add(msg);
        }
      }
    });
    _subs.add(sub);
  }

  // ── 지도 준비 완료 콜백 ───────────────────────────────────

  Future<void> _onMapReady() async {
    setState(() => _mapReady = true);

    for (final msg in _pendingMessages) {
      _mapKey.currentState?.addMessage(
        msg['userId'],
        msg['userName'],
        msg['message'],
      );
    }
    _pendingMessages.clear();

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
      _mapKey.currentState?.updateMyCircle(lat, lng, radius, widget.myUserName);
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
          _partnerColors[i % _partnerColors.length],
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
          permission == LocationPermission.deniedForever)
        return null;
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
    _mapKey.currentState?.updateMyCircle(lat, lng, radius, widget.myUserName);

    final msg = '${widget.myUserName}님이 구역을 설정했어요';
    _mapKey.currentState?.addMessage(widget.myUserId, widget.myUserName, msg);
    _updateIntersectionState();

    // 원 저장 완료 후 메시지 전송 — 상대방에서 핀이 생긴 뒤 메시지가 도착하도록 순서 보장
    _saveTimer?.cancel();
    _circleService
        .saveMyCircle(
          roomId: widget.roomId,
          userId: widget.myUserId,
          userName: widget.myUserName,
          lat: lat,
          lng: lng,
          radius: radius,
        )
        .then((_) {
          _circleService.sendMessage(
            roomId: widget.roomId,
            userId: widget.myUserId,
            userName: widget.myUserName,
            message: msg,
          );
        });
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
      final roomData = await _roomService.getRoom(widget.roomId) ?? {};
      final searchQuery = roomData['searchQuery'] ?? '맛집';
      final mood = List<String>.from(roomData['mood'] ?? []);
      final intimacyScore = (roomData['intimacyScore'] ?? 50).toDouble();

      // 모든 파트너 원을 partners 배열로 전달 (백엔드가 지원하는 경우)
      // 백엔드가 2인만 지원하면 user2에 첫 번째 파트너를 사용
      final partnerIds = widget.members
          .where((id) => id != widget.myUserId)
          .toList();
      final firstPartnerId = partnerIds.first;
      final firstPartnerData = _partnerCircles[firstPartnerId];
      if (firstPartnerData == null) {
        throw Exception('파트너 원 데이터를 찾을 수 없습니다');
      }

      final response = await http
          .post(
            Uri.parse('${AppConstants.baseUrl}/recommend'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'user1': {'lat': _myLat, 'lng': _myLng, 'radius': _myRadius},
              'user2': {
                'lat': firstPartnerData['lat'],
                'lng': firstPartnerData['lng'],
                'radius': firstPartnerData['radius'],
              },
              // 3인 이상 원 데이터 추가 전달 (백엔드 확장 시 활용)
              'users': [
                {'lat': _myLat, 'lng': _myLng, 'radius': _myRadius},
                ...partnerIds.map((id) {
                  final d = _partnerCircles[id]!;
                  return {
                    'lat': d['lat'],
                    'lng': d['lng'],
                    'radius': d['radius'],
                  };
                }),
              ],
              'search_query': searchQuery,
              'mood': mood,
              'intimacy_score': intimacyScore,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 422) {
        // 추천 장소 2개 미만
        if (mounted) {
          await showDialog(
            context: context,
            builder: (_) => PointerInterceptor(
              child: AppDialog(
                title: '장소가 부족해요',
                content: '교집합이 너무 작아 추천 장소가 2곳 미만이에요.\n원을 조금 더 넓게 그려주세요.',
                icon: Icons.location_off_outlined,
                actions: [
                  DialogAction(
                    label: '확인',
                    primary: true,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
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
                  // 헤더 행: 뒤로가기 + 타이틀 + 날짜/날씨
                  GlassmorphicContainer(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                    child: Row(
                      children: [
                        // 뒤로가기
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.bg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.chevron_left_rounded,
                              size: 22,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '구역 설정',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        // 날짜 + 날씨
                        if (_appointmentDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
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

                  const SizedBox(height: 8),

                  // 모드 인디케이터 pill
                  if (_circleChecked)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Builder(
                          builder: (context) {
                            final pill = AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: _isDrawMode
                                    ? AppTheme.accent.withValues(
                                        alpha: kIsWeb ? 0.95 : 0.88,
                                      )
                                    : Colors.white.withValues(
                                        alpha: kIsWeb ? 0.95 : 0.82,
                                      ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isDrawMode
                                      ? AppTheme.accent.withValues(alpha: 0.4)
                                      : Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isDrawMode
                                        ? Icons.gesture
                                        : Icons.open_with,
                                    size: 14,
                                    color: _isDrawMode
                                        ? Colors.white
                                        : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isDrawMode
                                        ? '손가락으로 원을 그려보세요'
                                        : _myCircleDrawn
                                        ? '이동 모드  ·  반경 ${(_myRadius / 1000).toStringAsFixed(1)}km'
                                        : '이동 모드  ·  원을 그려보세요',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _isDrawMode
                                          ? Colors.white
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            );
                            return kIsWeb
                                ? pill
                                : BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 10,
                                      sigmaY: 10,
                                    ),
                                    child: pill,
                                  );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── 원 미그리기 안내 ───────────────────────────────
          if (_circleChecked && !_myCircleDrawn)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomPad + 100,
              child: PointerInterceptor(
                child: GlassmorphicContainer(
                  borderRadius: BorderRadius.circular(14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  backgroundAlpha: 0.12,
                  baseColor: AppTheme.warning,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: AppTheme.warningDark,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '원을 그려주세요',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.warningDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 교집합 없음 경고 ───────────────────────────────
          if (!_hasIntersection && _myCircleDrawn)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomPad + 100,
              child: PointerInterceptor(
                child: GlassmorphicContainer(
                  borderRadius: BorderRadius.circular(14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  backgroundAlpha: 0.12,
                  baseColor: AppTheme.accent,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _partnerCircles.length < widget.members.length - 1
                            ? '모든 멤버가 원을 그려야 장소 추천이 가능해요'
                            : '원이 겹치지 않아요. 더 넓게 그려주세요',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 하단 플로팅 툴바 ────────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + 16,
            child: PointerInterceptor(
              child: GlassmorphicContainer(
                borderRadius: BorderRadius.circular(24),
                sigmaX: 16,
                sigmaY: 16,
                padding: const EdgeInsets.all(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
                child: Row(
                  children: [
                    // 그리기 모드 토글
                    GestureDetector(
                      onTap: _toggleDrawMode,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _isDrawMode ? AppTheme.accent : AppTheme.bg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _isDrawMode ? Icons.open_with : Icons.gesture,
                          color: _isDrawMode
                              ? Colors.white
                              : AppTheme.textMuted,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 내 위치 버튼
                    GestureDetector(
                      onTap: () => _moveToCurrentLocation(showFeedback: true),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          color: AppTheme.accent,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 장소 추천 버튼
                    Expanded(
                      child: GradientButton(
                        onTap: _requestPlaces,
                        enabled: _hasIntersection,
                        loading: _isRequesting,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '장소 추천 받기',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
