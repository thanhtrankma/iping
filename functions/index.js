const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated, onDocumentDeleted, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { setGlobalOptions } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { wantsAlert, blockedSender, CRITICAL } = require('./alert_prefs');

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
  const name = snap.get('name');
  if (name) return name;
  // Hồ sơ thiếu tên (tài khoản cũ / đăng nhập Google): lấy tên từ Firebase Auth và lưu bổ sung.
  const authName = await getAuth().getUser(uid).then((u) => (u.displayName || '').trim(), () => '');
  if (!authName) return 'Thành viên';
  await db.doc(`users/${uid}`).set({ name: authName }, { merge: true });
  return authName;
}

// ---------- Lưu trữ ----------

// Sự kiện nhóm (kể cả toạ độ SOS / check-in) tự xoá sau 30 ngày bằng Firestore TTL trên `expireAt`.
const EVENT_TTL_MS = 30 * 24 * 60 * 60 * 1000;
// Báo cáo vi phạm giữ tối đa 1 năm cho việc kiểm duyệt.
const REPORT_TTL_MS = 365 * 24 * 60 * 60 * 1000;

function eventExpireAt(from = Date.now()) {
  return Timestamp.fromMillis(from + EVENT_TTL_MS);
}

// Firestore giới hạn 500 thao tác mỗi batch.
const BATCH_SIZE = 400;

/// Xoá (hoặc cập nhật bằng `update`) các doc theo từng batch.
async function commitInChunks(refs, update) {
  for (let i = 0; i < refs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + BATCH_SIZE)) {
      if (update) batch.update(ref, update);
      else batch.delete(ref);
    }
    await batch.commit();
  }
}

/// Xoá mọi doc khớp truy vấn, mỗi lần tối đa BATCH_SIZE doc.
async function deleteQuery(query) {
  for (;;) {
    const snap = await query.limit(BATCH_SIZE).get();
    if (snap.empty) return;
    await commitInChunks(snap.docs.map((d) => d.ref));
    if (snap.size < BATCH_SIZE) return;
  }
}

// Xoá ảnh trên Storage theo tiền tố (ví dụ cả nhóm). Lỗi chỉ ghi log.
async function deleteFilesWithPrefix(prefix) {
  try {
    await getStorage().bucket().deleteFiles({ prefix, force: true });
  } catch (e) {
    console.warn('deleteFilesWithPrefix', prefix, e.message);
  }
}

// ---------- Giới hạn tần suất push ----------

/// Cho phép tối đa 1 lần mỗi `minMs` cho cùng một khoá (ví dụ nhóm + người + loại).
/// Chỉ chặn việc gửi push, không xoá dữ liệu. Doc `rateLimits/*` client không đọc/ghi được, tự xoá sau 1 ngày (TTL).
async function allowRate(key, minMs) {
  const id = crypto.createHash('sha1').update(key).digest('hex');
  const ref = db.doc(`rateLimits/${id}`);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const now = Date.now();
      const last = snap.exists ? snap.get('at') || 0 : 0;
      if (now - last < minMs) return false;
      tx.set(ref, { at: now, expireAt: Timestamp.fromMillis(now + 24 * 3600 * 1000) });
      return true;
    });
  } catch (e) {
    // Lỗi tranh chấp transaction khi bị dội liên tục: coi như vượt giới hạn.
    console.warn('rate limit', key, e.message);
    return false;
  }
}

// Khoảng tối thiểu giữa hai push cùng loại của một người trong một nhóm.
const EVENT_RATE_MS = {
  sos: 30 * 1000,
  checkin: 60 * 1000,
  low_battery: 30 * 60 * 1000,
  speeding: 5 * 60 * 1000,
  location_off: 10 * 60 * 1000,
};
const DEFAULT_EVENT_RATE_MS = 5 * 1000;
// Sự kiện do chính server tạo (không cần giới hạn).
const SERVER_EVENTS = new Set(['join', 'leave_group', 'removed', 'safe_overdue', 'offline']);

