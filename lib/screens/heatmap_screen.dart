import 'dart:async';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobv/app_theme.dart';
import 'package:flutter/material.dart';
import '../app_config.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../services/history_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/platform_html_view.dart';

// ── 데이터 모델 ────────────────────────────────────────────────────────
class _PlaceGroup {
  final String name;
  final double lat;
  final double lng;
  final String address;
  final String category;
  final String? url;
  final List<Map<String, dynamic>> historyEntries;

  _PlaceGroup({
    required this.name,
    required this.lat,
    required this.lng,
    required this.address,
    required this.category,
    this.url,
    required this.historyEntries,
  });

  int get count => historyEntries.length;

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'address': address,
    'count': count,
  };
}

// ── 히트맵 화면 ────────────────────────────────────────────────────────
class HeatmapScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;

  const HeatmapScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
  });

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final _historyService = HistoryService();
  final _mapKey = GlobalKey<_HeatmapMapViewState>();

  StreamSubscription? _historySub;
  List<_PlaceGroup> _places = [];
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _historySub = _historyService.watchHistory(widget.roomId).listen((history) {
      final groups = _groupByPlace(history);
      setState(() {
        _places = groups;
      });
      if (_mapReady) _mapKey.currentState?.updateData(groups);
    });
  }

  @override
  void dispose() {
    _historySub?.cancel();
    super.dispose();
  }

  List<_PlaceGroup> _groupByPlace(List<Map<String, dynamic>> history) {
    // 동명이지만 다른 위치의 장소를 구별하기 위해 좌표 기반 키 사용
    final Map<String, _PlaceGroup> groups = {};
    for (final h in history) {
      final place = Map<String, dynamic>.from(
        h['confirmedPlace'] as Map? ?? {},
      );
      final name = (place['name'] as String?) ?? '';
      final lat = (place['lat'] as num?)?.toDouble() ?? 0;
      final lng = (place['lng'] as num?)?.toDouble() ?? 0;
      if (name.isEmpty || (lat == 0 && lng == 0)) continue;

      // 소수점 4자리까지 반올림해 부동소수 오차 허용 (~11m 오차)
      final key = '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';

      if (groups.containsKey(key)) {
        groups[key]!.historyEntries.add(h);
      } else {
        final rawUrl = (place['url'] ?? place['kakaoUrl']) as String?;
        groups[key] = _PlaceGroup(
          name: name,
          lat: lat,
          lng: lng,
          address: (place['address'] as String?) ?? '',
          category: (place['category'] as String?) ?? '',
          url: (rawUrl?.isNotEmpty == true) ? rawUrl : null,
          historyEntries: [h],
        );
      }
    }
    return groups.values.toList()..sort((a, b) => b.count.compareTo(a.count));
  }

  void _onMapReady() {
    setState(() => _mapReady = true);
    _mapKey.currentState?.updateData(_places);
  }

  void _onPinTapped(String placeName) {
    final group = _places.firstWhere(
      (p) => p.name == placeName,
      orElse: () => _PlaceGroup(
        name: '',
        lat: 0,
        lng: 0,
        address: '',
        category: '',
        historyEntries: [],
      ),
    );
    if (group.name.isEmpty) return;

    final topPadding = MediaQuery.paddingOf(context).top;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PointerInterceptor(
        child: _PlaceDetailSheet(
          roomId: widget.roomId,
          myUserId: widget.myUserId,
          myUserName: widget.myUserName,
          initialGroup: group,
          historyService: _historyService,
          topPadding: topPadding,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 전체 화면 지도
          Positioned.fill(
            child: _HeatmapMapView(
              key: _mapKey,
              kakaoApiKey: AppConfig.kakaoJsKey,
              onMapReady: _onMapReady,
              onPinTapped: _onPinTapped,
            ),
          ),

          // ── 상단 오버레이 ──────────────────────────────────
          Positioned(
            top: topPad + 8,
            left: 16,
            right: 16,
            child: PointerInterceptor(
              child: GlassmorphicContainer(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Row(
                  children: [
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
                        '방문 히스토리',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 빈 상태 ────────────────────────────────────────
          if (_places.isEmpty && _mapReady)
            Center(
              child: GlassmorphicContainer(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.place_outlined,
                        size: 26,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '아직 방문한 장소가 없어요',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '약속을 확정하면 지도에 기록돼요',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ),

          // ── 범례 ──────────────────────────────────────────
          if (_places.isNotEmpty)
            Positioned(
              bottom: bottomPad + 20,
              right: 16,
              child: PointerInterceptor(
                child: GlassmorphicContainer(
                  borderRadius: BorderRadius.circular(14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  sigmaX: 10,
                  sigmaY: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '방문 횟수',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _legendRow(AppTheme.primary, '1회'),
                      const SizedBox(height: 4),
                      _legendRow(AppTheme.drawing, '2-3회'),
                      const SizedBox(height: 4),
                      _legendRow(AppTheme.accent, '4회+'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
        ),
      ],
    );
  }
}

// ── 히트맵 WebView ──────────────────────────────────────────────────────
class _HeatmapMapView extends StatefulWidget {
  final String kakaoApiKey;
  final VoidCallback onMapReady;
  final void Function(String placeName) onPinTapped;

  const _HeatmapMapView({
    super.key,
    required this.kakaoApiKey,
    required this.onMapReady,
    required this.onPinTapped,
  });

  @override
  State<_HeatmapMapView> createState() => _HeatmapMapViewState();
}

class _HeatmapMapViewState extends State<_HeatmapMapView> {
  PlatformHtmlViewController? _ctrl;

  void updateData(List<_PlaceGroup> places) {
    final json = jsonEncode(places.map((p) => p.toJson()).toList());
    final encoded = Uri.encodeComponent(json);
    _ctrl?.runJavaScript(
      'updateMapData(JSON.parse(decodeURIComponent("$encoded")))',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformHtmlView(
      html: _buildHtml(),
      webUrl: '/heatmap_bridge.html?appkey=${widget.kakaoApiKey}',
      channels: {
        'MapReadyChannel': (_) => widget.onMapReady(),
        'PinTappedChannel': (msg) => widget.onPinTapped(msg),
        'Console': (msg) => debugPrint('HeatmapJS: $msg'),
      },
      onCreated: (ctrl) => _ctrl = ctrl,
    );
  }

  String _buildHtml() =>
      '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap" rel="stylesheet">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; -webkit-user-select:none; user-select:none; -webkit-tap-highlight-color:transparent; font-family:"Noto Sans KR",-apple-system,"Apple SD Gothic Neo",system-ui,sans-serif; }
    body { width:100vw; height:100vh; overflow:hidden; }
    #map    { width:100%; height:100%; }
    #canvas { position:absolute; top:0; left:0; width:100%; height:100%; pointer-events:none; z-index:2; }
    #pins   { position:absolute; top:0; left:0; width:100%; height:100%; pointer-events:none; z-index:4; }
    .pin {
      position:absolute; pointer-events:auto; cursor:pointer;
      display:flex; flex-direction:column; align-items:center;
      transform:translate(-50%,-100%);
    }
    .pin-body {
      display:flex; flex-direction:column; align-items:center;
      transition: transform 0.32s cubic-bezier(0.34,1.56,0.64,1);
      transform-origin: center center;
    }
    .pin:active .pin-body {
      transform: scale(0.82);
      transition-duration: 0.06s;
      transition-timing-function: ease-in;
    }
    .pin-circle {
      width:46px; height:46px; border-radius:50%;
      display:flex; align-items:center; justify-content:center; flex-direction:column;
      color:white; box-shadow:0 4px 14px rgba(0,0,0,0.18); border:2.5px solid rgba(255,255,255,0.9);
      z-index:1;
    }
    .pin-count { font-size:15px; font-weight:800; line-height:1; }
    .pin-unit  { font-size:8px; opacity:0.9; margin-top:1px; font-weight:600; }
    .pin-tail  { width:0; height:0; border-left:6px solid transparent; border-right:6px solid transparent; margin-top:-2px; z-index:0; }
    .pin-label {
      background:rgba(28,28,46,0.78); color:white; font-size:11px; font-weight:600;
      padding:3px 8px; border-radius:8px; margin-top:5px;
      max-width:100px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
      border:1px solid rgba(255,255,255,0.12);
      -webkit-backdrop-filter:blur(8px); backdrop-filter:blur(8px);
    }
    .cpin {
      position:absolute; pointer-events:auto; cursor:pointer;
      display:flex; flex-direction:column; align-items:center;
      transform:translate(-50%,-50%);
    }
    .cpin-circle {
      border-radius:50%; display:flex; align-items:center; justify-content:center; flex-direction:column;
      color:white; border:3px solid rgba(255,255,255,0.9);
      box-shadow:0 4px 16px rgba(0,0,0,0.2);
      transition: transform 0.32s cubic-bezier(0.34,1.56,0.64,1);
      transform-origin: center;
    }
    .cpin:active .cpin-circle {
      transform: scale(0.82);
      transition-duration: 0.06s;
      transition-timing-function: ease-in;
    }
    .cpin-num   { font-weight:800; line-height:1; }
    .cpin-sub   { font-size:9px; opacity:0.9; font-weight:600; }
    .cpin-badge {
      background:rgba(28,28,46,0.78); color:white; font-size:11px; font-weight:600;
      padding:3px 9px; border-radius:8px; margin-top:5px; white-space:nowrap;
      border:1px solid rgba(255,255,255,0.12);
      -webkit-backdrop-filter:blur(8px); backdrop-filter:blur(8px);
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <div id="pins"></div>
  <canvas id="canvas"></canvas>

  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=${widget.kakaoApiKey}"></script>
  <script>
    document.addEventListener('touchstart', function(){}, {passive:true});
    var map;
    var canvas   = document.getElementById('canvas');
    var ctx      = canvas.getContext('2d');
    var pinsDiv  = document.getElementById('pins');
    var currentData  = [];
    var clusterTimer = null;
    var pinch        = null;   // { dist, cx, cy }

    kakao.maps.load(function() {
      canvas.width  = window.innerWidth;
      canvas.height = window.innerHeight;

      map = new kakao.maps.Map(document.getElementById('map'), {
        center: new kakao.maps.LatLng(37.5665, 126.9780),
        level: 8
      });

      // 팬: 히트맵 + 핀 위치 실시간 업데이트
      kakao.maps.event.addListener(map, 'center_changed', function() {
        redrawHeatmap();
        updatePinPositions();
      });

      // 줌 완료: 오버레이 표시 + 재계산
      kakao.maps.event.addListener(map, 'zoom_changed', function() {
        pinch = null;
        clearTimeout(_wzT);
        canvas.style.opacity = pinsDiv.style.opacity = '1';
        redrawHeatmap();
        renderPins();
        redrawHeatmap();
      });

      var mapEl = document.getElementById('map');
      var _wzT = null;

      // 핀치 시작: 두 손가락이면 오버레이 숨김
      mapEl.addEventListener('touchstart', function(e) {
        if (e.touches.length === 2) {
          pinch = { dist: tdist(e.touches[0], e.touches[1]) };
          canvas.style.opacity = pinsDiv.style.opacity = '0';
        }
      }, {passive: true});

      MapReadyChannel.postMessage('ready');
    });

    function tdist(a, b) {
      var dx = a.clientX - b.clientX, dy = a.clientY - b.clientY;
      return Math.sqrt(dx*dx + dy*dy);
    }

    // ── 데이터 주입 ────────────────────────────────────────────────
    function updateMapData(data) {
      currentData = data || [];
      clearPins();
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      if (!currentData.length) return;

      if (currentData.length === 1) {
        map.setCenter(new kakao.maps.LatLng(currentData[0].lat, currentData[0].lng));
        map.setLevel(4);
      } else {
        var b = new kakao.maps.LatLngBounds();
        currentData.forEach(function(p) { b.extend(new kakao.maps.LatLng(p.lat, p.lng)); });
        map.setBounds(b, 80);
      }
      redrawHeatmap();
      renderPins();
    }

    function clearPins() {
      while (pinsDiv.firstChild) pinsDiv.removeChild(pinsDiv.firstChild);
      window._clusterData = [];
    }

    // 팬할 때 이미 렌더된 핀의 left/top만 갱신 (DOM 재생성 없이)
    function updatePinPositions() {
      if (!currentData.length) return;
      var proj = map.getProjection();
      var els  = pinsDiv.querySelectorAll('[data-lat]');
      els.forEach(function(el) {
        var pt = proj.containerPointFromCoords(
          new kakao.maps.LatLng(parseFloat(el.dataset.lat), parseFloat(el.dataset.lng))
        );
        el.style.left = pt.x + 'px';
        el.style.top  = pt.y + 'px';
      });
    }

    // ── 히트맵 (캔버스) ──────────────────────────────────────────
    // 핀과 동일한 클러스터 반경으로 근접 장소를 묶고,
    // 합산 횟수 하나에 대한 색·크기만 렌더링 (색 혼합 방지)
    function redrawHeatmap() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      if (!currentData.length) return;
      var proj     = map.getProjection();
      var level    = map.getLevel();
      var clusterR = Math.max(35, level * 9);

      var pts = currentData.map(function(p) {
        var pt = proj.containerPointFromCoords(new kakao.maps.LatLng(p.lat, p.lng));
        return { x: pt.x, y: pt.y };
      });

      var used  = new Array(pts.length).fill(false);
      var spots = [];
      for (var a = 0; a < pts.length; a++) {
        if (used[a]) continue;
        var cluster = [a];
        used[a] = true;
        for (var b = a + 1; b < pts.length; b++) {
          if (used[b]) continue;
          var dx = pts[a].x - pts[b].x, dy = pts[a].y - pts[b].y;
          if (Math.sqrt(dx*dx + dy*dy) < clusterR) { cluster.push(b); used[b] = true; }
        }
        var total = cluster.reduce(function(s,i) { return s + currentData[i].count; }, 0);
        var cLat  = cluster.reduce(function(s,i) { return s + currentData[i].lat;   }, 0) / cluster.length;
        var cLng  = cluster.reduce(function(s,i) { return s + currentData[i].lng;   }, 0) / cluster.length;
        var cPt   = proj.containerPointFromCoords(new kakao.maps.LatLng(cLat, cLng));
        spots.push({ x: cPt.x, y: cPt.y, count: total });
      }

      // 낮은 횟수부터 그려 높은 횟수가 위에 오도록
      spots.sort(function(a, b) { return a.count - b.count; });

      spots.forEach(function(s) {
        var r, alpha;
        if      (s.count >= 4) { r = 120; alpha = 0.42; }
        else if (s.count >= 2) { r =  95; alpha = 0.37; }
        else                   { r =  72; alpha = 0.34; }
        var rgb = heatRgb(s.count);
        var g = ctx.createRadialGradient(s.x, s.y, 0, s.x, s.y, r);
        g.addColorStop(0,   'rgba(' + rgb + ',' + alpha + ')');
        g.addColorStop(0.5, 'rgba(' + rgb + ',' + (alpha * 0.52) + ')');
        g.addColorStop(1,   'rgba(' + rgb + ',0)');
        ctx.beginPath();
        ctx.arc(s.x, s.y, r, 0, 2 * Math.PI);
        ctx.fillStyle = g;
        ctx.fill();
      });
    }

    // ── 핀 / 클러스터 (순수 HTML div) ────────────────────────────
    function renderPins() {
      clearPins();
      if (!currentData.length) return;

      var proj     = map.getProjection();
      var level    = map.getLevel();
      var clusterR = Math.max(35, level * 9);

      var pts = currentData.map(function(p) {
        var pt = proj.containerPointFromCoords(new kakao.maps.LatLng(p.lat, p.lng));
        return { x: pt.x, y: pt.y };
      });

      var used = new Array(pts.length).fill(false);
      for (var a = 0; a < pts.length; a++) {
        if (used[a]) continue;
        var cluster = [a];
        used[a] = true;
        for (var b = a + 1; b < pts.length; b++) {
          if (used[b]) continue;
          var dx = pts[a].x - pts[b].x, dy = pts[a].y - pts[b].y;
          if (Math.sqrt(dx*dx + dy*dy) < clusterR) { cluster.push(b); used[b] = true; }
        }
        if (cluster.length === 1) {
          addSinglePin(cluster[0], pts[cluster[0]]);
        } else {
          var cLat = cluster.reduce(function(s,i){return s+currentData[i].lat;},0)/cluster.length;
          var cLng = cluster.reduce(function(s,i){return s+currentData[i].lng;},0)/cluster.length;
          var cPt  = proj.containerPointFromCoords(new kakao.maps.LatLng(cLat, cLng));
          addClusterPin(cLat, cLng, cPt, cluster);
        }
      }
    }

    function addSinglePin(idx, pt) {
      var p     = currentData[idx];
      var color = pinColor(p.count);
      var name10 = Array.from(p.name).slice(0,10).join('');
      var label  = Array.from(p.name).length > 10 ? esc(name10)+'&#8230;' : esc(p.name);
      var el    = document.createElement('div');
      el.className    = 'pin';
      el.dataset.lat  = p.lat;
      el.dataset.lng  = p.lng;
      el.style.left   = pt.x + 'px';
      el.style.top    = pt.y + 'px';
      el.innerHTML =
        '<div class="pin-body">' +
          '<div class="pin-circle" style="background:' + color + '">' +
            '<span class="pin-count">' + p.count + '</span>' +
            '<span class="pin-unit">&#54924;</span>' +
          '</div>' +
          '<div class="pin-tail" style="border-top:8px solid ' + color + '"></div>' +
        '</div>' +
        '<div class="pin-label">' + label + '</div>';
      el.addEventListener('click', function(e) { e.stopPropagation(); onPinTap(idx); });
      pinsDiv.appendChild(el);
    }

    function addClusterPin(cLat, cLng, pt, clusterArr) {
      var total = clusterArr.reduce(function(s,i){return s+currentData[i].count;},0);
      var n  = clusterArr.length;
      var sz = Math.min(62, 46 + n * 3);
      var ci = window._clusterData.length;
      window._clusterData.push(clusterArr);
      var el = document.createElement('div');
      el.className    = 'cpin';
      el.dataset.lat  = cLat;
      el.dataset.lng  = cLng;
      el.style.left   = pt.x + 'px';
      el.style.top    = pt.y + 'px';
      el.innerHTML =
        '<div class="cpin-circle" style="width:' + sz + 'px;height:' + sz + 'px;background:' + pinColor(total) + '">' +
          '<span class="cpin-num" style="font-size:' + Math.round(sz*0.36) + 'px">' + n + '</span>' +
          '<span class="cpin-sub">&#44275;</span>' +
        '</div>' +
        '<div class="cpin-badge">' + total + '&#54924; &#48169;&#47928;</div>';
      el.addEventListener('click', function(e) { e.stopPropagation(); onClusterTap(ci); });
      pinsDiv.appendChild(el);
    }

    function onPinTap(idx) { PinTappedChannel.postMessage(currentData[idx].name); }
    function onClusterTap(ci) {
      var b = new kakao.maps.LatLngBounds();
      window._clusterData[ci].forEach(function(i){ b.extend(new kakao.maps.LatLng(currentData[i].lat,currentData[i].lng)); });
      map.setBounds(b, 100);
    }

    function heatRgb(c) { return c>=4?'255,95,126':c>=2?'157,142,255':'255,155,222'; }
    function pinColor(c) { return c>=4?'#FF5F7E':c>=2?'#9D8EFF':'#FF9BDE'; }
    function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#x27;'); }
  </script>
</body>
</html>
''';
}

// ── 장소 상세 시트 ──────────────────────────────────────────────────────
class _PlaceDetailSheet extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;
  final _PlaceGroup initialGroup;
  final HistoryService historyService;
  final double topPadding;

  const _PlaceDetailSheet({
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.initialGroup,
    required this.historyService,
    required this.topPadding,
  });

  @override
  State<_PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<_PlaceDetailSheet> {
  late _PlaceGroup _group;
  StreamSubscription? _sub;
  String? _activeHistoryId;
  final _reviewCtrl = TextEditingController();
  bool _submitting = false;
  final _sheetCtrl = DraggableScrollableController();
  double _sizeBeforeExpand = 0.65;
  bool _sheetExpanded = false;
  double _maxSize = 0.95;
  double _prevKeyboardHeight = 0;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;

    _sub = widget.historyService.watchHistory(widget.roomId).listen((history) {
      final entries = history.where((h) {
        final place = Map<String, dynamic>.from(
          h['confirmedPlace'] as Map? ?? {},
        );
        return (place['name'] as String?) == widget.initialGroup.name;
      }).toList();

      if (!mounted) return;
      if (entries.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _group = _PlaceGroup(
          name: widget.initialGroup.name,
          lat: widget.initialGroup.lat,
          lng: widget.initialGroup.lng,
          address: widget.initialGroup.address,
          category: widget.initialGroup.category,
          url: widget.initialGroup.url,
          historyEntries: entries,
        );
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reviewCtrl.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  void _closeInput() {
    setState(() => _activeHistoryId = null);
    FocusScope.of(context).unfocus();
    if (_sheetCtrl.isAttached && _sheetExpanded) {
      _sheetExpanded = false;
      _sheetCtrl.animateTo(
        _sizeBeforeExpand,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _submitRecord() async {
    if (_reviewCtrl.text.trim().isEmpty ||
        _submitting ||
        _activeHistoryId == null) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.historyService.addRecord(
        roomId: widget.roomId,
        historyId: _activeHistoryId!,
        userId: widget.myUserId,
        userName: widget.myUserName,
        review: _reviewCtrl.text.trim(),
      );
      if (mounted) {
        _reviewCtrl.clear();
        setState(() => _submitting = false);
        _closeInput();
      }
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final kh = MediaQuery.viewInsetsOf(context).bottom;
    if (kh == _prevKeyboardHeight) return;
    _prevKeyboardHeight = kh;

    if (kh > 0 &&
        _activeHistoryId != null &&
        _sheetCtrl.isAttached &&
        !_sheetExpanded) {
      _sizeBeforeExpand = _sheetCtrl.size;
      _sheetExpanded = true;
      _sheetCtrl.animateTo(
        _maxSize,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else if (kh == 0 && _sheetExpanded && _sheetCtrl.isAttached) {
      _sheetExpanded = false;
      _sheetCtrl.animateTo(
        _sizeBeforeExpand,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Color _countColor(int count) {
    if (count >= 4) return AppTheme.heatmapHigh;
    if (count >= 2) return AppTheme.heatmapMid;
    return AppTheme.heatmapLow;
  }

  @override
  Widget build(BuildContext context) {
    final color = _countColor(_group.count);
    final screenH = MediaQuery.sizeOf(context).height;
    _maxSize = ((screenH - widget.topPadding - 8) / screenH).clamp(0.5, 1.0);

    return DraggableScrollableSheet(
      controller: _sheetCtrl,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: _maxSize,
      snap: true,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // 핸들
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 장소 헤더 카드
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.place_rounded, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _group.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark,
                            ),
                          ),
                          if (_group.address.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _group.address,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_group.count}회',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    if (_group.url != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse(_group.url!),
                          mode: LaunchMode.inAppBrowserView,
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.map_outlined,
                            size: 18,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 방문 목록
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                itemCount: _group.historyEntries.length,
                itemBuilder: (_, i) {
                  final entry = _group.historyEntries[i];
                  final historyId = entry['historyId'] as String;
                  final dateTs = entry['appointmentDate'];
                  final date = dateTs != null
                      ? ((dateTs as dynamic).toDate() as DateTime).toLocal()
                      : null;
                  return _VisitCard(
                    roomId: widget.roomId,
                    historyId: historyId,
                    date: date,
                    myUserId: widget.myUserId,
                    myUserName: widget.myUserName,
                    historyService: widget.historyService,
                    isActive: _activeHistoryId == historyId,
                    onRecordTap: () => setState(() {
                      _activeHistoryId = historyId;
                      _reviewCtrl.clear();
                    }),
                  );
                },
              ),
            ),

            // 고정 입력바 (키보드 위)
            if (_activeHistoryId != null)
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0x18000000))),
                ),
                padding: EdgeInsets.fromLTRB(
                  12,
                  8,
                  12,
                  8 + MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reviewCtrl,
                        autofocus: true,
                        maxLines: 4,
                        minLines: 1,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textDark,
                        ),
                        decoration: InputDecoration(
                          hintText: '기억을 남겨보세요...',
                          hintStyle: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: AppTheme.bg,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: AppTheme.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: AppTheme.primary,
                              width: 1.5,
                            ),
                          ),
                          suffixIcon: GestureDetector(
                            onTap: _closeInput,
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _reviewCtrl.text.trim().isNotEmpty
                          ? _submitRecord
                          : null,
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          color: _reviewCtrl.text.trim().isNotEmpty
                              ? AppTheme.primary
                              : AppTheme.disabled,
                          shape: BoxShape.circle,
                        ),
                        child: _submitting
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 방문 카드 ──────────────────────────────────────────────────────────
class _VisitCard extends StatefulWidget {
  final String roomId;
  final String historyId;
  final DateTime? date;
  final String myUserId;
  final String myUserName;
  final HistoryService historyService;
  final VoidCallback onRecordTap;
  final bool isActive;

  const _VisitCard({
    required this.roomId,
    required this.historyId,
    required this.date,
    required this.myUserId,
    required this.myUserName,
    required this.historyService,
    required this.onRecordTap,
    required this.isActive,
  });

  @override
  State<_VisitCard> createState() => _VisitCardState();
}

class _VisitCardState extends State<_VisitCard> {
  bool _deleting = false;

  String _formatDate(DateTime dt) {
    const wds = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} (${wds[dt.weekday - 1]})';
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: '만남 삭제',
        content: '이 만남 기록과 모든 후기를 삭제할까요?\n삭제하면 상대방에게도 사라져요.',
        icon: Icons.delete_outline_rounded,
        actions: [
          DialogAction(label: '취소', onTap: () => Navigator.pop(context, false)),
          DialogAction(
            label: '삭제',
            primary: true,
            destructive: true,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.historyService.deleteHistoryEntry(
        widget.roomId,
        widget.historyId,
      );
    } catch (_) {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _deleting ? 0.4 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // 날짜 행
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          widget.date != null
                              ? _formatDate(widget.date!)
                              : '날짜 미정',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_deleting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: AppTheme.primary,
                        strokeWidth: 2,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _confirmDelete,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(
              height: 1,
              color: AppTheme.border,
              indent: 14,
              endIndent: 14,
            ),

            // 기록 목록
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: widget.historyService.watchRecords(
                widget.roomId,
                widget.historyId,
              ),
              builder: (_, snap) {
                final records = snap.data ?? [];
                return Column(
                  children: [
                    ...records.map(
                      (r) => _RecordItem(
                        record: r,
                        isMyRecord: r['userId'] == widget.myUserId,
                        onDelete: () => widget.historyService.deleteRecord(
                          widget.roomId,
                          widget.historyId,
                          r['recordId'] as String,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.isActive ? null : widget.onRecordTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: widget.isActive
                              ? AppTheme.primary.withValues(alpha: 0.08)
                              : AppTheme.primary.withValues(alpha: 0.04),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.isActive
                                  ? Icons.edit_rounded
                                  : Icons.add_circle_outline,
                              size: 15,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.isActive ? '입력 중...' : '기록 남기기',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── 기록 아이템 ────────────────────────────────────────────────────────
class _RecordItem extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool isMyRecord;
  final VoidCallback onDelete;

  const _RecordItem({
    required this.record,
    required this.isMyRecord,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final userName = record['userName'] as String? ?? '';
    final review = record['review'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryBg,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    userName.isNotEmpty ? userName[0] : '?',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              const Spacer(),
              if (isMyRecord)
                GestureDetector(
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AppDialog(
                        title: '기록 삭제',
                        content: '이 기록을 삭제할까요?',
                        icon: Icons.delete_outline_rounded,
                        actions: [
                          DialogAction(
                            label: '취소',
                            onTap: () => Navigator.pop(context, false),
                          ),
                          DialogAction(
                            label: '삭제',
                            primary: true,
                            destructive: true,
                            onTap: () => Navigator.pop(context, true),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) onDelete();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          if (review.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textDark,
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0x12000000)),
        ],
      ),
    );
  }
}

// ── 기록 추가 시트 ─────────────────────────────────────────────────────
class _AddRecordSheet extends StatefulWidget {
  final String roomId;
  final String historyId;
  final String userId;
  final String userName;
  final HistoryService historyService;

  const _AddRecordSheet({
    required this.roomId,
    required this.historyId,
    required this.userId,
    required this.userName,
    required this.historyService,
  });

  @override
  State<_AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends State<_AddRecordSheet> {
  final _reviewCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _reviewCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit || _loading) return;
    setState(() => _loading = true);
    try {
      await widget.historyService.addRecord(
        roomId: widget.roomId,
        historyId: widget.historyId,
        userId: widget.userId,
        userName: widget.userName,
        review: _reviewCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e, st) {
      debugPrint('addRecord error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 오류: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 핸들
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '기록 남기기',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 후기 입력
          TextField(
            controller: _reviewCtrl,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textDark,
              height: 1.6,
            ),
            decoration: InputDecoration(
              hintText: '이 장소에서의 기억을 남겨보세요...',
              hintStyle: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 14,
              ),
              filled: true,
              fillColor: AppTheme.bg,
              contentPadding: const EdgeInsets.all(14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppTheme.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 저장 버튼
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: _canSubmit
                    ? const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.gradientEnd],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: _canSubmit ? null : AppTheme.disabled,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ElevatedButton(
                onPressed: _canSubmit && !_loading ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ).copyWith(elevation: WidgetStateProperty.all(0)),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        '저장',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
