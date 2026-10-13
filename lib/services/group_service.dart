import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import 'profile_service.dart';
import 'trip_analyzer.dart';

class GroupService {
  GroupService._();
  static final instance = GroupService._();

  final _db = FirebaseFirestore.instance;
  // Phải trùng region trong functions/index.js.
  final _fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _name => FirebaseAuth.instance.currentUser?.displayName ?? 'Thành viên';

  CollectionReference<Map<String, dynamic>> _sub(String gid, String name) =>
      _db.collection('groups').doc(gid).collection(name);

  // ---- Nhóm ----

  Stream<List<Group>> myGroups(String uid) => _db
      .collection('groups')
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map(Group.fromDoc).toList());

  Stream<Group?> group(String gid) => _db
      .doc('groups/$gid')
      .snapshots()
      .map((d) => d.exists ? Group.fromDoc(d) : null);

  Future<String> createGroup(String name) async {
    final res = await _fn.httpsCallable('createGroup').call({'name': name});
    return (res.data as Map)['groupId'] as String;
  }

  Future<String> joinGroup(String code) async {
    final res = await _fn.httpsCallable('joinGroup').call({'code': code});
    return (res.data as Map)['groupId'] as String;
  }

  Future<void> leaveGroup(String gid) =>
      _fn.httpsCallable('leaveGroup').call({'groupId': gid});

  /// Chủ nhóm xoá một thành viên; [block] = chặn không cho tham gia lại.
  Future<void> removeMember(String gid, String uid, {bool block = false}) =>
      _fn.httpsCallable('removeMember').call({'groupId': gid, 'uid': uid, 'block': block});

  Future<void> unblockMember(String gid, String uid) =>
      _fn.httpsCallable('unblockMember').call({'groupId': gid, 'uid': uid});

  // ---- Vị trí ----

  Stream<List<MemberLocation>> locations(String gid) => _sub(gid, 'locations')
      .snapshots()
      .map((s) => s.docs.map(MemberLocation.fromDoc).toList());

  /// Lịch sử vị trí của một thành viên trong khoảng thời gian.
  Future<List<TrackPoint>> history(String gid, String uid, DateTime from, DateTime to) async {
    final snap = await _sub(gid, 'locations')
        .doc(uid)
        .collection('points')
        .where('t', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('t', isLessThan: Timestamp.fromDate(to))
        .orderBy('t')
        .get();
    return [
      for (final d in snap.docs)
        TrackPoint(
          lat: (d['lat'] as num).toDouble(),
          lng: (d['lng'] as num).toDouble(),
          speed: (d.data()['speed'] as num?)?.toDouble(),
          time: (d['t'] as Timestamp).toDate(),
        ),
    ];
  }

  // ---- Ping nhanh (❤️ Yêu nhé!, 👻 Ú òa!...) ----

  Future<void> sendPing(String gid, String toUid, String type) => _sub(gid, 'pings').add({
        'from': _uid,
        'fromName': _name,
        'to': toUid,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// Sự kiện đến/rời địa điểm của một thành viên.
  Stream<List<GroupEvent>> memberEvents(String gid, String uid) => _sub(gid, 'events')
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(GroupEvent.fromDoc).toList());

  // ---- Khoảnh khắc ----

  /// Khoảnh khắc trong 24 giờ gần nhất, mới nhất trước.
  Stream<List<Moment>> moments(String gid) => _sub(gid, 'moments')
      .where('createdAt', isGreaterThan: Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 24))))
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Moment.fromDoc).toList());

  Future<void> postMoment(String gid, {required String text, XFile? photo, double? lat, double? lng}) async {
    final ref = _sub(gid, 'moments').doc();
    String? photoUrl;
    if (photo != null) {
      photoUrl = await ProfileService.instance.uploadImage('moments/$gid/$_uid/${ref.id}.jpg', photo);
    }
    final now = DateTime.now();
    await ref.set({
      'uid': _uid,
      'name': _name,
      'text': text,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'likes': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'clientAt': Timestamp.fromDate(now),
      // Firestore TTL tự xoá sau 24 giờ.
      'expireAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
    });
  }

  Future<void> toggleLike(String gid, Moment m) => _sub(gid, 'moments').doc(m.id).update({
        'likes': m.likes.contains(_uid) ? FieldValue.arrayRemove([_uid]) : FieldValue.arrayUnion([_uid]),
      });

  Future<void> deleteMoment(String gid, String id) => _sub(gid, 'moments').doc(id).delete();

  // ---- Meetup ----

  Stream<List<Meetup>> activeMeetups(String gid) => _sub(gid, 'meetups')
      .where('active', isEqualTo: true)
      .orderBy('time')
      .snapshots()
      .map((s) => s.docs.map(Meetup.fromDoc).toList());

  Stream<Meetup?> meetup(String gid, String id) =>
      _sub(gid, 'meetups').doc(id).snapshots().map((d) => d.exists ? Meetup.fromDoc(d) : null);

  Future<String> createMeetup(String gid,
      {required String title, required double lat, required double lng, required DateTime time}) async {
    final ref = await _sub(gid, 'meetups').add({
      'title': title,
      'lat': lat,
      'lng': lng,
      'time': Timestamp.fromDate(time),
      'createdBy': _uid,
      'createdByName': _name,
      'participants': {_uid: MeetupStatus.going.name},
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> setMeetupStatus(String gid, String id, MeetupStatus status) =>
      _sub(gid, 'meetups').doc(id).update({'participants.$_uid': status.name});

  Future<void> endMeetup(String gid, String id) => _sub(gid, 'meetups').doc(id).update({'active': false});

  // ---- Địa điểm (vùng geofence) ----

  Stream<List<Place>> places(String gid) =>
      _sub(gid, 'places').orderBy('name').snapshots().map((s) => s.docs.map(Place.fromDoc).toList());

  Future<void> addPlace(String gid,
          {required String name, required double lat, required double lng, required double radius}) =>
      _sub(gid, 'places').add({
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'createdBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> deletePlace(String gid, String pid) => _sub(gid, 'places').doc(pid).delete();

  // ---- Hoạt động ----

  Stream<List<GroupEvent>> events(String gid) => _sub(gid, 'events')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(GroupEvent.fromDoc).toList());

  Future<void> addEvent(String gid,
          {required String type, String? placeName, double? lat, double? lng}) =>
      _sub(gid, 'events').add({
        'type': type,
        'uid': _uid,
        'name': _name,
        if (placeName != null) 'placeName': placeName,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> sendSos(String gid, {double? lat, double? lng}) =>
      addEvent(gid, type: 'sos', lat: lat, lng: lng);

  // ---- Trò chuyện ----

  Stream<List<ChatMessage>> messages(String gid) => _sub(gid, 'messages')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  Future<void> sendMessage(String gid, String text) => _sub(gid, 'messages').add({
        'uid': _uid,
        'name': _name,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
}
