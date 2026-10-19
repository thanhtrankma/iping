/// Bộ lọc từ ngữ không phù hợp (Apple 1.2 / Google Play UGC).
///
/// BẢN SAO của functions/content_filter.js: hai danh sách từ và thuật toán phải giống hệt nhau
/// (kiểm tra bằng test/content_filter_test.dart và functions/content_filter.test.js).
///
/// - [words]: so khớp sau khi chuẩn hoá hoàn toàn (chữ thường, bỏ dấu tiếng Việt, đ→d, leetspeak).
///   Chỉ chứa từ không có nghĩa vô hại khi bỏ dấu.
/// - [strict]: từ tiếng Việt mà khi bỏ dấu sẽ trùng từ bình thường (lồn/lon, cặc/các, địt/dít...)
///   → chỉ khớp khi đúng dấu (vẫn chịu chữ hoa, tổ hợp NFD, ký tự lặp, chèn dấu chấm/cách).
/// Mỗi từ (hoặc cụm từ) khớp trọn từ, không khớp một phần từ (class, assistant, Scunthorpe).
class ContentFilter {
  ContentFilter._();

  // BEGIN WORDS
  static const words = [
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
  static const strict = [
    'địt', 'đụ', 'đéo', 'lồn', 'lìn', 'cặc', 'kặc', 'buồi', 'đĩ', 'điếm', 'phò', 'chịch', 'nứng',
    'đù má', 'mẹ kiếp', 'thằng chó', 'đồ chó', 'bú cu', 'hột le', 'thủ dâm', 'gái gọi',
    'dâm đãng', 'dâm dục', 'dâm loạn', 'dâm tặc', 'bê đê', 'khựa',
  ];
  // END STRICT

  static const maskText = '***';

  /// Văn bản có từ không phù hợp không.
  static bool isFlagged(String? text) => findSpans(text).isNotEmpty;

  /// Thay từ không phù hợp bằng "***"; văn bản sạch giữ nguyên.
  /// Dùng khi hiển thị (lọc cả nội dung cũ), có bộ nhớ đệm nhỏ.
  static String mask(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    final cached = _cache.remove(text);
    if (cached != null) return _cache[text] = cached;
    final spans = findSpans(text);
    var out = text;
    if (spans.isNotEmpty) {
      final b = StringBuffer();
      var pos = 0;
      for (final s in spans) {
        b
          ..write(text.substring(pos, s.$1))
          ..write(maskText);
        pos = s.$2;
      }
      b.write(text.substring(pos));
      out = b.toString();
    }
    if (_cache.length >= 500) _cache.remove(_cache.keys.first);
    return _cache[text] = out;
  }

  static final _cache = <String, String>{};

  /// Các đoạn [start, end) trong văn bản gốc chứa từ không phù hợp.
  static List<(int, int)> findSpans(String? text) {
    if (text == null || text.isEmpty) return const [];
    final ws = _words(text);
    final seqs = [ws, _glue(ws, text)];
    final spans = <(int, int)>[];
    for (final idx in _indexes) {
      for (final seq in seqs) {
        final toks = [
          for (final t in seq) _Key(_collapse(_keys(t, idx.strict)), t.u.length),
        ];
        for (var i = 0; i < toks.length; i++) {
          final cands = [...?idx.first[toks[i].c], ...?idx.compact[toks[i].c]];
          for (final ent in cands) {
            if (i + ent.length > toks.length) continue;
            // Khớp trọn từ; từ bị kéo dài ("fuuuck") vẫn khớp nhưng từ ngắn hơn ("Niger") thì không.
            var ok = true;
            for (var j = 0; j < ent.length && ok; j++) {
              ok = toks[i + j].c == ent[j].c && toks[i + j].n >= ent[j].n;
            }
            if (ok) spans.add((seq[i].start, seq[i + ent.length - 1].end));
          }
        }
      }
    }
    spans.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    final merged = <(int, int)>[];
    for (final s in spans) {
      if (merged.isNotEmpty && s.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, s.$2 > last.$2 ? s.$2 : last.$2));
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  // ---- Chuẩn hoá ----

  // Thanh điệu: '' ngang, '`' huyền, "'" sắc, '?' hỏi, '~' ngã, '.' nặng.
  static const _tones = ['', '`', "'", '?', '~', '.'];
  // Dấu mũ / trăng / móc: '^' (â ê ô), '(' (ă), '+' (ơ ư), '-' (đ).
  static const _vowels = [
    ('a', '', 'aàáảãạ'), ('a', '^', 'âầấẩẫậ'), ('a', '(', 'ăằắẳẵặ'),
    ('e', '', 'eèéẻẽẹ'), ('e', '^', 'êềếểễệ'),
    ('i', '', 'iìíỉĩị'),
    ('o', '', 'oòóỏõọ'), ('o', '^', 'ôồốổỗộ'), ('o', '+', 'ơờớởỡợ'),
    ('u', '', 'uùúủũụ'), ('u', '+', 'ưừứửữự'),
    ('y', '', 'yỳýỷỹỵ'),
  ];
  static final Map<String, _Unit> _decomp = () {
    final m = <String, _Unit>{'đ': const _Unit('d', '-', '')};
    for (final (base, shape, chars) in _vowels) {
      for (var i = 0; i < chars.length; i++) {
        m[chars[i]] = _Unit(base, shape, _tones[i]);
      }
    }
    return m;
  }();
  // Dấu tổ hợp (văn bản dạng NFD): (true = thanh điệu | false = dấu mũ/móc, mã).
  static const _combining = {
    '̀': (true, '`'), '́': (true, "'"), '̉': (true, '?'), '̃': (true, '~'),
    '̣': (true, '.'), '̂': (false, '^'), '̆': (false, '('), '̛': (false, '+'),
  };
  static const _leet = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', r'$': 's'};
  static final _wordChar = RegExp(r'^[\p{L}\p{N}]$', unicode: true);
  static final _space = RegExp(r'\s');

  /// Tách văn bản thành các từ; mỗi từ là các "đơn vị chữ" (chữ gốc, dấu mũ, thanh) + vị trí gốc.
  static List<_Tok> _words(String text) {
    final out = <_Tok>[];
    _Tok? cur;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      final comb = _combining[ch];
      if (comb != null) {
        if (cur != null && cur.end == i) {
          final u = cur.u.last;
          cur.u[cur.u.length - 1] = comb.$1 ? _Unit(u.b, u.s, comb.$2) : _Unit(u.b, comb.$2, u.t);
          cur.end = i + 1;
        }
        continue;
      }
      var lower = ch.toLowerCase();
      if (lower.length != 1) lower = ch;
      _Unit? u = _decomp[lower];
      if (u == null) {
        final l = _leet[lower];
        if (l != null) {
          u = _Unit(l, '', '');
        } else if (_wordChar.hasMatch(lower)) {
          u = _Unit(lower, '', '');
        }
      }
      if (u == null) continue;
      if (cur == null || cur.end != i) {
        cur = _Tok([], i, i);
        out.add(cur);
      }
      cur.u.add(u);
      cur.end = i + 1;
    }
    return out;
  }

  /// Ghép các từ bị chèn ký tự phân cách: "f.u.c.k", "đ.ụ", "f u c k", "sh-it".
  static List<_Tok> _glue(List<_Tok> ws, String text) {
    final out = <_Tok>[];
    _Tok? prev;
    for (final w in ws) {
      if (prev != null && out.isNotEmpty) {
        final gap = text.substring(prev.end, w.start);
        final singles = prev.u.length == 1 && w.u.length == 1;
        if (gap.length <= 3 && (singles || !_space.hasMatch(gap))) {
          out.last.u.addAll(w.u);
          out.last.end = w.end;
          prev = w;
          continue;
        }
      }
      out.add(_Tok([...w.u], w.start, w.end));
      prev = w;
    }
    return out;
  }

  static List<String> _keys(_Tok t, bool strict) => [for (final u in t.u) strict ? u.b + u.s + u.t : u.b];

  /// Gộp ký tự lặp liên tiếp ("fuuuck" → "fuck").
  static String _collapse(List<String> ks) => [
        for (var i = 0; i < ks.length; i++)
          if (i == 0 || ks[i] != ks[i - 1]) ks[i],
      ].join('\u0001');

  static _Index _buildIndex(List<String> list, bool strict) {
    final idx = _Index(strict);
    for (final word in list) {
      final ws = _words(word);
      final toks = [
        for (final w in ws) _Key(_collapse(_keys(w, strict)), w.u.length),
      ];
      if (toks.isEmpty) continue;
      (idx.first[toks.first.c] ??= []).add(toks);
      if (toks.length > 1) {
        final all = [for (final w in ws) ..._keys(w, strict)];
        final c = _collapse(all);
        (idx.compact[c] ??= []).add([_Key(c, all.length)]);
      }
    }
    return idx;
  }

  static final _indexes = [_buildIndex(words, false), _buildIndex(strict, true)];
}

class _Unit {
  const _Unit(this.b, this.s, this.t);
  final String b;
  final String s;
  final String t;
}

class _Tok {
  _Tok(this.u, this.start, this.end);
  final List<_Unit> u;
  final int start;
  int end;
}

class _Key {
  const _Key(this.c, this.n);
  final String c;
  final int n;
}

class _Index {
  _Index(this.strict);
  final bool strict;
  final first = <String, List<List<_Key>>>{};
  final compact = <String, List<List<_Key>>>{};
}
