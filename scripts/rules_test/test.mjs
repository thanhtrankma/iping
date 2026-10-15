// Kiểm thử firestore.rules trên emulator. Chạy từ thư mục gốc repo:
//   (cd scripts/rules_test && npm install)   # lần đầu
//   firebase emulators:exec --only firestore --project demo-iping "node scripts/rules_test/test.mjs"
// Mỗi ca ghi giống cách lib/ đang ghi (serverTimestamp, expireAt...) để không làm hỏng client.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, updateDoc, deleteDoc, addDoc, collection, writeBatch,
  serverTimestamp, Timestamp, arrayUnion, arrayRemove, deleteField, setLogLevel,
} from 'firebase/firestore';

setLogLevel('silent');

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const env = await initializeTestEnvironment({
  projectId: 'demo-iping',
  firestore: { rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8') },
});

const G = 'g1';
const OWNER = 'alice';
const BOB = 'bob';
const CAROL = 'carol';
const OUT = 'mallory'; // không ở trong nhóm
const DM = `${BOB}_${CAROL}`;

async function seed() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `groups/${G}`), {
      name: 'Gia đình', ownerId: OWNER, memberIds: [OWNER, BOB, CAROL],
      memberNames: { [OWNER]: 'Alice', [BOB]: 'Bob', [CAROL]: 'Carol' }, inviteCode: 'ABC234',
    });
    await setDoc(doc(db, `config/maps`), { key: 'x' });
    await setDoc(doc(db, `config/admins`), { uids: [OWNER] });
    await setDoc(doc(db, `dms/${DM}`), { members: [BOB, CAROL], groupId: G });
    await setDoc(doc(db, `dms/${DM}/messages/m1`), { uid: BOB, text: 'hi', createdAt: Timestamp.now() });
    await setDoc(doc(db, `groups/${G}/messages/m1`), { uid: BOB, text: 'hello', createdAt: Timestamp.now() });
    await setDoc(doc(db, `groups/${G}/moments/mo1`), { uid: BOB, text: 'x', likes: [], createdAt: Timestamp.now() });
    await setDoc(doc(db, `groups/${G}/meetups/mt1`), {
      title: 'Cafe', lat: 1, lng: 2, time: Timestamp.now(), createdBy: BOB,
      participants: { [BOB]: 'going' }, active: true, createdAt: Timestamp.now(),
    });
    await setDoc(doc(db, `groups/${G}/locations/${BOB}`), {
      name: 'Bob', lat: 10, lng: 106, accuracy: 5, speed: 1, battery: 80, sharing: true,
    });
  });
}

const as = (uid) => env.authenticatedContext(uid).firestore();
const in30d = () => Timestamp.fromMillis(Date.now() + 30 * 24 * 3600 * 1000);

const cases = [];
const test = (name, fn) => cases.push([name, fn]);

// ---------- Báo cáo vi phạm ----------
const report = (over = {}) => ({
  reporterUid: BOB, kind: 'message', reason: 'spam', targetUid: CAROL, groupId: G, targetId: 'm1',
  text: 'hello', createdAt: serverTimestamp(), ...over,
});
test('report: tạo hợp lệ', () => assertSucceeds(addDoc(collection(as(BOB), 'reports'), report())));
test('report: kind user + note', () => assertSucceeds(addDoc(collection(as(BOB), 'reports'),
  { reporterUid: BOB, kind: 'user', reason: 'harassment', targetUid: CAROL, note: 'n'.repeat(500), createdAt: serverTimestamp() })));
test('report: dm', () => assertSucceeds(addDoc(collection(as(BOB), 'reports'),
  { reporterUid: BOB, kind: 'dm', reason: 'sexual', targetUid: CAROL, dmId: DM, targetId: 'm1', createdAt: serverTimestamp() })));
test('report: mạo danh người báo cáo', () => assertFails(addDoc(collection(as(BOB), 'reports'), report({ reporterUid: CAROL }))));
test('report: kind sai', () => assertFails(addDoc(collection(as(BOB), 'reports'), report({ kind: 'group' }))));
test('report: reason sai', () => assertFails(addDoc(collection(as(BOB), 'reports'), report({ reason: 'hate' }))));
test('report: note quá dài', () => assertFails(addDoc(collection(as(BOB), 'reports'), report({ note: 'n'.repeat(501) }))));
test('report: text quá dài', () => assertFails(addDoc(collection(as(BOB), 'reports'), report({ text: 't'.repeat(1001) }))));
test('report: thiếu targetUid', () => assertFails(addDoc(collection(as(BOB), 'reports'),
  { reporterUid: BOB, kind: 'user', reason: 'spam', createdAt: serverTimestamp() })));
