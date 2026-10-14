const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { setGlobalOptions } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { wantsAlert, CRITICAL } = require('./alert_prefs');

initializeApp();
setGlobalOptions({ region: 'asia-southeast1' });
const db = getFirestore();

const MAX_MEMBERS = 20;
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function randomCode(len = 6) {
  let s = '';
  for (let i = 0; i < len; i++) s += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
  return s;
}

function requireAuth(req) {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Bạn cần đăng nhập.');
  return uid;
}

async function displayName(uid) {
  if (!uid) return 'Thành viên';
  const snap = await db.doc(`users/${uid}`).get();
  return snap.get('name') || 'Thành viên';
}

async function photoUrl(uid) {
  const snap = await db.doc(`users/${uid}`).get();
  return snap.get('photoUrl') || null;
}

// ---------- Nhóm ----------

exports.createGroup = onCall(async (req) => {
  const uid = requireAuth(req);
  const name = String(req.data?.name ?? '').trim().slice(0, 50);
  if (!name) throw new HttpsError('invalid-argument', 'Tên nhóm không được để trống.');

  const memberName = await displayName(uid);
  const groupRef = db.collection('groups').doc();

  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomCode();
    const codeRef = db.doc(`inviteCodes/${code}`);
    try {
      await db.runTransaction(async (tx) => {
        if ((await tx.get(codeRef)).exists) throw new Error('code-taken');
        tx.set(groupRef, {
          name,
          ownerId: uid,
          memberIds: [uid],
          memberNames: { [uid]: memberName },
          memberPhotos: { [uid]: await photoUrl(uid) },
          inviteCode: code,
          createdAt: FieldValue.serverTimestamp(),
        });
        tx.set(codeRef, { groupId: groupRef.id });
      });
      return { groupId: groupRef.id };
    } catch (e) {
      if (e.message !== 'code-taken') throw e;
    }
  }
  throw new HttpsError('resource-exhausted', 'Không tạo được mã mời, hãy thử lại.');
});

exports.joinGroup = onCall(async (req) => {
  const uid = requireAuth(req);
  const code = String(req.data?.code ?? '').trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(code)) throw new HttpsError('invalid-argument', 'Mã mời gồm 6 ký tự.');

  const codeSnap = await db.doc(`inviteCodes/${code}`).get();
  if (!codeSnap.exists) throw new HttpsError('not-found', 'Mã mời không hợp lệ.');

  const groupRef = db.doc(`groups/${codeSnap.get('groupId')}`);
  const memberName = await displayName(uid);
  const memberPhoto = await photoUrl(uid);

  const joined = await db.runTransaction(async (tx) => {
    const g = await tx.get(groupRef);
    if (!g.exists) throw new HttpsError('not-found', 'Nhóm không còn tồn tại.');
    const members = g.get('memberIds') || [];
    if (members.includes(uid)) return false;
    if ((g.get('blockedIds') || []).includes(uid)) {
      throw new HttpsError('permission-denied', 'Bạn không thể tham gia nhóm này.');
    }
    if (members.length >= MAX_MEMBERS) {
      throw new HttpsError('failed-precondition', `Nhóm đã đủ ${MAX_MEMBERS} thành viên.`);
    }
    tx.update(groupRef, {
      memberIds: FieldValue.arrayUnion(uid),
      [`memberNames.${uid}`]: memberName,
      [`memberPhotos.${uid}`]: memberPhoto,
    });
    return true;
  });

  if (joined) {
    await groupRef.collection('events').add({
      type: 'join', uid, name: memberName, createdAt: FieldValue.serverTimestamp(),
    });
  }
  return { groupId: groupRef.id };
});