/// Tên của `uid` theo server: `memberNames` của nhóm, nếu không có thì hồ sơ.
/// Không dùng `name`/`fromName`/`createdByName` do client ghi để tránh mạo danh trong push.
async function nameIn(groupSnap, uid) {
  const n = (groupSnap?.get?.('memberNames') || {})[uid];
  if (typeof n === 'string' && n.trim()) return n.trim().slice(0, 50);
  if (!uid || typeof uid !== 'string') return 'Thành viên';
  return displayName(uid);
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
      type: 'join', uid, name: memberName, createdAt: FieldValue.serverTimestamp(), expireAt: eventExpireAt(),
    });
  }
  return { groupId: groupRef.id };
});

// Gỡ một thành viên khỏi nhóm: chuyển quyền chủ nhóm, xoá nhóm khi không còn ai.
// `announce`: ghi sự kiện "đã rời nhóm" (không ghi khi xoá tài khoản: không để lại tên / uid).
async function leaveGroupAs(uid, groupId, { announce = true } = {}) {
  const groupRef = db.doc(`groups/${groupId}`);

  const result = await db.runTransaction(async (tx) => {
    const g = await tx.get(groupRef);
    if (!g.exists) return { deleted: false, missing: true };
    const remaining = (g.get('memberIds') || []).filter((m) => m !== uid);
    if (remaining.length === 0) {
      tx.delete(db.doc(`inviteCodes/${g.get('inviteCode')}`));
      // Xoá luôn doc nhóm trong transaction: nếu bước dọn subcollection phía sau lỗi,
      // cũng không còn nhóm "mồ côi" (còn memberIds nhưng mất mã mời).
      tx.delete(groupRef);
      return { deleted: true };
    }
    const update = {
      memberIds: FieldValue.arrayRemove(uid),
      [`memberNames.${uid}`]: FieldValue.delete(),
      [`memberPhotos.${uid}`]: FieldValue.delete(),
    };
    if (g.get('ownerId') === uid) update.ownerId = remaining[0];
    tx.update(groupRef, update);
    return { deleted: false, name: g.get(`memberNames.${uid}`) };
  });

  if (result.missing) return;
  if (result.deleted) {
    await db.recursiveDelete(groupRef);
    await deleteFilesWithPrefix(`moments/${groupId}/`);
  } else {
    await removeMemberData(groupRef, uid);
    if (announce) {
      await groupRef.collection('events').add({
        type: 'leave_group', uid, name: result.name || await displayName(uid),
        createdAt: FieldValue.serverTimestamp(), expireAt: eventExpireAt(),
      });
    }
  }
}

exports.leaveGroup = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? '');
  if (!groupId) throw new HttpsError('invalid-argument', 'Thiếu groupId.');
  await leaveGroupAs(uid, groupId);
  return { ok: true };
});

