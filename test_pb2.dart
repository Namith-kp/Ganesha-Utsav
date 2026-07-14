import 'dart:convert';
import 'package:http/http.dart' as http;

class PbEnum {
  final int value;
  PbEnum(this.value);
}

class PbTuple {
  final int childCount;
  final String serialized;
  PbTuple(this.childCount, this.serialized);
}

class StreetViewService {
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

  String buildFindPanoramaRequestUrl(double lat, double lon, int radius) {
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
        5: <int, dynamic>{}, // This is what the app uses
        6: <int, dynamic>{}, // This is what the app uses
      }
    };
    
    final pbString = toProtobufUrl(searchMessage);
    return "https://maps.googleapis.com/maps/api/js/GeoPhotoService.SingleImageSearch?pb=$pbString&callback=_xdc_._v2mub5";
  }
}

void main() async {
  final s = StreetViewService();
  final url = s.buildFindPanoramaRequestUrl(37.422, -122.084, 1000);
  print(url);
  final response = await http.get(Uri.parse(url));
  print(response.statusCode);
  print(response.body);
}
