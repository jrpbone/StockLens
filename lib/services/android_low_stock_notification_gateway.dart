import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/product.dart';
import 'low_stock_notification_service.dart';

class AndroidLowStockNotificationGateway
    implements LowStockNotificationGateway {
  AndroidLowStockNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
    required this.onNotificationOpened,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'stocklens_low_stock';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      'Low stock alerts',
      channelDescription: 'Alerts when a product reaches its stock threshold.',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  final Future<void> Function(String productId) onNotificationOpened;

  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('launch_background'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final productId = response.payload;
        if (productId != null && productId.isNotEmpty) {
          unawaited(onNotificationOpened(productId));
        }
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            'Low stock alerts',
            description: 'Alerts when a product reaches its stock threshold.',
            importance: Importance.high,
          ),
        );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final productId = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        productId != null &&
        productId.isNotEmpty) {
      await onNotificationOpened(productId);
    }
  }

  Future<bool> requestPermission() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission() ??
      false;

  Future<bool> notificationsEnabled() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled() ??
      false;

  Future<bool> openNotificationSettings() async =>
      await _plugin.openAppNotificationSettings() ?? false;

  @override
  Future<void> showLowStock(Product product) => _plugin.show(
    id: product.id.hashCode,
    title: 'Low stock',
    body: '${product.name}: ${product.quantity} remaining',
    notificationDetails: _details,
    payload: product.id,
  );
}