// Gỡ một thành viên khỏi nhóm: chuyển quyền chủ nhóm, xoá nhóm khi không còn ai.
async function leaveGroupAs(uid, groupId) {
  const groupRef = db.doc(`groups/${groupId}`);

  const result = await db.runTransaction(async (tx) => {
    const g = await tx.get(groupRef);
    if (!g.exists) return { deleted: false, missing: true };
    const remaining = (g.get('memberIds') || []).filter((m) => m !== uid);
    if (remaining.length === 0) {
      tx.delete(db.doc(`inviteCodes/${g.get('inviteCode')}`));
      return { deleted: true };
    }
    const update = {
      memberIds: FieldValue.arrayRemove(uid),
      [`memberNames.${uid}`]: FieldValue.delete(),
      [`memberPhotos.${uid}`]: FieldValue.delete(),
    };
    if (g.get('ownerId') === uid) update.ownerId = remaining[0];
    tx.update(groupRef, update);
    return { deleted: false };
  });

  if (result.missing) return;
  if (result.deleted) {
    await db.recursiveDelete(groupRef);
  } else {
    await removeMemberData(groupRef, uid);
    await groupRef.collection('events').add({
      type: 'leave_group', uid, name: await displayName(uid), createdAt: FieldValue.serverTimestamp(),
    });
  }
}

exports.leaveGroup = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? '');
  if (!groupId) throw new HttpsError('invalid-argument', 'Thiếu groupId.');
  await leaveGroupAs(uid, groupId);
  return { ok: true };
});

// Xoá vị trí (kèm lịch sử points), điểm khám phá và chuyến "Về an toàn" của một thành viên trong nhóm.
async function removeMemberData(groupRef, uid) {
  await db.recursiveDelete(groupRef.collection('locations').doc(uid));
  await groupRef.collection('explore').doc(uid).delete();
  await groupRef.collection('safeTrips').doc(uid).delete();
}

// Đọc nhóm và chắc chắn người gọi là chủ nhóm.
async function requireOwner(tx, groupRef, uid) {
  const g = await tx.get(groupRef);
  if (!g.exists) throw new HttpsError('not-found', 'Nhóm không còn tồn tại.');
  if (g.get('ownerId') !== uid) throw new HttpsError('permission-denied', 'Chỉ chủ nhóm mới làm được việc này.');
  return g;
}

exports.removeMember = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? '');
  const target = String(req.data?.uid ?? '');
  const block = req.data?.block === true;
  if (!groupId || !target) throw new HttpsError('invalid-argument', 'Thiếu groupId hoặc uid.');
  if (target === uid) throw new HttpsError('invalid-argument', 'Bạn không thể tự xoá mình. Hãy dùng "Rời nhóm".');
  const groupRef = db.doc(`groups/${groupId}`);

  const result = await db.runTransaction(async (tx) => {
    const g = await requireOwner(tx, groupRef, uid);
    const isMember = (g.get('memberIds') || []).includes(target);
    if (!isMember && !block) throw new HttpsError('not-found', 'Người này không còn trong nhóm.');
    const name = g.get(`memberNames.${target}`) || g.get(`blockedNames.${target}`) || 'Thành viên';
    const update = {};
    if (isMember) {
      update.memberIds = FieldValue.arrayRemove(target);
      update[`memberNames.${target}`] = FieldValue.delete();
      update[`memberPhotos.${target}`] = FieldValue.delete();
    }
    if (block) {
      update.blockedIds = FieldValue.arrayUnion(target);
      update[`blockedNames.${target}`] = name;
    }
    tx.update(groupRef, update);
    return { isMember, name };
  });

  if (result.isMember) {
    await removeMemberData(groupRef, target);
    await groupRef.collection('events').add({
      type: 'removed', uid: target, name: result.name, createdAt: FieldValue.serverTimestamp(),
    });
  }
  return { ok: true };
});

exports.unblockMember = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? '');
  const target = String(req.data?.uid ?? '');
  if (!groupId || !target) throw new HttpsError('invalid-argument', 'Thiếu groupId hoặc uid.');
  const groupRef = db.doc(`groups/${groupId}`);
  await db.runTransaction(async (tx) => {
    await requireOwner(tx, groupRef, uid);
    tx.update(groupRef, {
      blockedIds: FieldValue.arrayRemove(target),
      [`blockedNames.${target}`]: FieldValue.delete(),
    });
  });
  return { ok: true };
});

// ---------- Thông báo đẩy ----------

