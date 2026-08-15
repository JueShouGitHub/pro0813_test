import 'dart:collection';
import 'dart:convert';

import 'package:adjust_sdk/adjust.dart';
import 'package:adjust_sdk/adjust_event.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:bubble_pop/inite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class Bscreen extends StatefulWidget {
  final String toUrl;
  final String userAgent;
  final String config;
  final String eventType;
  const Bscreen({
    super.key,
    required this.toUrl,
    required this.userAgent,
    required this.config,
    required this.eventType,
  });

  @override
  State<Bscreen> createState() => _BscreenState();
}

class _BscreenState extends State<Bscreen> {
  InAppWebViewController? webViewController;
  bool isLoading = true;

  void registerJavaScriptHandlers() {
    webViewController?.addJavaScriptHandler(
      handlerName: 'native',
      callback: (data) {
        debugPrint('native event : $data');
        Map<String, dynamic> map = json.decode(data[0]);
        var event = map['event'];
        if (event == 'openWindow') {
          var url = map['params']['url'];
          debugPrint('打开页面 : $url');
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).then((value) {
            if (!value) {
              debugPrint('打开页面 : $url 失败');
            }
          });
        } else {
          if (widget.eventType == 'ad') {
            // adjust
            AdjustEvent adjustEvent = AdjustEvent(event);
            if (map['params'].isNotEmpty && map['params']['revenue'] != null) {
              //adjustEvent.revenue = map['params']['revenue'];
              adjustEvent.setRevenue(
                double.parse(map['params']['revenue']),
                map['params']['currency'],
              );
            }
            Adjust.trackEvent(adjustEvent);
          } else {
            // appsflyer
            appsflyerSdk?.logEvent(event, map['params']);
          }
        }
      },
    );
  }

  Future<bool> handleBack() async {
    final controller = webViewController;
    if (controller == null) {
      return true;
    }
    final canGoBack = await controller.canGoBack();
    if (canGoBack) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (webViewController == null) return;
        final canGoBack = await webViewController?.canGoBack();
        if (canGoBack!) {
          await webViewController?.goBack();
        }

        // final shouldExit = await handleBack();
        // if (shouldExit && mounted) {
        //   Navigator.of(context).pop();
        // }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.toUrl)),
              initialSettings: InAppWebViewSettings(
                userAgent: widget.userAgent,
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              onWebViewCreated: (controller) {
                webViewController = controller;
                registerJavaScriptHandlers();
              },
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: widget.config,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                UserScript(
                  source: widget.config,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                ),
              ]),
              onCreateWindow: (controller, createWindowAction) async {
                final url = createWindowAction.request.url;
                if (url != null) {
                  await controller.loadUrl(urlRequest: URLRequest(url: url));
                }
                return true;
              },
              shouldOverrideUrlLoading: (controller, request) async {
                final url = request.request.url;
                if (url != null && url.path.toLowerCase().endsWith('.apk')) {
                  debugPrint('拦截 APK: $url');

                  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                    throw Exception('Could not launch $url');
                  }

                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStop: (controller, urlRequest) {
                setState(() => isLoading = false);
              },
            ),
            if (isLoading)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('loading...', style: TextStyle(color: Colors.white)),
                        const SizedBox(height: 10),
                        const SizedBox(
                          height: 1,
                          width: 100,
                          child: LinearProgressIndicator(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