test('report: trường lạ (status)', () => assertFails(addDoc(collection(as(BOB), 'reports'), report({ status: 'closed' }))));
test('report: createdAt giờ máy', () => assertFails(addDoc(collection(as(BOB), 'reports'), report({ createdAt: Timestamp.now() }))));
test('report: chưa đăng nhập', () => assertFails(addDoc(collection(env.unauthenticatedContext().firestore(), 'reports'), report())));
test('report: không đọc / sửa / xoá được', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'reports/r1'), { reporterUid: BOB }));
  await assertFails(getDoc(doc(as(BOB), 'reports/r1')));
  await assertFails(updateDoc(doc(as(BOB), 'reports/r1'), { note: 'x' }));
  await assertFails(deleteDoc(doc(as(BOB), 'reports/r1')));
});
test('config: maps đọc được, admins thì không', async () => {
  await assertSucceeds(getDoc(doc(as(BOB), 'config/maps')));
  await assertFails(getDoc(doc(as(BOB), 'config/admins')));
});

// ---------- Hồ sơ / chặn ----------
test('users: lưu hồ sơ + token như client', () => assertSucceeds(setDoc(doc(as(BOB), `users/${BOB}`),
  { name: 'Bob', fcmTokens: arrayUnion('t1'), profileSyncAt: serverTimestamp() }, { merge: true })));
test('users: chặn / bỏ chặn', async () => {
  await assertSucceeds(setDoc(doc(as(BOB), `users/${BOB}`), { blockedUids: arrayUnion(CAROL) }, { merge: true }));
  await assertSucceeds(updateDoc(doc(as(BOB), `users/${BOB}`), { blockedUids: arrayRemove(CAROL) }));
});
test('users: blockedUids không phải list', () => assertFails(setDoc(doc(as(BOB), `users/${BOB}`), { blockedUids: 'x' }, { merge: true })));
test('users: blockedUids > 500', () => assertFails(setDoc(doc(as(BOB), `users/${BOB}`),
  { blockedUids: Array.from({ length: 501 }, (_, i) => `u${i}`) }, { merge: true })));
test('users: không ghi được hồ sơ người khác', () => assertFails(setDoc(doc(as(CAROL), `users/${BOB}`), { blockedUids: [] }, { merge: true })));
test('users: tên quá dài', () => assertFails(setDoc(doc(as(BOB), `users/${BOB}`), { name: 'x'.repeat(101) }, { merge: true })));

// ---------- Chat 1-1 ----------
const dmSend = (db, uid, text = 'yo') => {
  const b = writeBatch(db);
  b.set(doc(collection(db, `dms/${DM}/messages`)), { uid, name: 'x', text, createdAt: serverTimestamp() });
  b.update(doc(db, `dms/${DM}`), { lastText: text, lastUid: uid, lastAt: serverTimestamp() });
  return b.commit();
};
test('dm: gửi như DmService.send', () => assertSucceeds(dmSend(as(CAROL), CAROL)));
test('dm: người nhận chưa có hồ sơ vẫn gửi được', () => assertSucceeds(dmSend(as(BOB), BOB)));
test('dm: người nhận có hồ sơ, chặn người khác thì vẫn gửi được', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `users/${BOB}`), { blockedUids: [OUT], name: 'Bob' }));
  await assertSucceeds(dmSend(as(CAROL), CAROL));
});
test('dm: bị người nhận chặn thì không gửi được', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `users/${BOB}`), { blockedUids: [CAROL] }));
  await assertFails(dmSend(as(CAROL), CAROL));
  // Người chặn vẫn gửi được (chặn một chiều).
  await assertSucceeds(dmSend(as(BOB), BOB));
});
test('dm: createdAt giờ máy bị từ chối', () => assertFails(addDoc(collection(as(CAROL), `dms/${DM}/messages`),
  { uid: CAROL, text: 'x', createdAt: Timestamp.now() })));
test('dm: xoá tin của mình / không xoá tin người khác', async () => {
  await assertFails(deleteDoc(doc(as(CAROL), `dms/${DM}/messages/m1`)));
  await assertSucceeds(deleteDoc(doc(as(BOB), `dms/${DM}/messages/m1`)));
});
test('dm: người ngoài không đọc được', () => assertFails(getDoc(doc(as(OUT), `dms/${DM}/messages/m1`))));

// ---------- Tin nhắn nhóm ----------
test('message: gửi như GroupService.sendMessage', () => assertSucceeds(addDoc(collection(as(CAROL), `groups/${G}/messages`),
  { uid: CAROL, name: 'Carol', text: 'hi', createdAt: serverTimestamp() })));
