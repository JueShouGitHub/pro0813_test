import 'package:adjust_sdk/adjust.dart';
import 'package:adjust_sdk/adjust_config.dart';
import 'package:advertising_id/advertising_id.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';

var appsflyerSdk;

///需要几个参数： 是否需要推送功能、推送的token
Future<void> initPush(bool isPush, String appId) async {
  OneSignal.initialize(appId);
  OneSignal.Notifications.requestPermission(true);
}

///需要几个参数： 是否需要推送功能、推送的token
Future<void> initAdjust(String sdkKey) async {
  final config = AdjustConfig(sdkKey, AdjustEnvironment.sandbox);
  config.logLevel = AdjustLogLevel.verbose;
  Adjust.initSdk(config);
}

///需要几个参数： 是否需要推送功能、推送的token
Future<AppsflyerSdk> initAppsflyer(String afDevKey, String appId) async {
  AppsFlyerOptions appsFlyerOptions = AppsFlyerOptions(
    afDevKey: afDevKey,
    appId: appId,
    showDebug: false,
    timeToWaitForATTUserAuthorization: 50, // for iOS 14.5
    disableAdvertisingIdentifier: false, // Optional field
    disableCollectASA: false, //Optional field
  ); // Optional field

  appsflyerSdk = AppsflyerSdk(appsFlyerOptions);
  appsflyerSdk.startSDK();

  return appsflyerSdk;
}

Future<String> getS2SAdUrl(String toUrl, String sdkKey) async {
  toUrl += toUrl.contains('?') ? '&' : '?';

  final adid = await Adjust.getAdid();
  final advertisingId = await AdvertisingId.id(true);
  return toUrl += 'ad_app_token=$sdkKey&gps_adid=$advertisingId&idfa=$adid&adid=$adid';
}
