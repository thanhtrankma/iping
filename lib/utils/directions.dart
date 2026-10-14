import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/common.dart';

/// Link chỉ đường tới một toạ độ: Apple Maps trên iOS, Google Maps trên nền tảng khác.
Uri directionsUri(double lat, double lng, {required bool ios}) {
  final dest = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
  return ios
      ? Uri.https('maps.apple.com', '/', {'daddr': dest, 'dirflg': 'd'})
      : Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': dest, 'travelmode': 'driving'});
}

/// Mở ứng dụng bản đồ để chỉ đường; báo lỗi nếu không mở được.
Future<void> openDirections(BuildContext context, double lat, double lng) async {
  final uri = directionsUri(lat, lng, ios: defaultTargetPlatform == TargetPlatform.iOS);
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) showMessage(context, 'Không mở được ứng dụng bản đồ.');
}
