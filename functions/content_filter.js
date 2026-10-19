'use strict';

// Bộ lọc từ ngữ không phù hợp (Apple 1.2 / Google Play UGC).
//
// BẢN SAO của lib/services/content_filter.dart: hai danh sách từ và thuật toán phải giống hệt nhau
// (kiểm tra bằng test/content_filter_test.dart và functions/content_filter.test.js).
//
// - WORDS: so khớp sau khi chuẩn hoá hoàn toàn (chữ thường, bỏ dấu tiếng Việt, đ→d, leetspeak).
//   Chỉ chứa từ không có nghĩa vô hại khi bỏ dấu.
// - STRICT: từ tiếng Việt mà khi bỏ dấu sẽ trùng từ bình thường (lồn/lon, cặc/các, địt/dít...)
//   → chỉ khớp khi đúng dấu (vẫn chịu chữ hoa, tổ hợp NFD, ký tự lặp, chèn dấu chấm/cách).
// Mỗi từ (hoặc cụm từ) khớp trọn từ, không khớp một phần từ (class, assistant, Scunthorpe).

// BEGIN WORDS
const WORDS = [
  // Tiếng Anh
  'fuck', 'fucks', 'fucked', 'fucker', 'fuckers', 'fucking', 'fuckin', 'fuckface', 'fck', 'fcking',
  'fuk', 'fuking', 'fukin', 'fuq', 'phuck', 'motherfucker', 'motherfuckers', 'motherfucking', 'mofo',
  'wtf', 'stfu', 'gtfo', 'shit', 'shits', 'shitty', 'shithead', 'shithole', 'bullshit', 'horseshit',
  'bitch', 'bitches', 'bitchy', 'biatch', 'bastard', 'bastards', 'asshole', 'assholes', 'arsehole',
  'dumbass', 'jackass', 'dick', 'dicks', 'dickhead', 'cock', 'cocks', 'cocksucker', 'pussy', 'pussies',
  'cunt', 'cunts', 'twat', 'wanker', 'wank', 'whore', 'whores', 'slut', 'sluts', 'slutty',
  'porn', 'porno', 'pornhub', 'blowjob', 'handjob', 'rimjob', 'dildo', 'dildos', 'horny',
  'boobs', 'boobies', 'tits', 'titties', 'milf', 'orgasm', 'masturbate', 'masturbating', 'masturbation',
  'jerk off', 'cumshot', 'anal', 'nudes', 'rape', 'raped', 'rapist', 'raping',
  'nigger', 'niggers', 'nigga', 'niggas', 'faggot', 'faggots', 'fag', 'fags', 'dyke', 'tranny',
  'retard', 'retarded', 'spic', 'kike', 'gook', 'wetback', 'pedo', 'pedophile', 'kys', 'kill yourself',
  // Tiếng Việt không dấu / viết tắt / teencode (không trùng từ thường)
  'dmm', 'dcm', 'dcmm', 'dkm', 'dmcs', 'vcl', 'vkl', 'clm', 'cmm', 'clgt', 'cmnr', 'loz',
  'djt', 'djtme', 'ditme', 'ditmemay', 'dit me may', 'dit con me', 'duma', 'dume', 'dumemay',
  'khieu dam', 'hiep dam', 'loan luan', 'phim sex', 'phim heo', 'trym', 'chym', 'pe de', 'tau khua',
];
// END WORDS

// BEGIN STRICT
const STRICT = [
  'địt', 'đụ', 'đéo', 'lồn', 'lìn', 'cặc', 'kặc', 'buồi', 'đĩ', 'điếm', 'phò', 'chịch', 'nứng',
  'đù má', 'mẹ kiếp', 'thằng chó', 'đồ chó', 'bú cu', 'hột le', 'thủ dâm', 'gái gọi',
  'dâm đãng', 'dâm dục', 'dâm loạn', 'dâm tặc', 'bê đê', 'khựa',
];
// END STRICT

const MASK = '***';

// Thanh điệu: '' ngang, '`' huyền, "'" sắc, '?' hỏi, '~' ngã, '.' nặng.
const TONES = ['', '`', "'", '?', '~', '.'];
// Dấu mũ / trăng / móc: '^' (â ê ô), '(' (ă), '+' (ơ ư), '-' (đ).
const VOWELS = [
  ['a', '', 'aàáảãạ'], ['a', '^', 'âầấẩẫậ'], ['a', '(', 'ăằắẳẵặ'],
  ['e', '', 'eèéẻẽẹ'], ['e', '^', 'êềếểễệ'],
  ['i', '', 'iìíỉĩị'],
  ['o', '', 'oòóỏõọ'], ['o', '^', 'ôồốổỗộ'], ['o', '+', 'ơờớởỡợ'],
  ['u', '', 'uùúủũụ'], ['u', '+', 'ưừứửữự'],
  ['y', '', 'yỳýỷỹỵ'],
];
const DECOMP = new Map([['đ', ['d', '-', '']]]);
for (const [base, shape, chars] of VOWELS) {
  [...chars].forEach((c, i) => DECOMP.set(c, [base, shape, TONES[i]]));
}
// Dấu tổ hợp (văn bản dạng NFD): [true = thanh điệu | false = dấu mũ/móc, mã].
const COMBINING = new Map([
  ['̀', [true, '`']], ['́', [true, "'"]], ['̉', [true, '?']], ['̃', [true, '~']],
  ['̣', [true, '.']], ['̂', [false, '^']], ['̆', [false, '(']], ['̛', [false, '+']],
]);
const LEET = new Map([['0', 'o'], ['1', 'i'], ['3', 'e'], ['4', 'a'], ['5', 's'], ['7', 't'], ['@', 'a'], ['$', 's']]);
const WORD_CHAR = /^[\p{L}\p{N}]$/u;
const SPACE = /\s/;

