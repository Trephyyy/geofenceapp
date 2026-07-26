class LearningPoint {
  final double lat;
  final double lng;
  final DateTime timestamp;

  LearningPoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory LearningPoint.fromMap(Map<String, dynamic> map) {
    return LearningPoint(
      lat: map['lat'] as double,
      lng: map['lng'] as double,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
}