/// Xoá lịch sử vị trí (points) của `uid` trong nhóm và ẩn vị trí cuối (không còn toạ độ / "đang chia sẻ").
async function forgetLocation(groupRef, uid) {
  const locRef = groupRef.collection('locations').doc(uid);
  await db.recursiveDelete(locRef.collection('points'));
  try {
    await locRef.update({
      sharing: false,
      lat: FieldValue.delete(),
      lng: FieldValue.delete(),
      accuracy: FieldValue.delete(),
      speed: FieldValue.delete(),
      battery: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // Chưa từng chia sẻ với nhóm này: không có gì để ẩn.
    if (e.code !== 5 && e.code !== 'not-found') throw e; // 5 = NOT_FOUND
  }
}

/// Dọn toàn bộ dữ liệu của `uid` trong một nhóm (rời nhóm, bị xoá khỏi nhóm, xoá tài khoản):
/// vị trí + lịch sử, điểm khám phá, chuyến "Về an toàn", sự kiện (kể cả toạ độ SOS / check-in),
/// tin nhắn nhóm, ping, khoảnh khắc (+ ảnh), meetup đã tạo, trạng thái tham gia meetup và lượt tim.
async function removeMemberData(groupRef, uid) {
  await db.recursiveDelete(groupRef.collection('locations').doc(uid));
  await groupRef.collection('explore').doc(uid).delete();
  await groupRef.collection('safeTrips').doc(uid).delete();

  await deleteQuery(groupRef.collection('events').where('uid', '==', uid));
  await deleteQuery(groupRef.collection('messages').where('uid', '==', uid));
  await deleteQuery(groupRef.collection('pings').where('from', '==', uid));
  await deleteQuery(groupRef.collection('pings').where('to', '==', uid));

  // Khoảnh khắc: xoá doc (onMomentDeleted xoá ảnh) và xoá cả thư mục ảnh của người này cho chắc.
  await deleteQuery(groupRef.collection('moments').where('uid', '==', uid));
  await deleteFilesWithPrefix(`moments/${groupRef.id}/${uid}/`);
  const liked = await groupRef.collection('moments').where('likes', 'array-contains', uid).get();
  await commitInChunks(liked.docs.map((d) => d.ref), { likes: FieldValue.arrayRemove(uid) });

  // Meetup do người này tạo: xoá. Meetup khác: bỏ trạng thái tham gia của người này.
  const meetups = await groupRef.collection('meetups').get();
  const mine = meetups.docs.filter((d) => d.get('createdBy') === uid);
  await Promise.all(mine.map((d) => db.recursiveDelete(d.ref)));
  const joined = meetups.docs.filter((d) => d.get('createdBy') !== uid && uid in (d.get('participants') || {}));
  await commitInChunks(joined.map((d) => d.ref), { [`participants.${uid}`]: FieldValue.delete() });

  // Địa điểm (Nhà, Trường...) là của chung nhóm: giữ lại nhưng bỏ thông tin người tạo.
  const places = await groupRef.collection('places').where('createdBy', '==', uid).get();
  await commitInChunks(places.docs.map((d) => d.ref), { createdBy: FieldValue.delete() });
}

exports.forgetMyLocationInGroup = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? '');
  if (!groupId) throw new HttpsError('invalid-argument', 'Thiếu groupId.');
  // Không cần kiểm tra thành viên: chỉ xoá dữ liệu của chính người gọi.
  await forgetLocation(db.doc(`groups/${groupId}`), uid);
  return { ok: true };
});

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
      type: 'removed', uid: target, name: result.name,
      createdAt: FieldValue.serverTimestamp(), expireAt: eventExpireAt(),
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
    // Người nhận đã chặn người gửi.
    if (blockedSender(u.data(), data.type, senderUid)) continue;
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
    // SOS: kênh "sos" có tiếng còi (Android), file sos_siren.caf trong bundle (iOS).
    android: isSos ? { priority: 'high', notification: { channelId: 'sos', sound: 'sos_siren' } } : { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          sound: isSos ? 'sos_siren.caf' : 'default',
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
  // Bản app cũ không ghi `expireAt`: bổ sung để TTL tự xoá sự kiện sau 30 ngày.
  if (!e.expireAt) {
    const created = e.createdAt?.toMillis?.() ?? Date.now();
    await event.data.ref.update({ expireAt: eventExpireAt(created) }).catch((err) => console.warn('event expireAt', err.message));
  }
  const groupId = event.params.groupId;
  const g = await db.doc(`groups/${groupId}`).get();
  if (!g.exists) return;
  // Tên lấy từ server (nhóm / hồ sơ), không tin `name` do client gửi. Người vừa bị xoá / rời nhóm
  // không còn trong memberNames → dùng tên trong sự kiện do chính server ghi.
  e.name = SERVER_EVENTS.has(e.type) && e.name ? String(e.name) : await nameIn(g, e.uid);
  const groupName = g.get('name') || 'Nhóm';

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
        body: `📵 Chưa thấy ${e.name} hoạt động từ ${hhmm(e.lastAt)} (có thể mất mạng, hết pin hoặc tắt máy)`,
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
  if (!SERVER_EVENTS.has(e.type)) {
    // Đến/rời nhiều địa điểm cùng lúc là hợp lệ → khoá theo cả tên địa điểm.
    const kind = e.type === 'arrive' || e.type === 'leave' ? `${e.type}:${e.placeName || ''}` : e.type;
    const minMs = EVENT_RATE_MS[e.type] ?? DEFAULT_EVENT_RATE_MS;
    if (!(await allowRate(`event:${groupId}:${e.uid}:${kind}`, minMs))) return;
  }
  await notifyGroup(groupId, e.uid, notification, { type: e.type, uid: String(e.uid || '') });
});

exports.onGroupMessage = onDocumentCreated('groups/{groupId}/messages/{messageId}', async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const groupId = event.params.groupId;
  const g = await db.doc(`groups/${groupId}`).get();
  if (!g.exists) return;
  // Nhắn dồn dập: tối đa 1 push mỗi 3 giây cho mỗi người gửi.
  if (!(await allowRate(`message:${groupId}:${m.uid}`, 3 * 1000))) return;
  const groupName = g.get('name') || 'Nhóm';
  await notifyGroup(groupId, m.uid, {
    title: `${await nameIn(g, m.uid)} · ${groupName}`,
    body: String(m.text).slice(0, 200),
  }, { type: 'message', uid: String(m.uid || '') });
});

