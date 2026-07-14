class Collector {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? assignedArea;
  final String role; // 'admin' or 'collector'

  Collector({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.assignedArea,
    required this.role,
  });

  factory Collector.fromMap(Map<String, dynamic> map, String id) {
    return Collector(
      id: id,
      name: map['name'] as String? ?? 'Unknown',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String?,
      assignedArea: map['assignedArea'] as String?,
      role: map['role'] as String? ?? 'collector',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'assignedArea': assignedArea,
      'role': role,
    };
  }
}
