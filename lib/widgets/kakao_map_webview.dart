import 'package:flutter/material.dart';
import 'platform_html_view.dart';

class KakaoMapWebView extends StatefulWidget {
  final String kakaoApiKey;
  final Function(double lat, double lng) onCenterChanged;
  final Function(double lat, double lng, double radius) onCircleDrawn;
  final VoidCallback? onMapReady;

  const KakaoMapWebView({
    super.key,
    required this.kakaoApiKey,
    required this.onCenterChanged,
    required this.onCircleDrawn,
    this.onMapReady,
  });

  @override
  State<KakaoMapWebView> createState() => KakaoMapWebViewState();
}

class KakaoMapWebViewState extends State<KakaoMapWebView> {
  PlatformHtmlViewController? _ctrl;

  void updateMyCircle(double lat, double lng, double radius, String userName) {
    final enc = Uri.encodeComponent(userName);
    _ctrl?.runJavaScript(
        'updateMyCircle($lat,$lng,$radius,decodeURIComponent("$enc"))');
  }

  void updatePartnerCircle(String partnerId, double lat, double lng,
      double radius, String userName, String color) {
    final enc = Uri.encodeComponent(userName);
    _ctrl?.runJavaScript(
        'updatePartnerCircle("$partnerId",$lat,$lng,$radius,decodeURIComponent("$enc"),"$color")');
  }

  void clearPartnerCircle(String partnerId) {
    _ctrl?.runJavaScript('clearPartnerCircle("$partnerId")');
  }

  void setDrawMode(bool isDrawMode) {
    _ctrl?.runJavaScript('setDrawMode($isDrawMode)');
  }

  void setCenter(double lat, double lng, {int level = 6}) {
    _ctrl?.runJavaScript('setMapCenter($lat,$lng,$level)');
  }

  void moveToCurrentLocation() {
    _ctrl?.runJavaScript('moveToCurrentLocation()');
  }

  void showCurrentLocationDot(double lat, double lng) {
    _ctrl?.runJavaScript('updateCurrentLocationDot($lat,$lng)');
  }

  void addMessage(String userId, String userName, String message) {
    final encName = Uri.encodeComponent(userName);
    final encMsg  = Uri.encodeComponent(message);
    _ctrl?.runJavaScript(
        'addMessage("$userId",decodeURIComponent("$encName"),decodeURIComponent("$encMsg"))');
  }

  @override
  Widget build(BuildContext context) {
    return PlatformHtmlView(
      key: const ValueKey('kakao-map-webview'),
      html: _buildHtml(),
      webUrl: '/kakao_map_bridge.html?appkey=${widget.kakaoApiKey}',
      channels: {
        'CircleDrawnChannel': (msg) {
          final parts = msg.split(',');
          widget.onCircleDrawn(
            double.parse(parts[0]),
            double.parse(parts[1]),
            double.parse(parts[2]),
          );
        },
        'Console': (msg) => debugPrint('JS: $msg'),
        'MapReadyChannel': (_) => widget.onMapReady?.call(),
      },
      onCreated: (ctrl) => _ctrl = ctrl,
    );
  }

