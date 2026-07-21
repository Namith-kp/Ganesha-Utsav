class Collector {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? assignedArea;
  final String role; // 'admin', 'collector', 'team_member', or 'viewer'
  final bool isCoreTeamMember;
  final bool canAccessAdminControl;
  final String? photoUrl;
  
  // Team Fund fields
  final String? fundStatus; // 'paid' or 'pending'
  final double? fundAmount;
  final String? fundPaymentMethod;
  final DateTime? fundCollectedAt;
  final String? fundCollectedBy;

  Collector({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.assignedArea,
    required this.role,
    this.isCoreTeamMember = false,
    this.canAccessAdminControl = false,
    this.photoUrl,
    this.fundStatus,
    this.fundAmount,
    this.fundPaymentMethod,
    this.fundCollectedAt,
    this.fundCollectedBy,
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
      canAccessAdminControl: map['canAccessAdminControl'] as bool? ?? false,
      photoUrl: map['photoUrl'] as String?,
      fundStatus: map['fundStatus'] as String? ?? 'pending',
      fundAmount: (map['fundAmount'] as num?)?.toDouble(),
      fundPaymentMethod: map['fundPaymentMethod'] as String?,
      fundCollectedAt: map['fundCollectedAt'] != null 
          ? (map['fundCollectedAt'] as dynamic).toDate() 
          : null,
      fundCollectedBy: map['fundCollectedBy'] as String?,
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
      'canAccessAdminControl': canAccessAdminControl,
      'photoUrl': photoUrl,
      'fundStatus': fundStatus,
      'fundAmount': fundAmount,
      'fundPaymentMethod': fundPaymentMethod,
      'fundCollectedAt': fundCollectedAt,
      'fundCollectedBy': fundCollectedBy,
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isCollector => role == 'collector';
  bool get isTeamMember => role == 'team_member';
  bool get isViewer => role == 'viewer';
  bool get hasAdminControlAccess => isAdmin && canAccessAdminControl;
  
  bool get canCreate => isAdmin || isCollector;
  bool get canSeeAllTags => isAdmin || isCollector || isTeamMember || isCoreTeamMember;
  bool get canSeeTeamData => isAdmin || isTeamMember || isCoreTeamMember;
  bool get canAccessAR => isAdmin || isCollector;
  bool get canAccessReports => isAdmin || isCollector || isTeamMember;
}
