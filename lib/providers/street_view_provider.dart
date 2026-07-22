import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/street_view_node.dart';

const String baseUrl = 'https://pub-2e6c9cb2a1eb4eb98c8bae3105ebf165.r2.dev';

// Provides the list of all street view nodes parsed from the JSON
final streetViewNodesProvider = FutureProvider<List<StreetViewNode>>((
  ref,
) async {
  // Try mapped_metadata first, fallback to metadata
  final url = Uri.parse('$baseUrl/mapped_metadata.json');
  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final List<dynamic> jsonList = json.decode(response.body);
      return jsonList.map((e) => StreetViewNode.fromJson(e)).toList();
    }
  } catch (e) {
    print('Failed to load mapped_metadata.json: $e');
  }

  // Fallback
  final fallbackUrl = Uri.parse('$baseUrl/metadata.json');
  final response = await http.get(fallbackUrl);
  if (response.statusCode == 200) {
    final List<dynamic> jsonList = json.decode(response.body);
    return jsonList.map((e) => StreetViewNode.fromJson(e)).toList();
  } else {
    throw Exception('Failed to load metadata');
  }
});

// A provider that can be used to query a specific node by ID quickly
final nodeByIdProvider = Provider.family<StreetViewNode?, String>((ref, id) {
  final nodesAsync = ref.watch(streetViewNodesProvider);
  return nodesAsync.maybeWhen(
    data: (nodes) {
      try {
        return nodes.firstWhere((node) => node.id == id);
      } catch (_) {
        return null;
      }
    },
    orElse: () => null,
  );
});

class CurrentPanoramaIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void updateId(String? newId) {
    state = newId;
  }
}

// Tracks the ID of the panorama the user is currently viewing
final currentPanoramaIdProvider =
    NotifierProvider<CurrentPanoramaIdNotifier, String?>(
      CurrentPanoramaIdNotifier.new,
    );

// A listener provider that handles the predictive pre-fetching
final prefetchControllerProvider = Provider<void>((ref) {
  final currentId = ref.watch(currentPanoramaIdProvider);
  if (currentId == null) return;

  final currentNode = ref.read(nodeByIdProvider(currentId));
  if (currentNode == null) return;

  // CacheManager uses sqflite/path_provider and does not support web out of the box
  if (kIsWeb) return;

  // Prefetch the current node just in case
  DefaultCacheManager().downloadFile('$baseUrl/$currentId.webp');

  // Silently pre-fetch all neighboring images into cache
  for (final neighborId in currentNode.neighbors) {
    final neighborUrl = '$baseUrl/$neighborId.webp';
    // Using DefaultCacheManager to download and cache the file without blocking UI
    DefaultCacheManager().downloadFile(neighborUrl);
  }
});
