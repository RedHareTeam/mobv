import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

typedef ChannelHandler = void Function(String message);

int _viewCounter = 0;

class PlatformHtmlViewController {
  final html.IFrameElement _iframe;
  PlatformHtmlViewController(this._iframe);

  Future<void> runJavaScript(String js) async {
    _iframe.contentWindow?.postMessage({'__eval': js}, '*');
  }
}

class PlatformHtmlView extends StatefulWidget {
  final String html;
  final String webUrl;
  final Map<String, ChannelHandler> channels;
  final void Function(PlatformHtmlViewController)? onCreated;

  const PlatformHtmlView({
    super.key,
    required this.html,
    required this.webUrl,
    this.channels = const {},
    this.onCreated,
  });

  @override
  State<PlatformHtmlView> createState() => _PlatformHtmlViewState();
}

class _PlatformHtmlViewState extends State<PlatformHtmlView> {
  late final String _viewType;
  late final html.IFrameElement _iframe;
  StreamSubscription? _msgSub;

  @override
  void initState() {
    super.initState();
    _viewType = 'platform-html-view-${_viewCounter++}';

    _iframe = html.IFrameElement()
      ..src = widget.webUrl
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'geolocation';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _iframe);

    _msgSub = html.window.onMessage.listen((event) {
      final data = event.data;
      if (data is Map) {
        final ch = data['__channel'] as String?;
        final msg = (data['__data'] as String?) ?? '';
        if (ch != null) widget.channels[ch]?.call(msg);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCreated?.call(PlatformHtmlViewController(_iframe));
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
