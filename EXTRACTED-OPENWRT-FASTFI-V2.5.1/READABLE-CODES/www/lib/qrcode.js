/* FastFi QR — minimal QR Code generator, ISO/IEC 18004.
 *
 * Scope is deliberately small: byte mode, error-correction level M, versions
 * 1-10. That covers a 12-char voucher code (which lands in version 1) with a
 * wide margin and keeps the file ~8 KB instead of pulling in a general-purpose
 * library. Level M tolerates ~15% damage, which is the right trade for a paper
 * ticket that gets folded and handled.
 *
 * ES5 only — no let/const, arrow functions, or template literals. The admin UI
 * is opened from legacy Android WebViews and Smart TV browsers (see the ES5
 * compatibility pass in v2.3.14), and this file is NOT run through terser
 * (fastfi-harden.py only minifies top-level www/*.js, never subdirectories).
 *
 * Public API:
 *   FastFiQR.make(text)       -> { size: n, modules: [[0|1,...],...] }
 *   FastFiQR.svg(text, opts)  -> SVG markup string (opts.quiet = quiet-zone modules)
 */
(function (global) {
'use strict';

/* ── GF(256) arithmetic, primitive polynomial 0x11D ───────────────────────── */

var GF_EXP = [], GF_LOG = [];
(function () {
    var x = 1, i;
    for (i = 0; i < 255; i++) {
        GF_EXP[i] = x;
        GF_LOG[x] = i;
        x <<= 1;
        if (x & 0x100) x ^= 0x11D;
    }
    for (i = 255; i < 512; i++) GF_EXP[i] = GF_EXP[i - 255];
})();

function gmul(a, b) {
    if (a === 0 || b === 0) return 0;
    return GF_EXP[GF_LOG[a] + GF_LOG[b]];
}

/* Reed-Solomon generator polynomial, highest degree first. */
function rsGenPoly(degree) {
    var poly = [1], d, i, next;
    for (d = 0; d < degree; d++) {
        next = [];
        for (i = 0; i <= poly.length; i++) next[i] = 0;
        for (i = 0; i < poly.length; i++) {
            next[i] ^= poly[i];                       /* multiply by x */
            next[i + 1] ^= gmul(poly[i], GF_EXP[d]);  /* multiply by alpha^d */
        }
        poly = next;
    }
    return poly;
}

function rsEncode(data, ecLen) {
    var gen = rsGenPoly(ecLen), res = [], i, j, factor;
    for (i = 0; i < ecLen; i++) res[i] = 0;
    for (i = 0; i < data.length; i++) {
        factor = data[i] ^ res[0];
        res.shift();
        res.push(0);
        for (j = 0; j < ecLen; j++) res[j] ^= gmul(gen[j + 1], factor);
    }
    return res;
}

/* ── Version tables (error-correction level M) ────────────────────────────── */

/* [ecCodewordsPerBlock, group1Blocks, group1DataCw, group2Blocks, group2DataCw] */
var EC_M = {
    1:  [10, 1, 16, 0, 0],
    2:  [16, 1, 28, 0, 0],
    3:  [26, 1, 44, 0, 0],
    4:  [18, 2, 32, 0, 0],
    5:  [24, 2, 43, 0, 0],
    6:  [16, 4, 27, 0, 0],
    7:  [18, 4, 31, 0, 0],
    8:  [22, 2, 38, 2, 39],
    9:  [22, 3, 36, 2, 37],
    10: [26, 4, 43, 1, 44]
};

/* Alignment-pattern centre coordinates per version. */
var ALIGN = {
    1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30],
    6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50]
};

function dataCodewords(ver) {
    var s = EC_M[ver];
    return s[1] * s[2] + s[3] * s[4];
}

function countBitsFor(ver) {
    return ver < 10 ? 8 : 16;
}

function chooseVersion(byteLen) {
    var v, need;
    for (v = 1; v <= 10; v++) {
        need = 4 + countBitsFor(v) + byteLen * 8;
        if (need <= dataCodewords(v) * 8) return v;
    }
    return -1;
}

/* ── Data encoding ────────────────────────────────────────────────────────── */