test('message: giờ tương lai bị từ chối', () => assertFails(addDoc(collection(as(CAROL), `groups/${G}/messages`),
  { uid: CAROL, name: 'Carol', text: 'hi', createdAt: Timestamp.fromMillis(Date.now() + 1e9) })));
test('message: thành viên khác không xoá được', () => assertFails(deleteDoc(doc(as(CAROL), `groups/${G}/messages/m1`))));
test('message: người gửi xoá được', () => assertSucceeds(deleteDoc(doc(as(BOB), `groups/${G}/messages/m1`))));
test('message: chủ nhóm xoá được', () => assertSucceeds(deleteDoc(doc(as(OWNER), `groups/${G}/messages/m1`))));
test('message: người ngoài không xoá được', () => assertFails(deleteDoc(doc(as(OUT), `groups/${G}/messages/m1`))));

// ---------- Khoảnh khắc ----------
const moment = (over = {}) => ({
  uid: CAROL, name: 'Carol', text: 'hey', likes: [], lat: 1, lng: 2,
  createdAt: serverTimestamp(), clientAt: Timestamp.now(),
  expireAt: Timestamp.fromMillis(Date.now() + 24 * 3600 * 1000), ...over,
});
const photo = (gid, uid) => `https://firebasestorage.googleapis.com/v0/b/iping-share.firebasestorage.app/o/moments%2F${gid}%2F${uid}%2Fabc.jpg?alt=media&token=t`;
test('moment: đăng như GroupService.postMoment', () => assertSucceeds(setDoc(doc(as(CAROL), `groups/${G}/moments/new`), moment())));
test('moment: kèm ảnh của mình', () => assertSucceeds(setDoc(doc(as(CAROL), `groups/${G}/moments/new`), moment({ photoUrl: photo(G, CAROL) }))));
test('moment: ảnh của người khác', () => assertFails(setDoc(doc(as(CAROL), `groups/${G}/moments/new`), moment({ photoUrl: photo(G, BOB) }))));
test('moment: thiếu expireAt', () => assertFails(setDoc(doc(as(CAROL), `groups/${G}/moments/new`),
  { uid: CAROL, text: 'x', likes: [], createdAt: serverTimestamp() })));
test('moment: expireAt quá xa', () => assertFails(setDoc(doc(as(CAROL), `groups/${G}/moments/new`),
  moment({ expireAt: in30d() }))));
test('moment: thả tim', () => assertSucceeds(updateDoc(doc(as(CAROL), `groups/${G}/moments/mo1`), { likes: arrayUnion(CAROL) })));
test('moment: thành viên khác không xoá được', () => assertFails(deleteDoc(doc(as(CAROL), `groups/${G}/moments/mo1`))));
test('moment: chủ nhóm xoá được', () => assertSucceeds(deleteDoc(doc(as(OWNER), `groups/${G}/moments/mo1`))));
test('moment: người đăng xoá được', () => assertSucceeds(deleteDoc(doc(as(BOB), `groups/${G}/moments/mo1`))));

// ---------- Sự kiện ----------
const event = (over = {}) => ({ type: 'checkin', uid: CAROL, name: 'Carol', placeName: 'Nhà', lat: 1, lng: 2,
  createdAt: serverTimestamp(), expireAt: in30d(), ...over });
test('event: addEvent kèm expireAt', () => assertSucceeds(addDoc(collection(as(CAROL), `groups/${G}/events`), event())));
test('event: bản cũ không có expireAt (safe_trip_service)', () => assertSucceeds(addDoc(collection(as(CAROL), `groups/${G}/events`),
  { type: 'safe_start', uid: CAROL, name: 'Carol', placeName: 'Nhà', dueAt: Timestamp.now(), createdAt: serverTimestamp() })));
test('event: expireAt quá 31 ngày', () => assertFails(addDoc(collection(as(CAROL), `groups/${G}/events`),
  event({ expireAt: Timestamp.fromMillis(Date.now() + 40 * 24 * 3600 * 1000) }))));
test('event: expireAt không phải timestamp', () => assertFails(addDoc(collection(as(CAROL), `groups/${G}/events`), event({ expireAt: 123 }))));
test('event: createdAt giờ máy', () => assertFails(addDoc(collection(as(CAROL), `groups/${G}/events`), event({ createdAt: Timestamp.now() }))));
test('event: speeding / low_battery / location_off', async () => {
  const c = collection(as(CAROL), `groups/${G}/events`);
  await assertSucceeds(addDoc(c, { type: 'speeding', uid: CAROL, name: 'C', speed: 95, createdAt: serverTimestamp(), expireAt: in30d() }));
  await assertSucceeds(addDoc(c, { type: 'low_battery', uid: CAROL, name: 'C', battery: 10, createdAt: serverTimestamp(), expireAt: in30d() }));
  await assertSucceeds(addDoc(c, { type: 'location_off', uid: CAROL, name: 'C', createdAt: serverTimestamp(), expireAt: in30d() }));
});
test('event: mạo danh uid', () => assertFails(addDoc(collection(as(CAROL), `groups/${G}/events`), event({ uid: BOB }))));

