import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class PbEnum {
  final int value;
  PbEnum(this.value);
}

class PbTuple {
  final int childCount;
  final String serialized;
  PbTuple(this.childCount, this.serialized);
}

class StreetViewLink {
  final String panoid;
  final double lat;
  final double lon;
  final double yaw;

  StreetViewLink({
    required this.panoid,
    required this.lat,
    required this.lon,
    required this.yaw,
  });
}

class StreetViewPanorama {
  final String id;
  final double lat;
  final double lon;
  final double heading;
  final List<StreetViewLink> links;

  StreetViewPanorama({
    required this.id,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.links,
  });
}

class StreetViewService {
  final Map<String, Uint8List> _imageCache = {};
  final Map<String, StreetViewPanorama> _panoCache = {};
  static const int _maxCacheSize = 15;

  void _addToCache(String panoid, Uint8List data) {
    _imageCache[panoid] = data;
    if (_imageCache.length > _maxCacheSize) {
      _imageCache.remove(_imageCache.keys.first);
    }
  }

  void clearCache() {
    _imageCache.clear();
    _panoCache.clear();
  }

  Future<void> prefetchPanoramas(List<String> panoids, {int zoom = 2}) async {
    for (var panoid in panoids) {
      if (!_imageCache.containsKey(panoid)) {
        // Run in background without awaiting the whole loop
        downloadPanoramaImage(panoid, zoom: zoom).then((data) {
          // data is already cached inside downloadPanoramaImage
        }).catchError((e) {
          debugPrint('Prefetch failed for $panoid: $e');
        });
      }
    }
  }
  String toProtobufUrl(Map<int, dynamic> fields) {
    return _toProtobufUrl(fields).serialized;
  }

  PbTuple _toProtobufUrl(Map<int, dynamic> fields) {
    String serialized = "";
    int childCount = 0;
    for (var entry in fields.entries) {
      final res = _fieldToString(entry.key, entry.value);
      serialized += res.serialized;
      childCount += res.childCount;
    }
    return PbTuple(childCount, serialized);
  }

  PbTuple _messageToString(int tag, Map<int, dynamic> value) {
    final res = _toProtobufUrl(value);
    final serialized = "!${tag}m${res.childCount}${res.serialized}";
    return PbTuple(res.childCount + 1, serialized);
  }

  PbTuple _listToString(int tag, List<dynamic> value) {
    String serialized = "";
    int childCount = 0;
    for (var entry in value) {
      final res = _fieldToString(tag, entry);
      serialized += res.serialized;
      childCount += res.childCount;
    }
    return PbTuple(childCount, serialized);
  }

  PbTuple _fieldToString(int tag, dynamic value) {
    if (value is List) {
      return _listToString(tag, value);
    } else if (value is Map<int, dynamic>) {
      return _messageToString(tag, value);
    } else if (value is bool) {
      return PbTuple(1, "!${tag}b${value ? 1 : 0}");
    } else if (value is PbEnum) {
      return PbTuple(1, "!${tag}e${value.value}");
    } else if (value is int) {
      return PbTuple(1, "!${tag}i$value");
    } else if (value is double) {
      return PbTuple(1, "!${tag}d$value");
    } else if (value is String) {
      return PbTuple(1, "!${tag}s$value");
    } else {
      throw Exception("Unknown type ${value.runtimeType}");
    }
  }

  String buildFindPanoramaRequestUrl(double lat, double lon, double radius) {
    final toggles = [
      PbEnum(1), PbEnum(2), PbEnum(3), PbEnum(4), PbEnum(6), PbEnum(8), PbEnum(12)
    ];
    
    final searchMessage = <int, dynamic>{
      1: {
        1: 'apiv3',
        5: 'US',
        11: {1: {1: false}}
      },
      2: {
        1: {3: lat, 4: lon}, 
        2: radius
      },
      3: {
        2: {1: 'en', 2: 'US'},
        9: {1: PbEnum(2)},
        11: {
          1: {1: PbEnum(2), 2: true, 3: PbEnum(2)}
        },
      },
      4: {
        1: toggles,
        5: {1: PbEnum(2)},
        6: {1: PbEnum(2)},
      }
    };
    
    final pbString = toProtobufUrl(searchMessage);
    return "https://maps.googleapis.com/maps/api/js/GeoPhotoService.SingleImageSearch?pb=$pbString&callback=_xdc_._v2mub5";
  }

  Future<StreetViewPanorama?> findPanoramaByLink(StreetViewLink link) async {
    if (_panoCache.containsKey(link.panoid)) {
      return _panoCache[link.panoid];
    }
    try {
      final pano = await findPanorama(link.lat, link.lon, radius: 50.0);
      if (pano != null) {
        _panoCache[pano.id] = pano;
        // Just in case the returned id is slightly different from link.panoid, cache it under both
        if (pano.id != link.panoid) {
          _panoCache[link.panoid] = pano;
        }
      }
      return pano;
    } catch (e) {
      debugPrint('Error finding panorama by link: $e');
      rethrow;
    }
  }