/// Tách văn bản thành các từ; mỗi từ là các "đơn vị chữ" {b: chữ gốc, s: dấu mũ, t: thanh} + vị trí gốc.
function words(text) {
  const out = [];
  let cur = null;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const comb = COMBINING.get(ch);
    if (comb) {
      if (cur && cur.end === i) {
        const u = cur.u[cur.u.length - 1];
        if (comb[0]) u.t = comb[1];
        else u.s = comb[1];
        cur.end = i + 1;
      }
      continue;
    }
    let lower = ch.toLowerCase();
    if (lower.length !== 1) lower = ch;
    let u = null;
    const d = DECOMP.get(lower);
    if (d) u = { b: d[0], s: d[1], t: d[2] };
    else if (LEET.has(lower)) u = { b: LEET.get(lower), s: '', t: '' };
    else if (WORD_CHAR.test(lower)) u = { b: lower, s: '', t: '' };
    if (!u) continue;
    if (!cur || cur.end !== i) {
      cur = { u: [], start: i, end: i };
      out.push(cur);
    }
    cur.u.push(u);
    cur.end = i + 1;
  }
  return out;
}

/// Ghép các từ bị chèn ký tự phân cách: "f.u.c.k", "đ.ụ", "f u c k", "sh-it".
function glue(ws, text) {
  const out = [];
  let prev = null;
  for (const w of ws) {
    const last = out[out.length - 1];
    if (prev && last) {
      const gap = text.slice(prev.end, w.start);
      const singles = prev.u.length === 1 && w.u.length === 1;
      if (gap.length <= 3 && (singles || !SPACE.test(gap))) {
        last.u = last.u.concat(w.u);
        last.end = w.end;
        prev = w;
        continue;
      }
    }
    out.push({ u: w.u.slice(), start: w.start, end: w.end });
    prev = w;
  }
  return out;
}

function keys(tok, strict) {
  return tok.u.map((u) => (strict ? u.b + u.s + u.t : u.b));
}

/// Gộp ký tự lặp liên tiếp ("fuuuck" → "fuck").
function collapse(ks) {
  return ks.filter((k, i) => i === 0 || k !== ks[i - 1]).join('\u0001');
}

function buildIndex(list, strict) {
  const first = new Map();
  const compact = new Map();
  const add = (map, key, entry) => {
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(entry);
  };
  for (const word of list) {
    const toks = words(word).map((w) => {
      const ks = keys(w, strict);
      return { c: collapse(ks), n: ks.length };
    });
    if (toks.length === 0) continue;
    add(first, toks[0].c, toks);
    if (toks.length > 1) {
      const all = words(word).flatMap((w) => keys(w, strict));
      add(compact, collapse(all), [{ c: collapse(all), n: all.length }]);
    }
  }
  return { first, compact, strict };
}

const INDEXES = [buildIndex(WORDS, false), buildIndex(STRICT, true)];

/// Các đoạn [start, end) trong văn bản gốc chứa từ không phù hợp.
function findSpans(text) {
  if (typeof text !== 'string' || !text) return [];
  const ws = words(text);
  const seqs = [ws, glue(ws, text)];
  const spans = [];
  for (const idx of INDEXES) {
    for (const seq of seqs) {
      const toks = seq.map((t) => {
        const ks = keys(t, idx.strict);
        return { c: collapse(ks), n: ks.length };
      });
      for (let i = 0; i < toks.length; i++) {
        const cands = [...(idx.first.get(toks[i].c) || []), ...(idx.compact.get(toks[i].c) || [])];
        for (const ent of cands) {
          if (i + ent.length > toks.length) continue;
          // Khớp trọn từ; từ bị kéo dài ("fuuuck") vẫn khớp nhưng từ ngắn hơn ("Niger") thì không.
          if (ent.every((e, j) => toks[i + j].c === e.c && toks[i + j].n >= e.n)) {
            spans.push([seq[i].start, seq[i + ent.length - 1].end]);
          }
        }
      }
    }
  }
  spans.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const merged = [];
  for (const s of spans) {
    const last = merged[merged.length - 1];
    if (last && s[0] <= last[1]) last[1] = Math.max(last[1], s[1]);
    else merged.push([s[0], s[1]]);
  }
  return merged;
}

function isFlagged(text) {
  return findSpans(text).length > 0;
}

/// Thay từ không phù hợp bằng "***"; văn bản sạch giữ nguyên.
function mask(text) {
  const spans = findSpans(text);
  if (spans.length === 0) return typeof text === 'string' ? text : '';
  let out = '';
  let pos = 0;
  for (const [s, e] of spans) {
    out += text.slice(pos, s) + MASK;
    pos = e;
  }
  return out + text.slice(pos);
}

module.exports = { WORDS, STRICT, MASK, findSpans, isFlagged, mask };