function utf8Bytes(text) {
    var out = [], i, c;
    for (i = 0; i < text.length; i++) {
        c = text.charCodeAt(i);
        if (c < 0x80) {
            out.push(c);
        } else if (c < 0x800) {
            out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
        } else {
            out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
        }
    }
    return out;
}

function pushBits(bits, value, len) {
    for (var i = len - 1; i >= 0; i--) bits.push((value >>> i) & 1);
}

function encodeData(bytes, ver) {
    var capacity = dataCodewords(ver) * 8;
    var bits = [], i, j, b, pad = [0xEC, 0x11], p = 0, cw = [];

    pushBits(bits, 4, 4);                                 /* byte mode */
    pushBits(bits, bytes.length, countBitsFor(ver));
    for (i = 0; i < bytes.length; i++) pushBits(bits, bytes[i], 8);

    pushBits(bits, 0, Math.min(4, capacity - bits.length));  /* terminator */
    while (bits.length % 8 !== 0) bits.push(0);
    while (bits.length < capacity) { pushBits(bits, pad[p], 8); p ^= 1; }

    for (i = 0; i < bits.length; i += 8) {
        b = 0;
        for (j = 0; j < 8; j++) b = (b << 1) | bits[i + j];
        cw.push(b);
    }
    return cw;
}

/* Split into blocks, add EC, then interleave both data and EC codewords. */
function interleave(dataCw, ver) {
    var spec = EC_M[ver], ecLen = spec[0];
    var counts = [], blocks = [], ecBlocks = [], out = [];
    var i, j, idx = 0, maxLen = 0;

    for (i = 0; i < spec[1]; i++) counts.push(spec[2]);
    for (i = 0; i < spec[3]; i++) counts.push(spec[4]);

    for (i = 0; i < counts.length; i++) {
        blocks.push(dataCw.slice(idx, idx + counts[i]));
        idx += counts[i];
        ecBlocks.push(rsEncode(blocks[i], ecLen));
        if (counts[i] > maxLen) maxLen = counts[i];
    }

    for (j = 0; j < maxLen; j++)
        for (i = 0; i < blocks.length; i++)
            if (j < blocks[i].length) out.push(blocks[i][j]);

    for (j = 0; j < ecLen; j++)
        for (i = 0; i < ecBlocks.length; i++)
            out.push(ecBlocks[i][j]);

    return out;
}

/* ── Matrix construction ──────────────────────────────────────────────────── */

function getBit(value, i) {
    return (value >>> i) & 1;
}