// `exceptUid` là người gửi: không gửi cho họ và dùng để lọc theo `mutedUids` của người nhận.
async function notifyGroup(groupId, exceptUid, notification, data) {
  const g = await db.doc(`groups/${groupId}`).get();
  if (!g.exists) return;
  const targets = (g.get('memberIds') || []).filter((m) => m !== exceptUid);
  await notifyUsers(groupId, targets, notification, data, exceptUid);
}

async function notifyUsers(groupId, targets, notification, data, senderUid) {
  if (targets.length === 0) return;

  const userSnaps = await db.getAll(...targets.map((m) => db.doc(`users/${m}`)));
  const tokenOwners = new Map();
  for (const u of userSnaps) {
    // Tôn trọng cài đặt "Quản lý cảnh báo" của người nhận.
    if (!wantsAlert(u.data(), data.type, senderUid)) continue;
    for (const t of u.get('fcmTokens') || []) tokenOwners.set(t, u.id);
  }
  const tokens = [...tokenOwners.keys()];
  if (tokens.length === 0) return;

  const isSos = CRITICAL.has(data.type);
  // Yêu cầu vị trí: đánh thức app nền để tự gửi vị trí (iOS cần content-available).
  const wake = data.type === 'locate';
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification,
    data: { groupId, ...data },
    android: { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          sound: 'default',
          'interruption-level': isSos ? 'time-sensitive' : 'active',
          ...(wake ? { 'content-available': 1 } : {}),
        },
      },
    },
  });

  // Dọn token đã hết hạn.
  const stale = [];
  res.responses.forEach((r, i) => {
    const code = r.error?.code;
    if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
      stale.push(tokens[i]);
    }
  });
  await Promise.all(stale.map((t) =>
    db.doc(`users/${tokenOwners.get(t)}`).update({ fcmTokens: FieldValue.arrayRemove(t) })));
}

exports.onGroupEvent = onDocumentCreated('groups/{groupId}/events/{eventId}', async (event) => {
  const e = event.data?.data();
  if (!e) return;
  // Tên lấy từ hồ sơ (chỉ chủ tài khoản ghi được), không tin `name` do client gửi.
  e.name = await displayName(e.uid);
  const groupId = event.params.groupId;
  const groupName = (await db.doc(`groups/${groupId}`).get()).get('name') || 'Nhóm';

  let notification;
  switch (e.type) {
    case 'arrive':
      notification = { title: groupName, body: `${e.name} đã đến ${e.placeName}` };
      break;
    case 'leave':
      notification = { title: groupName, body: `${e.name} đã rời ${e.placeName}` };
      break;
    case 'sos':
      notification = { title: `🚨 SOS từ ${e.name}`, body: `${e.name} cần trợ giúp! Mở ứng dụng để xem vị trí.` };
      break;
    case 'join':
      notification = { title: groupName, body: `${e.name} đã tham gia nhóm` };
      break;
    case 'checkin':
      notification = { title: groupName, body: `📍 ${e.name} đã check-in tại ${e.placeName || ''}` };
      break;
    case 'meetup_arrive':
      notification = { title: groupName, body: `📍 ${e.name} đã tới điểm hẹn ${e.placeName || ''}` };
      break;
    case 'low_battery':
      notification = { title: groupName, body: `🔋 ${e.name} sắp hết pin (${e.battery}%)` };
      break;
    case 'speeding':
      notification = { title: groupName, body: `🚗 ${e.name} đang chạy ${e.speed} km/h, quá tốc độ 80 km/h` };
      break;
    case 'offline':
      notification = {
        title: groupName,
        body: `📵 ${e.name} không cập nhật vị trí từ ${hhmm(e.lastAt)} (mất kết nối hoặc hết pin?)`,
      };
      break;
    case 'location_off':
      notification = { title: groupName, body: `📍 ${e.name} đã tắt định vị hoặc thu hồi quyền vị trí` };
      break;
    case 'safe_start':
      notification = {
        title: groupName,
        body: `🛡️ ${e.name} đang về ${e.placeName || ''}, dự kiến tới lúc ${hhmm(e.dueAt)}`,
      };
      break;
    case 'safe_arrive':
      notification = { title: groupName, body: `✅ ${e.name} đã về ${e.placeName || ''} an toàn` };
      break;
    case 'safe_ok':
      notification = { title: groupName, body: `✅ ${e.name} báo đã an toàn (chuyến về ${e.placeName || ''})` };
      break;
    case 'safe_extend':
      notification = { title: groupName, body: `⏱️ ${e.name} gia hạn chuyến về ${e.placeName || ''} tới ${hhmm(e.dueAt)}` };
      break;
    case 'safe_overdue': {
      const late = e.repeat ? 'vẫn chưa tới' : 'chưa tới';
      const battery = e.battery != null ? ` Pin ${e.battery}%.` : '';
      notification = {
        title: `⚠️ ${e.name} ${late} ${e.placeName || ''}`,
        body: `Đã quá giờ dự kiến ${hhmm(e.dueAt)}.${battery} Mở ứng dụng để xem vị trí và gọi cho ${e.name}.`,
      };
      break;
    }
    default:
      return;
  }
  await notifyGroup(groupId, e.uid, notification, { type: e.type, uid: String(e.uid || '') });
});