  String _buildHtml() => '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap" rel="stylesheet">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; font-family: "Noto Sans KR", -apple-system, "Apple SD Gothic Neo", system-ui, sans-serif; -webkit-user-select: none; -webkit-touch-callout: none; user-select: none; }
    body { width: 100vw; height: 100vh; overflow: hidden; background: #e8e8e8; }
    #map { width: 100%; height: 100%; }
    #canvas { position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 10; }
    #canvas.draw-mode { pointer-events: all; }
    #overlay-container { position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 20; }
    .bubble-wrap { position: absolute; display: flex; flex-direction: column; align-items: center; transform: translate(-50%, -100%); pointer-events: none; gap: 4px; padding-bottom: 6px; }
    .bubble { color: white; padding: 5px 10px; border-radius: 12px; font-size: 12px; white-space: nowrap; max-width: 160px; overflow: hidden; text-overflow: ellipsis; }
    .name-tag { background: rgba(0,0,0,0.5); color: white; padding: 2px 8px; border-radius: 8px; font-size: 11px; }
    .direction-pin { position: absolute; width: 48px; height: 48px; border-radius: 50%; display: flex; align-items: center; justify-content: center; flex-direction: column; font-size: 16px; font-weight: bold; color: white; cursor: pointer; pointer-events: all; box-shadow: 0 2px 8px rgba(0,0,0,0.3); transform: translate(-50%, -50%); transition: transform 0.32s cubic-bezier(0.34,1.56,0.64,1); -webkit-tap-highlight-color: transparent; }
    .direction-pin:active { transform: translate(-50%, -50%) scale(0.82); transition-duration: 0.06s; transition-timing-function: ease-in; }
    .direction-pin .pin-name { font-size: 9px; margin-top: 1px; }
    .direction-pin .pin-msg { position: absolute; bottom: 54px; left: 50%; transform: translateX(-50%); background: rgba(0,0,0,0.75); color: white; padding: 4px 8px; border-radius: 8px; font-size: 11px; white-space: normal; max-width: 130px; word-break: keep-all; text-align: center; pointer-events: none; }
    .curr-loc-wrap { position: relative; width: 20px; height: 20px; }
    .curr-loc-dot { position: absolute; top: 50%; left: 50%; transform: translate(-50%,-50%); width: 14px; height: 14px; border-radius: 50%; background: #4A8FD9; border: 2.5px solid white; box-shadow: 0 1px 4px rgba(0,0,0,0.4); z-index: 2; }
    .curr-loc-ring { position: absolute; top: 50%; left: 50%; transform: translate(-50%,-50%); width: 14px; height: 14px; border-radius: 50%; background: rgba(74,143,217,0.35); animation: curr-pulse 2s ease-out infinite; }
    @keyframes curr-pulse { 0% { transform: translate(-50%,-50%) scale(1); opacity: 1; } 100% { transform: translate(-50%,-50%) scale(3.2); opacity: 0; } }
  </style>
</head>
<body>
  <div id="map"></div>
  <canvas id="canvas"></canvas>
  <div id="overlay-container"></div>
  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=${widget.kakaoApiKey}"></script>
  <script>
    var map, myCircle;
    var isDrawMode = false, isDrawing = false, drawnPoints = [];
    var canvas = document.getElementById('canvas');
    var ctx = canvas.getContext('2d');
    var overlayContainer = document.getElementById('overlay-container');
    var circles = { my: { lat:null,lng:null,radius:null,userName:'',color:'#9D8EFF',messages:[] }, partners:{} };
    var partnerCircleObjects = {};
    var _currLocOverlay = null;

    kakao.maps.load(function() {
      Console.postMessage('kakao maps ready');
      canvas.width = window.innerWidth; canvas.height = window.innerHeight;
      map = new kakao.maps.Map(document.getElementById('map'), { center: new kakao.maps.LatLng(37.5665,126.9780), level:7 });
      myCircle = new kakao.maps.Circle({ map:null, center:new kakao.maps.LatLng(37.5665,126.9780), radius:3000, strokeWeight:2, strokeColor:'#9D8EFF', strokeOpacity:0.8, fillColor:'#9D8EFF', fillOpacity:0.2 });
      kakao.maps.event.addListener(map,'center_changed',updateAllOverlays);
      kakao.maps.event.addListener(map,'zoom_changed',function(){pinch=null;overlayContainer.style.opacity='1';updateAllOverlays();});
      var mapEl=document.getElementById('map');
      var pinch=null;
      function tdist(a,b){var dx=a.clientX-b.clientX,dy=a.clientY-b.clientY;return Math.sqrt(dx*dx+dy*dy);}
      mapEl.addEventListener('touchstart',function(e){if(e.touches.length===2){pinch={dist:tdist(e.touches[0],e.touches[1])};overlayContainer.style.opacity='0';}},{passive:true});
      canvas.addEventListener('touchstart',function(e){if(!isDrawMode)return;e.preventDefault();isDrawing=true;drawnPoints=[];ctx.clearRect(0,0,canvas.width,canvas.height);ctx.beginPath();ctx.strokeStyle='rgba(157,142,255,0.7)';ctx.lineWidth=3;ctx.lineCap='round';var t=e.touches[0],rect=canvas.getBoundingClientRect();ctx.moveTo(t.clientX-rect.left,t.clientY-rect.top);drawnPoints.push({x:t.clientX-rect.left,y:t.clientY-rect.top});},{passive:false});
      canvas.addEventListener('touchmove',function(e){if(!isDrawMode||!isDrawing)return;e.preventDefault();var t=e.touches[0],rect=canvas.getBoundingClientRect();ctx.lineTo(t.clientX-rect.left,t.clientY-rect.top);ctx.stroke();drawnPoints.push({x:t.clientX-rect.left,y:t.clientY-rect.top});},{passive:false});
      canvas.addEventListener('touchend',function(e){if(!isDrawMode||!isDrawing)return;isDrawing=false;if(drawnPoints.length<5)return;var cx=0,cy=0;drawnPoints.forEach(function(p){cx+=p.x;cy+=p.y;});cx/=drawnPoints.length;cy/=drawnPoints.length;var avgR=0;drawnPoints.forEach(function(p){avgR+=Math.sqrt((p.x-cx)*(p.x-cx)+(p.y-cy)*(p.y-cy));});avgR/=drawnPoints.length;ctx.clearRect(0,0,canvas.width,canvas.height);ctx.beginPath();ctx.arc(cx,cy,avgR,0,2*Math.PI);ctx.strokeStyle='rgba(157,142,255,0.9)';ctx.lineWidth=2;ctx.stroke();setTimeout(function(){ctx.clearRect(0,0,canvas.width,canvas.height);var proj=map.getProjection();var centerLatLng=proj.coordsFromContainerPoint(new kakao.maps.Point(cx,cy));var edgeLatLng=proj.coordsFromContainerPoint(new kakao.maps.Point(cx+avgR,cy));var R=6371000,dLat=(edgeLatLng.getLat()-centerLatLng.getLat())*Math.PI/180,dLng=(edgeLatLng.getLng()-centerLatLng.getLng())*Math.PI/180,a=Math.sin(dLat/2)*Math.sin(dLat/2)+Math.cos(centerLatLng.getLat()*Math.PI/180)*Math.cos(edgeLatLng.getLat()*Math.PI/180)*Math.sin(dLng/2)*Math.sin(dLng/2);var radiusMeters=R*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a));radiusMeters=Math.max(500,Math.min(20000,radiusMeters));myCircle.setPosition(centerLatLng);myCircle.setRadius(radiusMeters);myCircle.setMap(map);CircleDrawnChannel.postMessage(centerLatLng.getLat()+','+centerLatLng.getLng()+','+radiusMeters);},300);},{passive:false});
      document.addEventListener('contextmenu',function(e){e.preventDefault();});
      MapReadyChannel.postMessage('ready');
    });