  Future<StreetViewPanorama?> findPanorama(double lat, double lon, {double radius = 1000.0}) async {
    try {
      final url = buildFindPanoramaRequestUrl(lat, lon, radius);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception("API returned status code ${response.statusCode}");
      }
      
      final text = response.body;
      final firstParen = text.indexOf("(");
      final lastParen = text.lastIndexOf(")");
      if (firstParen == -1 || lastParen == -1) {
        throw Exception("Invalid JSONP format: $text");
      }
      
      final jsonString = "[${text.substring(firstParen + 1, lastParen)}]";
      final data = json.decode(jsonString) as List;
      
      final responseCode = data[0][0][0];
      if (responseCode != 0) {
        throw Exception("Google Maps returned error code $responseCode. Data: $data");
      }
      
      final msg = data[0][1];
      if (msg == null || msg.length < 2) {
        throw Exception("Missing message data in response: $data");
      }
      
      final pano = _parsePanoramaMsg(msg);
      _panoCache[pano.id] = pano;
      return pano;
    } catch (e) {
      debugPrint('Error finding panorama: $e');
      rethrow;
    }
  }

  StreetViewPanorama _parsePanoramaMsg(List<dynamic> msg) {
    final panoid = msg[1][1] as String;
    
    final latResponse = (msg[5][0][1][0][2] as num).toDouble();
    final lonResponse = (msg[5][0][1][0][3] as num).toDouble();
    final heading = (msg[5][0][1][2][0] as num).toDouble(); // degrees
    
    List<StreetViewLink> links = [];
    try {
      final linksList = msg[5][0][3][0] as List?;
      if (linksList != null) {
        // Collect all links with their distances
        List<Map<String, dynamic>> allLinks = [];
        for (var l in linksList) {
          final pId = l[0][1] as String;
          final lLat = (l[2][0][2] as num).toDouble();
          final lLon = (l[2][0][3] as num).toDouble();
          final lYaw = (l[2][2][0] as num).toDouble();
          
          final distance = _calculateDistance(latResponse, lonResponse, lLat, lLon);
          if (distance > 1.0) { // Skip self or virtually identical locations
            allLinks.add({
              'panoid': pId,
              'lat': lLat,
              'lon': lLon,
              'yaw': lYaw,
              'distance': distance,
            });
          }
        }
        
        // Sort by distance ascending so we evaluate closest first
        allLinks.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
        
        for (var l in allLinks) {
          final lYaw = l['yaw'] as double;
          
          // Skip panoramas that are in a very similar direction to ones we already picked
          bool tooCloseInAngle = false;
          for (var existing in links) {
            double diff = (existing.yaw - lYaw).abs();
            diff = diff > 180 ? 360 - diff : diff;
            if (diff < 45.0) {
              tooCloseInAngle = true;
              break;
            }
          }
          
          if (!tooCloseInAngle) {
            links.add(StreetViewLink(
              panoid: l['panoid'] as String,
              lat: l['lat'] as double,
              lon: l['lon'] as double,
              yaw: lYaw,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Could not parse some links: $e');
    }
    
    return StreetViewPanorama(
      id: panoid,
      lat: latResponse,
      lon: lonResponse,
      heading: heading,
      links: links,
    );
  }

  Future<Uint8List?> downloadPanoramaImage(String panoid, {int zoom = 2}) async {
    if (_imageCache.containsKey(panoid)) {
      return _imageCache[panoid];
    }
    
    try {
      int tileWidth = 512;
      int tileHeight = 512;
      int cols = pow(2, zoom).toInt();
      int rows = pow(2, zoom - 1).toInt();
      
      final baseImage = img.Image(width: cols * tileWidth, height: rows * tileHeight);
      
      final client = http.Client();
      final futures = <Future>[];
      
      for (int y = 0; y < rows; y++) {
        for (int x = 0; x < cols; x++) {
          futures.add(() async {
            final url = "https://streetviewpixels-pa.googleapis.com/v1/tile?cb_client=maps_sv.tactile&panoid=$panoid&x=$x&y=$y&zoom=$zoom";
            final response = await client.get(Uri.parse(url));
            if (response.statusCode == 200) {
              final tileImg = img.decodeImage(response.bodyBytes);
              if (tileImg != null) {
                img.compositeImage(baseImage, tileImg, dstX: x * tileWidth, dstY: y * tileHeight);
              }
            }
          }());
        }
      }
      
      await Future.wait(futures);
      client.close();
      
      final result = Uint8List.fromList(img.encodeJpg(baseImage, quality: 85));
      _addToCache(panoid, result);
      return result;
    } catch (e) {
      debugPrint('Error downloading panorama: $e');
      return null;
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a)) * 1000;
  }
}
