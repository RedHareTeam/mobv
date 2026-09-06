import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef ChannelHandler = void Function(String message);

class PlatformHtmlViewController {
  final WebViewController _wvc;
  PlatformHtmlViewController(this._wvc);
  Future<void> runJavaScript(String js) => _wvc.runJavaScript(js);
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
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    for (final e in widget.channels.entries) {
      _controller.addJavaScriptChannel(
        e.key,
        onMessageReceived: (msg) => e.value(msg.message),
      );
    }
    _controller.loadHtmlString(widget.html);
    widget.onCreated?.call(PlatformHtmlViewController(_controller));
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