    function hexToRgba(hex,alpha){var r=parseInt(hex.slice(1,3),16),g=parseInt(hex.slice(3,5),16),b=parseInt(hex.slice(5,7),16);return 'rgba('+r+','+g+','+b+','+alpha+')';}
    function updateAllOverlays(){overlayContainer.innerHTML='';if(circles.my.lat!==null){var sp=getScreenPos(circles.my.lat,circles.my.lng);if(isOnScreen(sp))renderBubbles(circles.my,sp,getCircleTopY(myCircle,circles.my.lat,circles.my.lng));else renderDirectionPin(circles.my,circles.my.lat,circles.my.lng);}Object.keys(circles.partners).forEach(function(pid){var c=circles.partners[pid];if(c.lat===null)return;var sp=getScreenPos(c.lat,c.lng);if(isOnScreen(sp))renderBubbles(c,sp,getCircleTopY(partnerCircleObjects[pid],c.lat,c.lng));else renderDirectionPin(c,c.lat,c.lng);});}
    function getScreenPos(lat,lng){var proj=map.getProjection(),pt=proj.containerPointFromCoords(new kakao.maps.LatLng(lat,lng));return{x:pt.x,y:pt.y};}
    function isOnScreen(pos){var m=80;return pos.x>-m&&pos.x<window.innerWidth+m&&pos.y>-m&&pos.y<window.innerHeight+m;}
    function getCircleTopY(circleObj,lat,lng){if(circleObj){var nb=circleObj.getBounds().getNorthEast().getLat();return getScreenPos(nb,lng).y;}return getScreenPos(lat,lng).y-40;}
    function renderBubbles(cd,sp,topY){var wrap=document.createElement('div');wrap.className='bubble-wrap';wrap.style.left=sp.x+'px';wrap.style.top=(topY-4)+'px';var nt=document.createElement('div');nt.className='name-tag';nt.innerText=cd.userName;wrap.appendChild(nt);var msgs=cd.messages.slice(-4);msgs.forEach(function(msg,i){var op=msgs.length===1?1.0:0.25+(i/(msgs.length-1))*0.75;var b=document.createElement('div');b.className='bubble';b.style.background=hexToRgba(cd.color,0.85);b.style.opacity=op;b.innerText=msg;wrap.insertBefore(b,nt);});overlayContainer.appendChild(wrap);}
    function renderDirectionPin(cd,lat,lng){var edge=getEdgePosition(getScreenPos(lat,lng));var pin=document.createElement('div');pin.className='direction-pin';pin.style.background=cd.color;pin.style.left=edge.x+'px';pin.style.top=edge.y+'px';var init=document.createElement('span');init.innerText=cd.userName?cd.userName[0]:'?';pin.appendChild(init);var ne=document.createElement('div');ne.className='pin-name';ne.innerText=cd.userName;pin.appendChild(ne);if(cd.messages.length>0){var me=document.createElement('div');me.className='pin-msg';me.innerText=cd.messages[cd.messages.length-1];pin.appendChild(me);}function pressIn(){pin.style.transform='translate(-50%,-50%) scale(0.82)';pin.style.transitionDuration='0.06s';pin.style.transitionTimingFunction='ease-in';}function pressOut(){pin.style.transform='translate(-50%,-50%) scale(1)';pin.style.transitionDuration='0.32s';pin.style.transitionTimingFunction='cubic-bezier(0.34,1.56,0.64,1)';}pin.addEventListener('touchstart',pressIn,{passive:true});pin.addEventListener('touchend',function(){pressOut();map.panTo(new kakao.maps.LatLng(lat,lng));},{passive:true});pin.addEventListener('touchcancel',pressOut,{passive:true});pin.addEventListener('mousedown',pressIn);pin.addEventListener('mouseup',function(){pressOut();map.panTo(new kakao.maps.LatLng(lat,lng));});pin.addEventListener('mouseleave',pressOut);overlayContainer.appendChild(pin);}
    function getEdgePosition(sp){var W=window.innerWidth,H=window.innerHeight,cx=W/2,cy=H/2,dx=sp.x-cx,dy=sp.y-cy,ml=60,mr=60,mt=140,mb=175,rx=W-mr-cx,lx=ml-cx,topY=mt-cy,botY=H-mb-cy,sx=dx!==0?(dx>0?rx:lx)/dx:Infinity,sy=dy!==0?(dy>0?botY:topY)/dy:Infinity,s=Math.min(Math.abs(sx),Math.abs(sy));return{x:Math.max(ml,Math.min(W-mr,cx+dx*s)),y:Math.max(mt,Math.min(H-mb,cy+dy*s))};}
    function updateMyCircle(lat,lng,radius,userName){circles.my.lat=lat;circles.my.lng=lng;circles.my.radius=radius;circles.my.userName=userName;myCircle.setPosition(new kakao.maps.LatLng(lat,lng));myCircle.setRadius(radius);myCircle.setMap(map);updateAllOverlays();}
    function clearPartnerCircle(partnerId){if(partnerCircleObjects[partnerId]){partnerCircleObjects[partnerId].setMap(null);delete partnerCircleObjects[partnerId];}delete circles.partners[partnerId];updateAllOverlays();}
    function updatePartnerCircle(partnerId,lat,lng,radius,userName,color){if(!circles.partners[partnerId])circles.partners[partnerId]={lat:null,lng:null,radius:null,userName:'',color:color,messages:[]};var c=circles.partners[partnerId];c.lat=lat;c.lng=lng;c.radius=radius;c.userName=userName;c.color=color;if(partnerCircleObjects[partnerId]){partnerCircleObjects[partnerId].setPosition(new kakao.maps.LatLng(lat,lng));partnerCircleObjects[partnerId].setRadius(radius);}else{partnerCircleObjects[partnerId]=new kakao.maps.Circle({map:map,center:new kakao.maps.LatLng(lat,lng),radius:radius,strokeWeight:2,strokeColor:color,strokeOpacity:0.8,fillColor:color,fillOpacity:0.2});}updateAllOverlays();}
    function addMessage(userId,userName,message){var cd=null;if(circles.my.userName===userName){cd=circles.my;}else{var keys=Object.keys(circles.partners);for(var i=0;i<keys.length;i++){if(circles.partners[keys[i]].userName===userName){cd=circles.partners[keys[i]];break;}}if(!cd&&circles.partners[userId])cd=circles.partners[userId];}if(!cd)return;cd.messages.push(message);if(cd.messages.length>4)cd.messages.shift();updateAllOverlays();setTimeout(function(){cd.messages.shift();updateAllOverlays();},5000);}
    function setDrawMode(enabled){isDrawMode=enabled;canvas.className=enabled?'draw-mode':'';if(!enabled)ctx.clearRect(0,0,canvas.width,canvas.height);Console.postMessage('drawMode: '+enabled);}
    function setMapCenter(lat,lng,level){map.setCenter(new kakao.maps.LatLng(lat,lng));if(level)map.setLevel(level);}
    function updateCurrentLocationDot(lat,lng){var pos=new kakao.maps.LatLng(lat,lng);if(_currLocOverlay){_currLocOverlay.setPosition(pos);}else{_currLocOverlay=new kakao.maps.CustomOverlay({map:map,position:pos,content:'<div class="curr-loc-wrap"><div class="curr-loc-ring"></div><div class="curr-loc-dot"></div></div>',zIndex:5,yAnchor:0.5,xAnchor:0.5});}}
    function moveToCurrentLocation(){if(!navigator.geolocation)return;navigator.geolocation.getCurrentPosition(function(pos){map.setCenter(new kakao.maps.LatLng(pos.coords.latitude,pos.coords.longitude));map.setLevel(5);updateCurrentLocationDot(pos.coords.latitude,pos.coords.longitude);},function(){},{timeout:5000,maximumAge:60000});}
  </script>
</body>
</html>
''';
}