exports.onGroupMessage = onDocumentCreated('groups/{groupId}/messages/{messageId}', async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const groupId = event.params.groupId;
  const groupName = (await db.doc(`groups/${groupId}`).get()).get('name') || 'Nhóm';
  await notifyGroup(groupId, m.uid, {
    title: `${await displayName(m.uid)} · ${groupName}`,
    body: String(m.text).slice(0, 200),
  }, { type: 'message', uid: String(m.uid || '') });
});

// Giới hạn tần suất ping theo cặp người gửi → người nhận (chống spam push, hao pin máy bị yêu cầu vị trí).
const PING_COOLDOWN_MS = { locate: 60 * 1000, default: 5 * 1000 };

async function allowPing(groupId, p) {
  const key = p.type === 'locate' ? 'locate' : 'ping';
  const ref = db.doc(`groups/${groupId}/pingLimits/${p.from}_${p.to}_${key}`);
  const cooldown = PING_COOLDOWN_MS[key] || PING_COOLDOWN_MS.default;
  return db.runTransaction(async (tx) => {
    const last = (await tx.get(ref)).get('at');
    const now = Date.now();
    if (last && now - last.toMillis() < cooldown) return false;
    tx.set(ref, { at: Timestamp.fromMillis(now) });
    return true;
  });
}

const PING_TEXT = {
  love: '❤️ Yêu nhé!',
  boo: '👻 Ú òa!',
  poke: '💩 Chọc!',
  arrived: '📍 Tới rồi!',
  call: '📞 Gọi lại cho mình nhé',
  home: '🏠 Về nhà chưa?',
};

exports.onPing = onDocumentCreated('groups/{groupId}/pings/{pingId}', async (event) => {
  const p = event.data?.data();
  if (!p || !(PING_TEXT[p.type] || p.type === 'locate')) return;
  const groupId = event.params.groupId;
  const g = await db.doc(`groups/${groupId}`).get();
  if (!(g.get('memberIds') || []).includes(p.to)) return;
  if (!(await allowPing(groupId, p))) return;
  const name = await displayName(p.from);
  if (p.type === 'locate') {
    // Data message ưu tiên cao: máy nhận tự lấy và ghi vị trí (nếu đang bật chia sẻ).
    await notifyUsers(groupId, [p.to], { title: 'IPing', body: `📍 ${name} muốn biết bạn đang ở đâu` },
      { type: 'locate', from: String(p.from || '') }, p.from);
    return;
  }
  await notifyUsers(groupId, [p.to], { title: name, body: PING_TEXT[p.type] },
    { type: 'ping', from: String(p.from || '') },
    p.from);
});

// ---------- Về an toàn ----------

/// Giờ:phút theo giờ Việt Nam cho Timestamp Firestore.
function hhmm(ts) {
  if (!ts || typeof ts.toDate !== 'function') return '?';
  return ts.toDate().toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Ho_Chi_Minh' });
}

