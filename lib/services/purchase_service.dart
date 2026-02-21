import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config.dart';

class PurchaseService {
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;
  PurchaseService._internal();

  static const String entitlementId = 'pro';

  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  CustomerInfo? _customerInfo;
  Offerings? _offerings;

  bool get isInitialized => _isInitialized;
  CustomerInfo? get customerInfo => _customerInfo;
  Offerings? get offerings => _offerings;

  /// Whether the user has an active premium entitlement (alias for isProUser)
  bool get isPremium {
    if (_customerInfo == null) return false;
    return _customerInfo!.entitlements.all[entitlementId]?.isActive ?? false;
  }

  /// Whether the user has an active pro entitlement
  Future<bool> isProUser() async {
    if (!_isInitialized) await _waitForInit();
    if (!_isInitialized) return false;
    await refreshCustomerInfo();
    return isPremium;
  }

  Future<void> _waitForInit() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
    }
  }

  /// Initialize RevenueCat SDK. Call with [appUserId] when user is logged in
  /// (e.g. Firebase UID) to link purchases; pass null for anonymous/guest.
  Future<void> initialize({String? appUserId}) async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();

    try {
      final apiKey = Platform.isAndroid
          ? Config.revenueCatGoogleApiKey
          : Config.revenueCatAppleApiKey;

      if (apiKey.isEmpty) {
        debugPrint('⚠️ RevenueCat API Key is empty. Purchases will be disabled.');
        _isInitialized = false;
        _initCompleter!.complete();
        return;
      }

      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }

      PurchasesConfiguration configuration = PurchasesConfiguration(apiKey)
        ..appUserID = appUserId;

      await Purchases.configure(configuration);
      _isInitialized = true;

      await refreshCustomerInfo();
      await fetchOfferings();

      debugPrint('RevenueCat initialized successfully');
    } catch (e) {
      debugPrint('Error initializing RevenueCat: $e');
      _isInitialized = false;
    } finally {
      if (!_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    }
  }

  /// Refresh customer information from RevenueCat
  Future<CustomerInfo?> refreshCustomerInfo() async {
    if (!_isInitialized) await _waitForInit();
    if (!_isInitialized) return null;

    try {
      _customerInfo = await Purchases.getCustomerInfo();
      return _customerInfo;
    } catch (e) {
      debugPrint('Error fetching customer info: $e');
      return null;
    }
  }

  /// Fetch available offerings
  Future<Offerings?> fetchOfferings() async {
    if (!_isInitialized) await _waitForInit();
    if (!_isInitialized) return null;

    try {
      _offerings = await Purchases.getOfferings();
      return _offerings;
    } catch (e) {
      debugPrint('Error fetching offerings: $e');
      return null;
    }
  }

  /// Make a purchase using a Package
  Future<bool> purchasePackage(Package package) async {
    if (!_isInitialized) await _waitForInit();
    if (!_isInitialized) {
      debugPrint('RevenueCat not initialized. Cannot purchase.');
      return false;
    }

    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _customerInfo = result.customerInfo;
      return isPremium;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('Purchase cancelled by user');
        return false;
      }
      debugPrint('Error purchasing package: $e');
      rethrow;
    } catch (e) {
      debugPrint('Error purchasing package: $e');
      rethrow;
    }
  }

  /// Restore past purchases
  Future<bool> restorePurchases() async {
    if (!_isInitialized) await _waitForInit();
    if (!_isInitialized) return false;

    try {
      _customerInfo = await Purchases.restorePurchases();
      return isPremium;
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      return false;
    }
  }

  /// Log out (useful if you have a user system)
  Future<void> logOut() async {
    if (!_isInitialized) await _waitForInit();
    if (!_isInitialized) return;

    try {
      _customerInfo = await Purchases.logOut();
    } catch (e) {
      debugPrint('Error logging out from RevenueCat: $e');
    }
  }

  /// Sync user ID (e.g. Firebase UID) with RevenueCat
  Future<void> logIn(String appUserId) async {
    if (!_isInitialized) await _waitForInit();
    if (!_isInitialized) return;

    try {
      final result = await Purchases.logIn(appUserId);
      _customerInfo = result.customerInfo;
    } catch (e) {
      debugPrint('Error logging in to RevenueCat: $e');
    }
  }
}
