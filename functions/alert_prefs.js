// Lọc thông báo đẩy theo `users/{uid}.alertPrefs` = { types: {key: bool}, mutedUids: [uid] }.
// Phải khớp với lib/services/alert_prefs.dart.

// data.type -> khoá cài đặt.
const PREF_KEY = {
  arrive: 'place',
  leave: 'place',
  sos: 'sos',
  join: 'join',
  meetup_arrive: 'meetup',
  message: 'message',
  dm: 'message',
  moment: 'moment',
  meetup: 'meetup',
  ping: 'ping',
  low_battery: 'battery',
  speeding: 'speeding',
  offline: 'offline',
  location_off: 'offline',
  safe_start: 'safe',
  safe_arrive: 'safe',
  safe_end: 'safe',
  safe_ok: 'safe',
  safe_extend: 'safe',
  // Quá giờ "Về an toàn" là cảnh báo khẩn: đi theo công tắc SOS.
  safe_overdue: 'sos',
};

// Cảnh báo khẩn vẫn đến dù người nhận đã tắt cảnh báo từ người gửi.
const CRITICAL = new Set(['sos', 'safe_overdue']);

function prefKeyFor(type) {
  return PREF_KEY[type] || null;
}

/// Người nhận có muốn nhận thông báo loại `type` từ `senderUid` không. Mặc định là có.
function wantsAlert(userData, type, senderUid) {
  const prefs = userData?.alertPrefs;
  if (!prefs || typeof prefs !== 'object') return true;
  const key = prefKeyFor(type);
  if (key && prefs.types && prefs.types[key] === false) return false;
  // SOS vẫn đến dù đã tắt cảnh báo từ người gửi (chỉ tắt được bằng công tắc SOS).
  if (!CRITICAL.has(type) && senderUid && Array.isArray(prefs.mutedUids) && prefs.mutedUids.includes(senderUid)) {
    return false;
  }
  return true;
}

/// Người nhận đã chặn `senderUid` (`users/{uid}.blockedUids`): không gửi push từ người đó
/// (tin nhắn, khoảnh khắc, ping...). Cảnh báo khẩn (SOS, quá giờ "Về an toàn") vẫn đến.
function blockedSender(userData, type, senderUid) {
  if (!senderUid || CRITICAL.has(type)) return false;
  const blocked = userData?.blockedUids;
  return Array.isArray(blocked) && blocked.includes(senderUid);
}

module.exports = { PREF_KEY, CRITICAL, prefKeyFor, wantsAlert, blockedSender };
