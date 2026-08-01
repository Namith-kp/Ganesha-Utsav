import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

// A listener provider that handles predictive pre-fetching for instant image switching
final prefetchControllerProvider = Provider.family<void, BuildContext?>((ref, context) {
  final currentId = ref.watch(currentPanoramaIdProvider);
  if (currentId == null) return;

  final currentNode = ref.read(nodeByIdProvider(currentId));
  if (currentNode == null) return;

  void prefetchUrl(String id) {
    final imgUrl = '$baseUrl/$id.webp';
    final provider = CachedNetworkImageProvider(imgUrl);

    // Warm Flutter's in-memory texture/ImageCache (works on both Web & Native)
    if (context != null) {
      precacheImage(provider, context).catchError((_) {});
    }

    // Disk cache on native
    if (!kIsWeb) {
      DefaultCacheManager().downloadFile(imgUrl);
    }
  }

  // 1. Prefetch current node
  prefetchUrl(currentId);

  // 2. Prefetch all immediate 1-hop neighbors
  for (final neighborId in currentNode.neighbors) {
    prefetchUrl(neighborId);

    // 3. Prefetch 2-hop neighbors for ultra-fast continuous street walking
    final neighborNode = ref.read(nodeByIdProvider(neighborId));
    if (neighborNode != null) {
      for (final hop2Id in neighborNode.neighbors) {
        if (hop2Id != currentId) {
          prefetchUrl(hop2Id);
        }
      }
    }
  }
});
