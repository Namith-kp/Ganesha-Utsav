class StreetViewNode {
  final String id;
  final double lat;
  final double lon;
  final double elevation;
  final double heading;
  final double pitch;
  final double roll;
  final String date;
  final String address;
  final List<String> neighbors;

  StreetViewNode({
    required this.id,
    required this.lat,
    required this.lon,
    required this.elevation,
    required this.heading,
    required this.pitch,
    required this.roll,
    required this.date,
    required this.address,
    required this.neighbors,
  });

  factory StreetViewNode.fromJson(Map<String, dynamic> json) {
    return StreetViewNode(
      id: json['id'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      elevation: (json['elevation'] as num).toDouble(),
      heading: (json['heading'] as num).toDouble(),
      pitch: (json['pitch'] as num).toDouble(),
      roll: (json['roll'] as num).toDouble(),
      date: json['date'] as String? ?? '',
      address: json['address'] as String? ?? '',
      neighbors:
          (json['neighbors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}
