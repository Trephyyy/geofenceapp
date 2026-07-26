class Visit {
  final String id;
  final String? serverId;
  final String placeId;
  final DateTime enterTs;
  final DateTime? exitTs;
  final int? durationS;
  final String source; // 'geofence' | 'manual_edit'
  final bool dirty;

  Visit({
    required this.id,
    this.serverId,
    required this.placeId,
    required this.enterTs,
    this.exitTs,
    this.durationS,
    required this.source,
    required this.dirty,
  });

  Visit copyWith({
    DateTime? exitTs,
    int? durationS,
    bool? dirty,
  }) {
    return Visit(
      id: id,
      serverId: serverId,
      placeId: placeId,
      enterTs: enterTs,
      exitTs: exitTs ?? this.exitTs,
      durationS: durationS ?? this.durationS,
      source: source,
      dirty: dirty ?? this.dirty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'place_id': placeId,
      'enter_ts': enterTs.millisecondsSinceEpoch,
      'exit_ts': exitTs?.millisecondsSinceEpoch,
      'duration_s': durationS,
      'source': source,
      'dirty': dirty ? 1 : 0,
    };
  }

  factory Visit.fromMap(Map<String, dynamic> map) {
    return Visit(
      id: map['id'] as String,
      serverId: map['server_id'] as String?,
      placeId: map['place_id'] as String,
      enterTs: DateTime.fromMillisecondsSinceEpoch(map['enter_ts'] as int),
      exitTs: map['exit_ts'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['exit_ts'] as int)
          : null,
      durationS: map['duration_s'] as int?,
      source: map['source'] as String,
      dirty: (map['dirty'] as int) == 1,
    );
  }
}