// Giới hạn tần suất ping theo cặp người gửi → người nhận (chống spam push, hao pin máy bị yêu cầu vị trí).
const PING_COOLDOWN_MS = { locate: 60 * 1000, ping: 5 * 1000 };

function allowPing(groupId, p) {
  const key = p.type === 'locate' ? 'locate' : 'ping';
  return allowRate(`ping:${groupId}:${p.from}:${p.to}:${key}`, PING_COOLDOWN_MS[key]);
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
  const name = await nameIn(g, p.from);
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
      name: (await displayName(uid)),
      placeName: trip.destName || '',
      dueAt: trip.dueAt,
      repeat,
      ...(typeof loc.lat === 'number' && loc.sharing !== false ? { lat: loc.lat, lng: loc.lng } : {}),
      ...(typeof loc.battery === 'number' ? { battery: loc.battery } : {}),
      createdAt: FieldValue.serverTimestamp(),
      expireAt: eventExpireAt(),
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
  // `profileSyncAt` đổi mỗi lần người dùng bấm lưu hồ sơ, để lưu lại cùng tên vẫn đồng bộ lại các nhóm.
  if (before.name === after.name && before.photoUrl === after.photoUrl
      && String(before.profileSyncAt?.toMillis?.()) === String(after.profileSyncAt?.toMillis?.())) return;
  const uid = event.params.uid;
  const groups = await db.collection('groups').where('memberIds', 'array-contains', uid).get();
  const name = after.name || 'Thành viên';
  const photoUrl = after.photoUrl || null;
  const batch = db.batch();
  for (const g of groups.docs) {
    batch.update(g.ref, { [`memberNames.${uid}`]: name, [`memberPhotos.${uid}`]: photoUrl });
    // Bản ghi vị trí cũng mang tên/ảnh (ghim bản đồ, danh sách thành viên) nên cập nhật luôn,
    // không phải đợi lần gửi vị trí tiếp theo.
    const loc = g.ref.collection('locations').doc(uid);
    if ((await loc.get()).exists) batch.update(loc, { name, photoUrl });
  }
  await batch.commit();
});

// ---------- Khoảnh khắc ----------

exports.onMoment = onDocumentCreated('groups/{groupId}/moments/{momentId}', async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const groupId = event.params.groupId;
  const g = await db.doc(`groups/${groupId}`).get();
  if (!g.exists) return;
  if (!(await allowRate(`moment:${groupId}:${m.uid}`, 30 * 1000))) return;
  const groupName = g.get('name') || 'Nhóm';
  const body = m.text ? String(m.text).slice(0, 120) : (m.photoUrl ? '📷 Đã đăng một ảnh' : 'Có khoảnh khắc mới');
  await notifyGroup(groupId, m.uid, { title: `✨ ${await nameIn(g, m.uid)} · ${groupName}`, body },
    { type: 'moment', uid: String(m.uid || '') });
});

/// Khoảnh khắc bị xoá (người đăng / chủ nhóm xoá, TTL 24 giờ, rời nhóm, xoá nhóm) → xoá ảnh trên Storage.
exports.onMomentDeleted = onDocumentDeleted('groups/{groupId}/moments/{momentId}', async (event) => {
  const m = event.data?.data();
  if (!m?.photoUrl || typeof m.uid !== 'string' || !m.uid) return;
  const { groupId, momentId } = event.params;
  try {
    await getStorage().bucket().file(`moments/${groupId}/${m.uid}/${momentId}.jpg`).delete({ ignoreNotFound: true });
  } catch (e) {
    console.warn('delete moment photo', groupId, momentId, e.message);
  }
});

// ---------- Meetup ----------

