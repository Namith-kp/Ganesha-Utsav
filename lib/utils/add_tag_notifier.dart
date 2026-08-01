import 'dart:async';
import 'package:flutter/foundation.dart';

/// Draft details entered by the user before setting location on map.
class PendingTagData {
  final String name;
  final bool isApartment;
  final int unitsCount;

  PendingTagData({
    required this.name,
    required this.isApartment,
    required this.unitsCount,
  });
}

/// A broadcast stream and state notifier for "Add Tag" location picking mode.
class HomeScreenAddTagNotifier {
  static final StreamController<PendingTagData?> _controller =
      StreamController<PendingTagData?>.broadcast();

  /// Listens for trigger requests with draft data
  static Stream<PendingTagData?> get stream => _controller.stream;

  /// Holds the current active state of location picking mode
  static final ValueNotifier<bool> isPickingLocation =
      ValueNotifier<bool>(false);

  /// Current pending tag data being placed on map
  static PendingTagData? pendingData;

  static void startPicking(PendingTagData data) {
    pendingData = data;
    isPickingLocation.value = true;
    _controller.add(data);
  }

  static void cancelPicking() {
    pendingData = null;
    isPickingLocation.value = false;
  }

  static void setPicking(bool active) {
    if (!active) pendingData = null;
    isPickingLocation.value = active;
  }
}