const SAFE_REALERT_MS = 15 * 60 * 1000;
const SAFE_MAX_ALERTS = 2;
// Chuyến quá giờ lâu mà không ai đóng: tự kết thúc để không quét mãi.
const SAFE_EXPIRE_MS = 12 * 60 * 60 * 1000;

/// Mỗi phút: chuyến "Về an toàn" quá giờ mà chưa tới → báo động cả nhóm (kèm vị trí cuối, pin)
/// và nhắc chính người đi. Nếu sau 15 phút vẫn chưa xong thì nhắc lại lần nữa.
exports.checkSafeTrips = onSchedule({ schedule: 'every 1 minutes', timeZone: 'Asia/Ho_Chi_Minh' }, async () => {
  const now = Date.now();
  const snap = await db.collectionGroup('safeTrips')
    .where('status', 'in', ['active', 'overdue'])
    .where('dueAt', '<=', new Date(now))
    .get();

  await Promise.all(snap.docs.map(async (doc) => {
    const groupRef = doc.ref.parent.parent;
    const uid = doc.id;
    const fire = await db.runTransaction(async (tx) => {
      const t = (await tx.get(doc.ref)).data();
      if (!t || !['active', 'overdue'].includes(t.status)) return null;
      // Người đã rời / bị xoá khỏi nhóm (hoặc nhóm đã bị xoá): kết thúc, không báo cả nhóm.
      const g = await tx.get(groupRef);
      if (!g.exists || !(g.get('memberIds') || []).includes(uid)) {
        tx.update(doc.ref, { status: 'ended', endedAt: FieldValue.serverTimestamp() });
        return null;
      }
      const alerts = t.alerts || 0;
      const dueMs = t.dueAt.toMillis();
      if (now > dueMs + SAFE_EXPIRE_MS) {
        tx.update(doc.ref, { status: 'ended', endedAt: FieldValue.serverTimestamp() });
        return null;
      }
      if (alerts >= SAFE_MAX_ALERTS) return null;
      if (now < dueMs + alerts * SAFE_REALERT_MS) return null;
      tx.update(doc.ref, { status: 'overdue', alerts: alerts + 1, overdueAt: FieldValue.serverTimestamp() });
      return { trip: t, repeat: alerts > 0 };
    });
    if (!fire) return;

    const loc = (await groupRef.collection('locations').doc(uid).get()).data() || {};
    const { trip, repeat } = fire;
    // Sự kiện → onGroupEvent gửi push cho các thành viên khác.
    await groupRef.collection('events').add({
      type: 'safe_overdue',
      uid,
      name: trip.name || 'Thành viên',
      placeName: trip.destName || '',
      dueAt: trip.dueAt,
      repeat,
      ...(typeof loc.lat === 'number' && loc.sharing !== false ? { lat: loc.lat, lng: loc.lng } : {}),
      ...(typeof loc.battery === 'number' ? { battery: loc.battery } : {}),
      createdAt: FieldValue.serverTimestamp(),
    });
    // Nhắc chính người đi: có thể họ quên tắt, hoặc cần gia hạn.
    await notifyUsers(groupRef.id, [uid], {
      title: `Bạn đã tới ${trip.destName || 'nơi'} chưa?`,
      body: 'Đã quá giờ dự kiến nên nhóm vừa được báo. Mở ứng dụng để báo "Tôi ổn" hoặc gia hạn.',
    }, { type: 'safe_self', uid }, null);
  }));
});

// ---------- Hồ sơ: đồng bộ tên & ảnh vào các nhóm ----------

exports.onUserProfile = onDocumentWritten('users/{uid}', async (event) => {
  const before = event.data?.before?.data() || {};
  const after = event.data?.after?.data();
  if (!after) return;
  if (before.name === after.name && before.photoUrl === after.photoUrl) return;
  const uid = event.params.uid;
  const groups = await db.collection('groups').where('memberIds', 'array-contains', uid).get();
  const batch = db.batch();
  groups.forEach((g) => batch.update(g.ref, {
    [`memberNames.${uid}`]: after.name || 'Thành viên',
    [`memberPhotos.${uid}`]: after.photoUrl || null,
  }));
  await batch.commit();
});

