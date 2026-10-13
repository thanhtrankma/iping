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
    this.memberPhotos = const {},
  });

  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final List<String> memberIds;
  final Map<String, String> memberNames;
  final Map<String, String?> memberPhotos;

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
      memberPhotos: Map<String, String?>.from(d['memberPhotos'] as Map? ?? const {}),
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
    this.photoUrl,
  });

  final String uid;
  final String name;
  final String? photoUrl;
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
      photoUrl: d['photoUrl'] as String?,
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
    this.battery,
  });

  final String id;
  final String type;
  final String uid;
  final String name;
  final String? placeName;
  final double? lat;
  final double? lng;
  final DateTime? createdAt;
  final int? battery;

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
      battery: (d['battery'] as num?)?.toInt(),
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

/// Khoảnh khắc: ảnh và/hoặc dòng trạng thái kèm vị trí, hết hạn sau 24 giờ.
class Moment {
  Moment({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.photoUrl,
    required this.lat,
    required this.lng,
    required this.likes,
    required this.createdAt,
  });

  final String id;
  final String uid;
  final String name;
  final String text;
  final String? photoUrl;
  final double? lat;
  final double? lng;
  final List<String> likes;
  final DateTime? createdAt;

  bool get hasLocation => lat != null && lng != null;
  LatLng? get point => hasLocation ? LatLng(lat!, lng!) : null;

  factory Moment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Moment(
      id: doc.id,
      uid: d['uid'] as String? ?? '',
      name: d['name'] as String? ?? 'Thành viên',
      text: d['text'] as String? ?? '',
      photoUrl: d['photoUrl'] as String?,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      likes: List<String>.from(d['likes'] as List? ?? const []),
      createdAt: _date(d['createdAt']) ?? _date(d['clientAt']),
    );
  }
}

/// Trạng thái tham gia meetup.
enum MeetupStatus { invited, going, declined, arrived }

class Meetup {
  Meetup({
    required this.id,
    required this.title,
    required this.lat,
    required this.lng,
    required this.time,
    required this.createdBy,
    required this.createdByName,
    required this.participants,
    required this.active,
  });

  final String id;
  final String title;
  final double lat;
  final double lng;
  final DateTime time;
  final String createdBy;
  final String createdByName;
  final Map<String, MeetupStatus> participants;
  final bool active;

  LatLng get point => LatLng(lat, lng);
  MeetupStatus statusOf(String uid) => participants[uid] ?? MeetupStatus.invited;

  factory Meetup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final raw = Map<String, dynamic>.from(d['participants'] as Map? ?? const {});
    return Meetup(
      id: doc.id,
      title: d['title'] as String? ?? '',
      lat: _num(d['lat']),
      lng: _num(d['lng']),
      time: _date(d['time']) ?? DateTime.now(),
      createdBy: d['createdBy'] as String? ?? '',
      createdByName: d['createdByName'] as String? ?? '',
      participants: {
        for (final e in raw.entries)
          e.key: MeetupStatus.values.firstWhere((s) => s.name == e.value, orElse: () => MeetupStatus.invited),
      },
      active: d['active'] as bool? ?? true,
    );
  }
}
