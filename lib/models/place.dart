enum PlaceIcon {
  work,
  gym,
  home,
  custom;

  static PlaceIcon fromString(String value) {
    return PlaceIcon.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => PlaceIcon.custom,
    );
  }
}

enum PlaceStatus {
  learning,
  confirmed,
  archived;

  static PlaceStatus fromString(String value) {
    return PlaceStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => PlaceStatus.learning,
    );
  }
}

enum GeofenceTriggerType {
  normal,
  harbor;

  String get displayName {
    switch (this) {
      case GeofenceTriggerType.normal:
        return 'Normal';
      case GeofenceTriggerType.harbor:
        return 'Harbor (5min latch)';
    }
  }

  String get description {
    switch (this) {
      case GeofenceTriggerType.normal:
        return 'Standard geofence: triggers on every enter/exit.';
      case GeofenceTriggerType.harbor:
        return 'For places like a harbor: enter for 5min starts visit, only ends when you enter and leave again.';
    }
  }

  static GeofenceTriggerType fromString(String value) {
    return GeofenceTriggerType.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => GeofenceTriggerType.normal,
    );
  }
}

class Place {
  final String id;
  final String? serverId;
  final String label;
  final PlaceIcon icon;
  final double lat;
  final double lng;
  final double radiusM;
  final PlaceStatus status;
  final GeofenceTriggerType triggerType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool dirty;

  Place({
    required this.id,
    this.serverId,
    required this.label,
    required this.icon,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.status,
    this.triggerType = GeofenceTriggerType.normal,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });

  Place copyWith({
    String? label,
    PlaceIcon? icon,
    double? lat,
    double? lng,
    double? radiusM,
    PlaceStatus? status,
    GeofenceTriggerType? triggerType,
    DateTime? updatedAt,
    bool? dirty,
  }) {
    return Place(
      id: id,
      serverId: serverId,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusM: radiusM ?? this.radiusM,
      status: status ?? this.status,
      triggerType: triggerType ?? this.triggerType,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'label': label,
      'icon': icon.name,
      'lat': lat,
      'lng': lng,
      'radius_m': radiusM,
      'status': status.name,
      'trigger_type': triggerType.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'dirty': dirty ? 1 : 0,
    };
  }

  factory Place.fromMap(Map<String, dynamic> map) {
    return Place(
      id: map['id'] as String,
      serverId: map['server_id'] as String?,
      label: map['label'] as String,
      icon: PlaceIcon.fromString(map['icon'] as String),
      lat: map['lat'] as double,
      lng: map['lng'] as double,
      radiusM: map['radius_m'] as double,
      status: PlaceStatus.fromString(map['status'] as String),
      triggerType: map['trigger_type'] != null
          ? GeofenceTriggerType.fromString(map['trigger_type'] as String)
          : GeofenceTriggerType.normal,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      dirty: (map['dirty'] as int) == 1,
    );
  }
}
