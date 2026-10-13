import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;
double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

class Group {
  Group({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    required this.memberIds,
    required this.memberNames,
  });

  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final List<String> memberIds;
  final Map<String, String> memberNames;

  String nameOf(String uid) => memberNames[uid] ?? 'Thành viên';

  factory Group.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Group(
      id: doc.id,
      name: d['name'] as String? ?? '',
      ownerId: d['ownerId'] as String? ?? '',
      inviteCode: d['inviteCode'] as String? ?? '',
      memberIds: List<String>.from(d['memberIds'] as List? ?? const []),
      memberNames: Map<String, String>.from(d['memberNames'] as Map? ?? const {}),
    );
  }
}

class MemberLocation {
  MemberLocation({
    required this.uid,
    required this.name,
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.speed,
    required this.battery,
    required this.sharing,
    required this.updatedAt,
  });

  final String uid;
  final String name;
  final double lat;
  final double lng;
  final double accuracy;
  final double? speed;
  final int? battery;
  final bool sharing;
  final DateTime? updatedAt;

  LatLng get point => LatLng(lat, lng);

  factory MemberLocation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MemberLocation(
      uid: doc.id,
      name: d['name'] as String? ?? 'Thành viên',
      lat: _num(d['lat']),
      lng: _num(d['lng']),
      accuracy: _num(d['accuracy']),
      speed: (d['speed'] as num?)?.toDouble(),
      battery: (d['battery'] as num?)?.toInt(),
      sharing: d['sharing'] as bool? ?? false,
      updatedAt: _date(d['updatedAt']) ?? _date(d['clientAt']),
    );
  }
}

class Place {
  Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radius,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radius;

  LatLng get point => LatLng(lat, lng);

  factory Place.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Place(
      id: doc.id,
      name: d['name'] as String? ?? '',
      lat: _num(d['lat']),
      lng: _num(d['lng']),
      radius: _num(d['radius']),
    );
  }
}

/// Sự kiện trong nhóm: arrive / leave / sos / join.
class GroupEvent {
  GroupEvent({
    required this.id,
    required this.type,
    required this.uid,
    required this.name,
    required this.placeName,
    required this.lat,
    required this.lng,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String uid;
  final String name;
  final String? placeName;
  final double? lat;
  final double? lng;
  final DateTime? createdAt;

  factory GroupEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GroupEvent(
      id: doc.id,
      type: d['type'] as String? ?? '',
      uid: d['uid'] as String? ?? '',
      name: d['name'] as String? ?? 'Thành viên',
      placeName: d['placeName'] as String?,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      createdAt: _date(d['createdAt']),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String uid;
  final String name;
  final String text;
  final DateTime? createdAt;

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ChatMessage(
      id: doc.id,
      uid: d['uid'] as String? ?? '',
      name: d['name'] as String? ?? 'Thành viên',
      text: d['text'] as String? ?? '',
      createdAt: _date(d['createdAt']),
    );
  }
}