// ---------- Ping ----------
test('ping: như GroupService.sendPing', () => assertSucceeds(addDoc(collection(as(CAROL), `groups/${G}/pings`),
  { from: CAROL, fromName: 'C', to: BOB, type: 'love', createdAt: serverTimestamp() })));
test('ping: giờ máy bị từ chối', () => assertFails(addDoc(collection(as(CAROL), `groups/${G}/pings`),
  { from: CAROL, to: BOB, type: 'love', createdAt: Timestamp.now() })));

// ---------- Meetup ----------
test('meetup: tạo như GroupService.createMeetup', () => assertSucceeds(addDoc(collection(as(CAROL), `groups/${G}/meetups`), {
  title: 'Ăn tối', lat: 1, lng: 2, time: Timestamp.now(), createdBy: CAROL, createdByName: 'C',
  participants: { [CAROL]: 'going' }, active: true, createdAt: serverTimestamp(),
})));
test('meetup: tạo kèm trạng thái người khác', () => assertFails(addDoc(collection(as(CAROL), `groups/${G}/meetups`), {
  title: 'x', lat: 1, lng: 2, time: Timestamp.now(), createdBy: CAROL, participants: { [CAROL]: 'going', [BOB]: 'going' }, active: true,
})));
test('meetup: tự đặt trạng thái của mình', () => assertSucceeds(updateDoc(doc(as(CAROL), `groups/${G}/meetups/mt1`), { [`participants.${CAROL}`]: 'declined' })));
test('meetup: đặt trạng thái người khác', () => assertFails(updateDoc(doc(as(CAROL), `groups/${G}/meetups/mt1`), { [`participants.${OWNER}`]: 'going' })));
test('meetup: người tạo cũng không đặt hộ được', () => assertFails(updateDoc(doc(as(BOB), `groups/${G}/meetups/mt1`), { [`participants.${CAROL}`]: 'going' })));
test('meetup: người tạo kết thúc', () => assertSucceeds(updateDoc(doc(as(BOB), `groups/${G}/meetups/mt1`), { active: false })));

// ---------- Vị trí ----------
test('location: ghi đầy đủ như _onPosition', () => assertSucceeds(setDoc(doc(as(CAROL), `groups/${G}/locations/${CAROL}`), {
  name: 'C', photoUrl: null, lat: 1, lng: 2, accuracy: 5, speed: 1, battery: 50, sharing: true,
  updatedAt: serverTimestamp(), lastSeenAt: serverTimestamp(), clientAt: Timestamp.now(),
})));
test('location: thôi chia sẻ → xoá toạ độ', async () => {
  await assertSucceeds(updateDoc(doc(as(BOB), `groups/${G}/locations/${BOB}`), {
    sharing: false, lat: deleteField(), lng: deleteField(), accuracy: deleteField(), speed: deleteField(),
    battery: deleteField(), updatedAt: serverTimestamp(),
  }));
});
test('location: không sửa vị trí người khác', () => assertFails(updateDoc(doc(as(CAROL), `groups/${G}/locations/${BOB}`), { sharing: false })));
test('points: ghi lịch sử kèm expireAt', () => assertSucceeds(addDoc(collection(as(CAROL), `groups/${G}/locations/${CAROL}/points`),
  { lat: 1, lng: 2, speed: 1, t: Timestamp.now(), expireAt: in30d() })));

// ---------- Nhóm ----------
test('group: chủ nhóm đổi tên', () => assertSucceeds(updateDoc(doc(as(OWNER), `groups/${G}`), { name: 'Nhà' })));
test('group: người ngoài không đọc', () => assertFails(getDoc(doc(as(OUT), `groups/${G}`))));

let failed = 0;
for (const [name, fn] of cases) {
  await seed();
  try {
    await fn();
    console.log(`  ok   ${name}`);
  } catch (e) {
    failed++;
    console.log(`  FAIL ${name}\n       ${String(e.message || e).split('\n')[0]}`);
  }
}
await env.cleanup();
console.log(failed ? `\n${failed}/${cases.length} ca lỗi` : `\nTất cả ${cases.length} ca đạt`);
process.exit(failed ? 1 : 0);
