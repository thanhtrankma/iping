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
    this.blockedIds = const [],
    this.blockedNames = const {},
  });

  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final List<String> memberIds;
  final Map<String, String> memberNames;
  final Map<String, String?> memberPhotos;
  /// Người bị chủ nhóm chặn (không thể tham gia lại bằng mã mời).
  final List<String> blockedIds;
  final Map<String, String> blockedNames;

  bool isOwner(String? uid) => uid != null && uid == ownerId;

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
      blockedIds: List<String>.from(d['blockedIds'] as List? ?? const []),
      blockedNames: Map<String, String>.from(d['blockedNames'] as Map? ?? const {}),
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

/// Sự kiện trong nhóm: arrive / leave / sos / join / checkin / safe_* ...
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
    this.dueAt,
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
  /// Giờ dự kiến tới (sự kiện "Về an toàn").
  final DateTime? dueAt;

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
      dueAt: _date(d['dueAt']),
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

/// Trạng thái chuyến "Về an toàn".
/// - active: đang đi, chưa quá giờ.
/// - overdue: quá giờ dự kiến mà chưa tới (server đã cảnh báo nhóm).
/// - arrived: đã tới nơi (tự phát hiện hoặc tự xác nhận).
/// - ended: người đi tự kết thúc (huỷ, hoặc báo "Tôi ổn" khi đang quá giờ).
enum SafeTripStatus { active, overdue, arrived, ended }

/// Một chuyến "Về an toàn" (`groups/{gid}/safeTrips/{uid}`, mỗi người tối đa một chuyến mỗi nhóm).
class SafeTrip {
  SafeTrip({
    required this.uid,
    required this.name,
    required this.destName,
    required this.destLat,
    required this.destLng,
    required this.radius,
    required this.startedAt,
    required this.dueAt,
    required this.status,
    this.startLat,
    this.startLng,
    this.endedAt,
  });

  final String uid;
  final String name;
  final String destName;
  final double destLat;
  final double destLng;
  /// Bán kính (m) quanh điểm đến được coi là đã tới.
  final double radius;
  final DateTime startedAt;
  final DateTime dueAt;
  final SafeTripStatus status;
  final double? startLat;
  final double? startLng;
  final DateTime? endedAt;

  LatLng get dest => LatLng(destLat, destLng);
  LatLng? get start => startLat == null || startLng == null ? null : LatLng(startLat!, startLng!);

  /// Đang diễn ra (cần hiển thị trên bản đồ / banner).
  bool get isOpen => status == SafeTripStatus.active || status == SafeTripStatus.overdue;

  /// Quá giờ: server đã đánh dấu, hoặc máy thấy đã qua giờ mà server chưa kịp chạy.
  bool isLate(DateTime now) => status == SafeTripStatus.overdue || (status == SafeTripStatus.active && now.isAfter(dueAt));

  /// Thời gian còn lại tới giờ dự kiến (âm nếu đã quá giờ).
  Duration remaining(DateTime now) => dueAt.difference(now);

  /// Tiến độ quãng đường 0–1 dựa trên khoảng cách còn lại so với lúc xuất phát.
  double progress(LatLng current) {
    final s = start;
    if (s == null) return 0;
    const d = Distance();
    final total = d(s, dest);
    if (total <= radius) return 1;
    final left = d(current, dest);
    return (1 - (left - radius) / (total - radius)).clamp(0.0, 1.0);
  }

  factory SafeTrip.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SafeTrip(
      uid: doc.id,
      name: d['name'] as String? ?? 'Thành viên',
      destName: d['destName'] as String? ?? '',
      destLat: _num(d['destLat']),
      destLng: _num(d['destLng']),
      radius: (d['radius'] as num?)?.toDouble() ?? 150,
      startedAt: _date(d['startedAt']) ?? DateTime.now(),
      dueAt: _date(d['dueAt']) ?? DateTime.now(),
      status: SafeTripStatus.values.firstWhere((s) => s.name == d['status'], orElse: () => SafeTripStatus.ended),
      startLat: (d['startLat'] as num?)?.toDouble(),
      startLng: (d['startLng'] as num?)?.toDouble(),
      endedAt: _date(d['endedAt']),
    );
  }
}
