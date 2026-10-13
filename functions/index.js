const crypto = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

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
  const snap = await db.doc(`users/${uid}`).get();
  return snap.get('name') || 'Thành viên';
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

  const joined = await db.runTransaction(async (tx) => {
    const g = await tx.get(groupRef);
    if (!g.exists) throw new HttpsError('not-found', 'Nhóm không còn tồn tại.');
    const members = g.get('memberIds') || [];
    if (members.includes(uid)) return false;
    if (members.length >= MAX_MEMBERS) {
      throw new HttpsError('failed-precondition', `Nhóm đã đủ ${MAX_MEMBERS} thành viên.`);
    }
    tx.update(groupRef, {
      memberIds: FieldValue.arrayUnion(uid),
      [`memberNames.${uid}`]: memberName,
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

exports.leaveGroup = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? '');
  if (!groupId) throw new HttpsError('invalid-argument', 'Thiếu groupId.');
  const groupRef = db.doc(`groups/${groupId}`);

  const result = await db.runTransaction(async (tx) => {
    const g = await tx.get(groupRef);
    if (!g.exists) return { deleted: false, remaining: [] };
    const remaining = (g.get('memberIds') || []).filter((m) => m !== uid);
    if (remaining.length === 0) {
      tx.delete(db.doc(`inviteCodes/${g.get('inviteCode')}`));
      return { deleted: true, remaining };
    }
    const update = {
      memberIds: FieldValue.arrayRemove(uid),
      [`memberNames.${uid}`]: FieldValue.delete(),
    };
    if (g.get('ownerId') === uid) update.ownerId = remaining[0];
    tx.update(groupRef, update);
    return { deleted: false, remaining };
  });

  if (result.deleted) {
    await db.recursiveDelete(groupRef);
  } else {
    await groupRef.collection('locations').doc(uid).delete();
    await groupRef.collection('events').add({
      type: 'leave_group', uid, name: await displayName(uid), createdAt: FieldValue.serverTimestamp(),
    });
  }
  return { ok: true };
});

// ---------- Thông báo đẩy ----------

async function notifyGroup(groupId, exceptUid, notification, data) {
  const g = await db.doc(`groups/${groupId}`).get();
  if (!g.exists) return;
  const targets = (g.get('memberIds') || []).filter((m) => m !== exceptUid);
  await notifyUsers(groupId, targets, notification, data);
}

async function notifyUsers(groupId, targets, notification, data) {
  if (targets.length === 0) return;

  const userSnaps = await db.getAll(...targets.map((m) => db.doc(`users/${m}`)));
  const tokenOwners = new Map();
  for (const u of userSnaps) {
    for (const t of u.get('fcmTokens') || []) tokenOwners.set(t, u.id);
  }
  const tokens = [...tokenOwners.keys()];
  if (tokens.length === 0) return;

  const isSos = data.type === 'sos';
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification,
    data: { groupId, ...data },
    android: { priority: 'high' },
    apns: { payload: { aps: { sound: 'default', 'interruption-level': isSos ? 'time-sensitive' : 'active' } } },
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
    default:
      return;
  }
  await notifyGroup(groupId, e.uid, notification, { type: e.type });
});

exports.onGroupMessage = onDocumentCreated('groups/{groupId}/messages/{messageId}', async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const groupId = event.params.groupId;
  const groupName = (await db.doc(`groups/${groupId}`).get()).get('name') || 'Nhóm';
  await notifyGroup(groupId, m.uid, {
    title: `${m.name} · ${groupName}`,
    body: String(m.text).slice(0, 200),
  }, { type: 'message' });
});

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
  if (!p || !PING_TEXT[p.type]) return;
  const groupId = event.params.groupId;
  const g = await db.doc(`groups/${groupId}`).get();
  if (!(g.get('memberIds') || []).includes(p.to)) return;
  await notifyUsers(groupId, [p.to], { title: p.fromName || 'IPing', body: PING_TEXT[p.type] }, { type: 'ping' });
});