exports.onMeetup = onDocumentCreated('groups/{groupId}/meetups/{meetupId}', async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const groupId = event.params.groupId;
  const g = await db.doc(`groups/${groupId}`).get();
  if (!g.exists) return;
  if (!(await allowRate(`meetup:${groupId}:${m.createdBy}`, 30 * 1000))) return;
  const when = m.time?.toDate?.();
  const time = when
    ? when.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })
    : '';
  await notifyGroup(groupId, m.createdBy, {
    title: `📍 Meetup: ${String(m.title || '').slice(0, 80)}`,
    body: `${await nameIn(g, m.createdBy)} hẹn mọi người lúc ${time}. Mở IPing để tham gia.`,
  }, { type: 'meetup', meetupId: event.params.meetupId });
});

// ---------- Báo cáo vi phạm ----------

const REPORT_KIND = { message: 'tin nhắn nhóm', dm: 'tin nhắn riêng', moment: 'khoảnh khắc', user: 'người dùng' };
const REPORT_REASON = { spam: 'spam', harassment: 'quấy rối', sexual: 'nội dung tình dục', violence: 'bạo lực', other: 'khác' };

/// Đọc lại nội dung bị báo cáo phía server (để còn bằng chứng nếu người đăng xoá sau đó).
async function reportedContent(r) {
  const id = typeof r.targetId === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(r.targetId) ? r.targetId : null;
  const safe = (v) => (typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v) ? v : null);
  let ref = null;
  if (r.kind === 'message' && safe(r.groupId) && id) ref = db.doc(`groups/${r.groupId}/messages/${id}`);
  if (r.kind === 'moment' && safe(r.groupId) && id) ref = db.doc(`groups/${r.groupId}/moments/${id}`);
  if (r.kind === 'dm' && safe(r.dmId) && id) ref = db.doc(`dms/${r.dmId}/messages/${id}`);
  if (!ref) return null;
  const snap = await ref.get();
  if (!snap.exists) return null;
  const d = snap.data();
  return {
    uid: typeof d.uid === 'string' ? d.uid : null,
    text: typeof d.text === 'string' ? d.text.slice(0, 1000) : null,
    photoUrl: typeof d.photoUrl === 'string' ? d.photoUrl : null,
  };
}

/// Báo cáo mới: đánh dấu `open`, lưu bản sao nội dung, hẹn giờ xoá (1 năm) và báo cho quản trị viên
/// (uid trong `config/admins.uids`).
exports.onReport = onDocumentCreated('reports/{reportId}', async (event) => {
  const r = event.data?.data();
  if (!r) return;
  const reportId = event.params.reportId;
  let content = null;
  try {
    content = await reportedContent(r);
  } catch (e) {
    console.warn('report content', reportId, e.message);
  }
  const created = r.createdAt?.toMillis?.() ?? Date.now();
  await event.data.ref.update({
    status: 'open',
    expireAt: Timestamp.fromMillis(created + REPORT_TTL_MS),
    ...(content ? { content } : {}),
  });

  const admins = ((await db.doc('config/admins').get()).get('uids') || []).filter((u) => typeof u === 'string');
  const summary = `${REPORT_KIND[r.kind] || r.kind} · ${REPORT_REASON[r.reason] || r.reason}`;
  if (admins.length === 0) {
    console.warn('Báo cáo vi phạm mới nhưng chưa cấu hình config/admins.uids', reportId, summary);
    return;
  }
  // Chống spam báo cáo: tối đa 1 push mỗi 10 giây cho mỗi người báo cáo.
  if (!(await allowRate(`report:${r.reporterUid}`, 10 * 1000))) return;
  const text = String(content?.text || r.text || r.note || '').slice(0, 120);
  await notifyUsers(String(r.groupId || ''), admins, {
    title: `🚩 Báo cáo vi phạm: ${summary}`,
    body: text || `Người bị báo cáo: ${r.targetUid}`,
  }, { type: 'report', reportId }, null);
});

// ---------- Tài khoản ----------