// ---------- Khoảnh khắc ----------

exports.onMoment = onDocumentCreated('groups/{groupId}/moments/{momentId}', async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const groupId = event.params.groupId;
  const groupName = (await db.doc(`groups/${groupId}`).get()).get('name') || 'Nhóm';
  const body = m.text ? String(m.text).slice(0, 120) : (m.photoUrl ? '📷 Đã đăng một ảnh' : 'Có khoảnh khắc mới');
  await notifyGroup(groupId, m.uid, { title: `✨ ${await displayName(m.uid)} · ${groupName}`, body },
    { type: 'moment', uid: String(m.uid || '') });
});

// ---------- Meetup ----------

exports.onMeetup = onDocumentCreated('groups/{groupId}/meetups/{meetupId}', async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const groupId = event.params.groupId;
  const when = m.time?.toDate?.();
  const time = when
    ? when.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })
    : '';
  await notifyGroup(groupId, m.createdBy, {
    title: `📍 Meetup: ${m.title}`,
    body: `${await displayName(m.createdBy)} hẹn mọi người lúc ${time}. Mở IPing để tham gia.`,
  }, { type: 'meetup', meetupId: event.params.meetupId });
});

// ---------- Tài khoản ----------

// Xoá vĩnh viễn tài khoản và toàn bộ dữ liệu của người gọi.
exports.deleteAccount = onCall({ timeoutSeconds: 300 }, async (req) => {
  const uid = requireAuth(req);

  // 1. Rời mọi nhóm (trước khi xoá users/{uid} vì cần tên cho sự kiện).
  const groups = await db.collection('groups').where('memberIds', 'array-contains', uid).get();
  for (const g of groups.docs) {
    await leaveGroupAs(uid, g.id);
    // Khoảnh khắc của người này sẽ mất ảnh nên xoá luôn.
    const moments = await g.ref.collection('moments').where('uid', '==', uid).get();
    await Promise.all(moments.docs.map((m) => db.recursiveDelete(m.ref)));
  }

  // 2. Ảnh đại diện và ảnh khoảnh khắc trên Storage.
  const bucket = getStorage().bucket();
  await bucket.deleteFiles({ prefix: `avatars/${uid}/` });
  await bucket.deleteFiles({ prefix: 'moments/', matchGlob: `moments/*/${uid}/**` });

  // 3. Hồ sơ cùng các collection con (explore...).
  await db.recursiveDelete(db.doc(`users/${uid}`));

  // 4. Cuối cùng xoá tài khoản đăng nhập.
  try {
    await getAuth().deleteUser(uid);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
  return { ok: true };
});

// ---------- Mất kết nối ----------

const STALE_MS = 60 * 60 * 1000;

/// Mỗi 15 phút: thành viên đang chia sẻ mà hơn 1 giờ không cập nhật vị trí → báo nhóm một lần cho mỗi đợt.
exports.checkStaleLocations = onSchedule({ schedule: 'every 15 minutes', timeZone: 'Asia/Ho_Chi_Minh' }, async () => {
  const cutoff = new Date(Date.now() - STALE_MS);
  const snap = await db.collectionGroup('locations')
    .where('sharing', '==', true)
    .where('updatedAt', '<=', cutoff)
    .get();

  await Promise.all(snap.docs.map(async (doc) => {
    const d = doc.data();
    // Đã báo cho lần cập nhật cuối này rồi (client ghi đè cả doc khi có vị trí mới → tự reset).
    if (d.offlineAlertedFor && d.updatedAt && d.offlineAlertedFor.isEqual(d.updatedAt)) return;
    const groupRef = doc.ref.parent.parent;
    const uid = doc.id;
    const g = await groupRef.get();
    if (!g.exists || !(g.get('memberIds') || []).includes(uid)) return;
    await doc.ref.update({ offlineAlertedFor: d.updatedAt });
    await groupRef.collection('events').add({
      type: 'offline',
      uid,
      name: d.name || 'Thành viên',
      lastAt: d.updatedAt,
      createdAt: FieldValue.serverTimestamp(),
    });
  }));
});
