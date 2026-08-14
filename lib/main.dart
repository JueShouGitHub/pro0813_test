import 'dart:math';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:advertising_id/advertising_id.dart';

import 'bubble_pop_game.dart';

void main() {
  runApp(const MainApp());
}

final dio = Dio();
final _random = Random();

/// 生成12位随机字符串
String rs(int length) {
  return List.generate(length, (_) => _random.nextInt(36).toRadixString(36)).join();
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  Future<dynamic> getData() async {
    final host = 'https://www.m3n6b9v2c5x.xyz';
    final packageInfo = await PackageInfo.fromPlatform();
    final packageName = packageInfo.packageName;

    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final referrer = await AndroidPlayInstallReferrer.installReferrer;
    final timeZone = await FlutterTimezone.getLocalTimezone();
    final userAgent = await InAppWebViewController.getDefaultUserAgent();
    final advertisingId = await AdvertisingId.id(true);

    Response response;
    var data = {
      'android_id': deviceInfo.id,
      'gps_adid': advertisingId,
      'install_referrer': referrer.installReferrer,
      'timeZone': timeZone.identifier,
      'locales': PlatformDispatcher.instance.locale.toString(),
    };
    var options = Options(
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': userAgent,
      },
    );
    response = await dio.post(
      '$host/${rs(12)}e/$packageName/${rs(12)}',
      data: data,
      options: options,
    );
    return response.data;
  }

  @override
  Widget build(BuildContext context) {
    final result = getData();
    debugPrint(result.toString());

    return MaterialApp(home: BubblePopApp());
  }
}