// Xoá vĩnh viễn tài khoản và toàn bộ dữ liệu của người gọi.
exports.deleteAccount = onCall({ timeoutSeconds: 540, memory: '512MiB' }, async (req) => {
  const uid = requireAuth(req);

  // 1. Rời mọi nhóm; removeMemberData xoá vị trí, lịch sử, sự kiện, tin nhắn, ping, khoảnh khắc (+ ảnh),
  //    meetup, trạng thái tham gia, lượt tim của người này trong nhóm. Không ghi sự kiện "đã rời nhóm".
  const groups = await db.collection('groups').where('memberIds', 'array-contains', uid).get();
  for (const g of groups.docs) {
    await leaveGroupAs(uid, g.id, { announce: false });
  }

  // Nhóm đã chặn người này: bỏ tên (và uid) khỏi danh sách chặn.
  const blockedIn = await db.collection('groups').where('blockedIds', 'array-contains', uid).get();
  await commitInChunks(blockedIn.docs.map((d) => d.ref), {
    blockedIds: FieldValue.arrayRemove(uid),
    [`blockedNames.${uid}`]: FieldValue.delete(),
  });

  // Chat 1-1 của người này (cả nội dung tin nhắn).
  const dms = await db.collection('dms').where('members', 'array-contains', uid).get();
  await Promise.all(dms.docs.map((d) => db.recursiveDelete(d.ref)));

  // Báo cáo vi phạm do người này gửi.
  await deleteQuery(db.collection('reports').where('reporterUid', '==', uid));

  // 2. Ảnh đại diện và ảnh khoảnh khắc trên Storage.
  const bucket = getStorage().bucket();
  await bucket.deleteFiles({ prefix: `avatars/${uid}/`, force: true });
  await bucket.deleteFiles({ prefix: 'moments/', matchGlob: `moments/*/${uid}/**`, force: true });

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

// Client ghi `lastSeenAt` mỗi 15 phút khi đang chia sẻ (kể cả đứng yên). Ngưỡng 4 giờ chừa chỗ cho iOS
// tạm dừng app chạy nền, để không báo nhầm người chỉ đang ngồi yên / ngủ.
const STALE_MS = 4 * 60 * 60 * 1000;

/// Mỗi 15 phút: thành viên đang chia sẻ mà quá 4 giờ không thấy hoạt động → báo nhóm một lần cho mỗi đợt.
exports.checkStaleLocations = onSchedule({ schedule: 'every 15 minutes', timeZone: 'Asia/Ho_Chi_Minh' }, async () => {
  const cutoff = new Date(Date.now() - STALE_MS);
  // Doc chưa có lastSeenAt (bản app cũ) không khớp truy vấn nên không bị báo nhầm.
  const snap = await db.collectionGroup('locations')
    .where('sharing', '==', true)
    .where('lastSeenAt', '<=', cutoff)
    .get();

  await Promise.all(snap.docs.map(async (doc) => {
    const d = doc.data();
    // Đã báo cho lần hoạt động cuối này rồi (heartbeat / vị trí mới sẽ đổi lastSeenAt → tự reset).
    if (d.offlineAlertedFor && d.lastSeenAt && d.offlineAlertedFor.isEqual(d.lastSeenAt)) return;
    const groupRef = doc.ref.parent.parent;
    const uid = doc.id;
    const g = await groupRef.get();
    if (!g.exists || !(g.get('memberIds') || []).includes(uid)) return;
    await doc.ref.update({ offlineAlertedFor: d.lastSeenAt });
    await groupRef.collection('events').add({
      type: 'offline',
      uid,
      name: g.get(`memberNames.${uid}`) || d.name || 'Thành viên',
      lastAt: d.lastSeenAt,
      createdAt: FieldValue.serverTimestamp(),
      expireAt: eventExpireAt(),
    });
  }));
});

// ---------- Chat 1-1 ----------

exports.onDmMessage = onDocumentCreated('dms/{dmId}/messages/{messageId}', async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const dm = (await db.doc(`dms/${event.params.dmId}`).get()).data();
  if (!dm || !(dm.members || []).includes(m.uid)) return;
  // Hai người phải vẫn còn chung nhóm (người bị chặn / xoá / đã rời không gửi push được).
  const g = await db.doc(`groups/${dm.groupId}`).get();
  const ids = g.exists ? g.get('memberIds') || [] : [];
  if (!dm.members.every((u) => ids.includes(u))) return;
  const others = dm.members.filter((u) => u !== m.uid);
  // Người nhận đã chặn người gửi: rules đã từ chối tin mới; notifyUsers cũng bỏ qua (blockedUids).
  if (!(await allowRate(`dm:${event.params.dmId}:${m.uid}`, 3 * 1000))) return;
  await notifyUsers(dm.groupId || '', others, {
    title: `💬 ${await nameIn(g, m.uid)}`,
    body: String(m.text).slice(0, 200),
  }, { type: 'dm', uid: String(m.uid), dmId: event.params.dmId }, m.uid);
});
