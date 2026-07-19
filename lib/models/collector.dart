class Collector {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? assignedArea;
  final String role; // 'admin', 'collector', 'team_member', or 'viewer'
  final bool isCoreTeamMember;
  final String? photoUrl;

  Collector({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.assignedArea,
    required this.role,
    this.isCoreTeamMember = false,
    this.photoUrl,
  });

  factory Collector.fromMap(Map<String, dynamic> map, String id) {
    return Collector(
      id: id,
      name: map['name'] as String? ?? 'Unknown',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String?,
      assignedArea: map['assignedArea'] as String?,
      role: map['role'] as String? ?? 'viewer',
      isCoreTeamMember: map['isCoreTeamMember'] as bool? ?? false,
      photoUrl: map['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'assignedArea': assignedArea,
      'role': role,
      'isCoreTeamMember': isCoreTeamMember,
      'photoUrl': photoUrl,
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isCollector => role == 'collector';
  bool get isTeamMember => role == 'team_member';
  bool get isViewer => role == 'viewer';
  
  bool get canCreate => isAdmin || isCollector;
  bool get canSeeAllTags => isAdmin || isCollector || isTeamMember || isCoreTeamMember;
  bool get canSeeTeamData => isAdmin || isTeamMember || isCoreTeamMember;
  bool get canAccessAR => isAdmin || isCollector;
  bool get canAccessReports => isAdmin || isCollector || isTeamMember;
}