function newMatrix(ver, codewords) {
    var size = ver * 4 + 17;
    var m = [], fn = [], x, y, i, j;

    for (y = 0; y < size; y++) {
        m.push([]); fn.push([]);
        for (x = 0; x < size; x++) { m[y].push(0); fn[y].push(false); }
    }

    function setFn(px, py, dark) {
        if (px < 0 || py < 0 || px >= size || py >= size) return;
        m[py][px] = dark ? 1 : 0;
        fn[py][px] = true;
    }

    /* Timing patterns run the full width/height first; the finder patterns are
     * drawn afterwards and deliberately overwrite the ends of them. Doing this
     * in the other order corrupts the finders and nothing decodes. */
    for (i = 0; i < size; i++) {
        setFn(6, i, i % 2 === 0);
        setFn(i, 6, i % 2 === 0);
    }

    /* Finder patterns plus their separators: dark at Chebyshev distance 0,1,3. */
    function finder(cx, cy) {
        var dx, dy, d;
        for (dy = -4; dy <= 4; dy++)
            for (dx = -4; dx <= 4; dx++) {
                d = Math.max(Math.abs(dx), Math.abs(dy));
                setFn(cx + dx, cy + dy, d !== 2 && d !== 4);
            }
    }
    finder(3, 3);
    finder(size - 4, 3);
    finder(3, size - 4);

    /* Alignment patterns, skipping the three finder corners */
    var ali = ALIGN[ver], last = ali.length - 1, dx, dy;
    for (i = 0; i <= last; i++)
        for (j = 0; j <= last; j++) {
            if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) continue;
            for (dy = -2; dy <= 2; dy++)
                for (dx = -2; dx <= 2; dx++)
                    setFn(ali[j] + dx, ali[i] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
        }

    /* Version information (versions 7+) */
    if (ver >= 7) {
        var rem = ver;
        for (i = 0; i < 12; i++) rem = (rem << 1) ^ (((rem >>> 11) & 1) * 0x1F25);
        var vbits = (ver << 12) | rem;
        for (i = 0; i < 18; i++) {
            var bit = getBit(vbits, i), a = size - 11 + i % 3, b = Math.floor(i / 3);
            setFn(a, b, bit);
            setFn(b, a, bit);
        }
    }

    /* Reserve the format-info modules so the codeword walk skips them. The real
     * bits are written later, once the mask is chosen. Note (6,8) and (8,6)
     * belong to the timing patterns and are deliberately not touched here. */
    function formatCells() {
        var cells = [];
        for (var k = 0; k <= 5; k++) cells.push([8, k, k]);
        cells.push([8, 7, 6]);
        cells.push([8, 8, 7]);
        cells.push([7, 8, 8]);
        for (k = 9; k < 15; k++) cells.push([14 - k, 8, k]);
        for (k = 0; k < 8; k++) cells.push([size - 1 - k, 8, k]);
        for (k = 8; k < 15; k++) cells.push([8, size - 15 + k, k]);
        return cells;
    }
    var fcells = formatCells();
    for (i = 0; i < fcells.length; i++) setFn(fcells[i][0], fcells[i][1], false);

    /* Always-dark module — set after the format reservation, which overlaps it. */
    setFn(8, size - 8, true);

    /* Codewords, zigzagging upward/downward in column pairs from the right.
     * Column 6 is the vertical timing pattern and is stepped over. */
    var bitIdx = 0, right, vert, k2, upward;
    for (right = size - 1; right >= 1; right -= 2) {
        if (right === 6) right = 5;
        for (vert = 0; vert < size; vert++) {
            for (k2 = 0; k2 < 2; k2++) {
                x = right - k2;
                upward = ((right + 1) & 2) === 0;
                y = upward ? size - 1 - vert : vert;
                if (!fn[y][x] && bitIdx < codewords.length * 8) {
                    m[y][x] = getBit(codewords[bitIdx >>> 3], 7 - (bitIdx & 7));
                    bitIdx++;
                }
            }
        }
    }

    return { size: size, modules: m, isFunction: fn, formatCells: fcells };
}

function maskAt(mask, x, y) {
    switch (mask) {
        case 0: return (x + y) % 2 === 0;
        case 1: return y % 2 === 0;
        case 2: return x % 3 === 0;
        case 3: return (x + y) % 3 === 0;
        case 4: return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
        case 5: return (x * y) % 2 + (x * y) % 3 === 0;
        case 6: return ((x * y) % 2 + (x * y) % 3) % 2 === 0;
        case 7: return ((x + y) % 2 + (x * y) % 3) % 2 === 0;
    }
    return false;
}

/* Format info: 5 data bits (EC level M = 00, then the 3 mask bits) with a
 * 10-bit BCH remainder, the whole 15 bits XORed with 0x5412. */
function formatBits(mask) {
    var data = (0 << 3) | mask, rem = data, i;
    for (i = 0; i < 10; i++) rem = (rem << 1) ^ (((rem >>> 9) & 1) * 0x537);
    return ((data << 10) | rem) ^ 0x5412;
}

function penalty(m, size) {
    var score = 0, x, y, i, run, c, dark = 0;

    /* Rule 1 — runs of five or more same-coloured modules */
    for (y = 0; y < size; y++) {
        run = 1;
        for (x = 1; x < size; x++) {
            if (m[y][x] === m[y][x - 1]) run++;
            else { if (run >= 5) score += 3 + (run - 5); run = 1; }
        }
        if (run >= 5) score += 3 + (run - 5);
    }
    for (x = 0; x < size; x++) {
        run = 1;
        for (y = 1; y < size; y++) {
            if (m[y][x] === m[y - 1][x]) run++;
            else { if (run >= 5) score += 3 + (run - 5); run = 1; }
        }
        if (run >= 5) score += 3 + (run - 5);
    }

    /* Rule 2 — 2x2 blocks of one colour */
    for (y = 0; y < size - 1; y++)
        for (x = 0; x < size - 1; x++) {
            c = m[y][x];
            if (c === m[y][x + 1] && c === m[y + 1][x] && c === m[y + 1][x + 1]) score += 3;
        }

    /* Rule 3 — finder-like 1:1:3:1:1 pattern with four light modules beside it */
    var pat1 = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0];
    var pat2 = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1];
    function countPat(get, len, pat) {
        var n = 0, s, k, ok;
        for (s = 0; s + pat.length <= len; s++) {
            ok = true;
            for (k = 0; k < pat.length; k++) if (get(s + k) !== pat[k]) { ok = false; break; }
            if (ok) n++;
        }
        return n;
    }
    function rowGetter(yy) { return function (i2) { return m[yy][i2]; }; }
    function colGetter(xx) { return function (i2) { return m[i2][xx]; }; }
    for (y = 0; y < size; y++)
        score += 40 * (countPat(rowGetter(y), size, pat1) + countPat(rowGetter(y), size, pat2));
    for (x = 0; x < size; x++)
        score += 40 * (countPat(colGetter(x), size, pat1) + countPat(colGetter(x), size, pat2));

    /* Rule 4 — deviation of the dark-module ratio from 50% */
    for (y = 0; y < size; y++) for (x = 0; x < size; x++) if (m[y][x]) dark++;
    score += Math.floor(Math.abs(dark * 100 / (size * size) - 50) / 5) * 10;

    return score;
}

function render(base, mask) {
    var size = base.size, m = [], x, y, i, cell, bits;

    for (y = 0; y < size; y++) {
        m.push([]);
        for (x = 0; x < size; x++) {
            m[y].push(
                (!base.isFunction[y][x] && maskAt(mask, x, y))
                    ? (base.modules[y][x] ^ 1)
                    : base.modules[y][x]
            );
        }
    }

    bits = formatBits(mask);
    for (i = 0; i < base.formatCells.length; i++) {
        cell = base.formatCells[i];
        m[cell[1]][cell[0]] = getBit(bits, cell[2]);
    }
    m[size - 8][8] = 1;  /* always-dark module */

    return m;
}

/* ── Public API ───────────────────────────────────────────────────────────── */

function make(text) {
    var bytes = utf8Bytes(String(text));
    var ver = chooseVersion(bytes.length);
    if (ver < 0) throw new Error('FastFiQR: text too long (max version 10, level M)');

    var base = newMatrix(ver, interleave(encodeData(bytes, ver), ver));
    var best = null, bestScore = Infinity, mask, m, s;

    for (mask = 0; mask < 8; mask++) {
        m = render(base, mask);
        s = penalty(m, base.size);
        if (s < bestScore) { bestScore = s; best = m; }
    }

    return { size: base.size, version: ver, modules: best };
}

/* Emits a single <path> rather than one <rect> per module: shorter markup, and
 * it prints as vector art at whatever resolution the printer runs at. */
function svg(text, opts) {
    opts = opts || {};
    var quiet = (opts.quiet === undefined) ? 4 : opts.quiet;
    var qr = make(text);
    var dim = qr.size + quiet * 2;
    var d = '', x, y;

    for (y = 0; y < qr.size; y++)
        for (x = 0; x < qr.size; x++)
            if (qr.modules[y][x]) d += 'M' + (x + quiet) + ' ' + (y + quiet) + 'h1v1h-1z';

    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + dim + ' ' + dim +
        '" shape-rendering="crispEdges" preserveAspectRatio="xMidYMid meet">' +
        '<rect width="' + dim + '" height="' + dim + '" fill="#ffffff"/>' +
        '<path d="' + d + '" fill="#000000"/></svg>';
}

global.FastFiQR = { make: make, svg: svg };

})(typeof window !== 'undefined' ? window : this);
