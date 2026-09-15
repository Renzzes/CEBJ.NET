/* FastFi ES5 polyfills for legacy Android WebViews (Android 5-9 / Chrome 37-66).
 *
 * The captive portal (bootstrap.js + index.html inline scripts) is written in
 * ES5 so old WebViews can PARSE it, but a few runtime APIs are still missing on
 * those engines. This file supplies them. Each polyfill only installs when the
 * native implementation is absent, so modern browsers are completely
 * unaffected. Load this BEFORE bootstrap.js.
 *
 * Covered: fetch (XHR-based), URLSearchParams, Object.values,
 * String.prototype.padStart, Promise.prototype.finally, Array.prototype.includes,
 * Element.prototype.closest. Promise itself exists on Android 4.4+, so no
 * Promise polyfill is needed.
 */
(function () {
  'use strict';

  // ---- Promise.prototype.finally (Chrome <63 / Android <8) ----
  if (typeof Promise !== 'undefined' && !Promise.prototype.finally) {
    Promise.prototype.finally = function (onFinally) {
      var C = this.constructor;
      return this.then(
        function (value) {
          return C.resolve(onFinally()).then(function () { return value; });
        },
        function (reason) {
          return C.resolve(onFinally()).then(function () { throw reason; });
        }
      );
    };
  }

  // ---- Array.prototype.includes (Chrome <47 / Android <6) ----
  if (!Array.prototype.includes) {
    Array.prototype.includes = function (searchElement, fromIndex) {
      var O = Object(this);
      var len = O.length >>> 0;
      if (len === 0) return false;
      var n = fromIndex | 0;
      var k = Math.max(n >= 0 ? n : len + n, 0);
      while (k < len) {
        if (O[k] === searchElement) return true;
        k++;
      }
      return false;
    };
  }

  // ---- Object.values (Chrome <54 / Android <7) ----
  if (typeof Object.values !== 'function') {
    Object.values = function (obj) {
      var out = [];
      for (var k in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, k)) out.push(obj[k]);
      }
      return out;
    };
  }

  // ---- String.prototype.padStart (Chrome <57 / Android <8) ----
  if (typeof String.prototype.padStart !== 'function') {
    String.prototype.padStart = function (targetLength, padString) {
      var str = String(this);
      var len = targetLength >> 0;
      var pad = typeof padString === 'undefined' ? ' ' : String(padString);
      if (str.length >= len || pad.length === 0) return str;
      var needed = len - str.length;
      var fill = '';
      while (fill.length < needed) fill += pad;
      return fill.slice(0, needed) + str;
    };
  }

  // ---- Element.prototype.closest (Chrome <41 / Android <5) ----
  if (typeof window.Element !== 'undefined' && !Element.prototype.closest) {
    Element.prototype.closest = function (selector) {
      var el = this;
      while (el && el.nodeType === 1) {
        if (el.matches(selector)) return el;
        el = el.parentElement || el.parentNode;
      }
      return null;
    };
  }

  // ---- URLSearchParams (Chrome <49 / Android <6) ----
  if (typeof window.URLSearchParams === 'undefined') {
    function URLSearchParams(init) {
      this._pairs = [];
      if (init) {
        if (typeof init === 'string') {
          var parts = init.replace(/^[?#]/, '').split('&');
          for (var i = 0; i < parts.length; i++) {
            if (parts[i] === '') continue;
            var eq = parts[i].indexOf('=');
            var name = eq >= 0 ? parts[i].slice(0, eq) : parts[i];
            var value = eq >= 0 ? parts[i].slice(eq + 1) : '';
            this.append(decodeURIComponent(name.replace(/\+/g, ' ')),
                        decodeURIComponent(value.replace(/\+/g, ' ')));
          }
        } else if (init instanceof URLSearchParams) {
          for (var j = 0; j < init._pairs.length; j++) {
            this._pairs.push([init._pairs[j][0], init._pairs[j][1]]);
          }
        } else if (typeof init === 'object') {
          for (var k in init) {
            if (Object.prototype.hasOwnProperty.call(init, k)) this.append(k, init[k]);
          }
        }
      }
    }
    URLSearchParams.prototype.append = function (name, value) {
      this._pairs.push([String(name), String(value)]);
    };
    URLSearchParams.prototype.get = function (name) {
      for (var i = 0; i < this._pairs.length; i++) {
        if (this._pairs[i][0] === name) return this._pairs[i][1];
      }
      return null;
    };
    URLSearchParams.prototype.getAll = function (name) {
      var out = [];
      for (var i = 0; i < this._pairs.length; i++) {
        if (this._pairs[i][0] === name) out.push(this._pairs[i][1]);
      }
      return out;
    };
    URLSearchParams.prototype.has = function (name) {
      return this.get(name) !== null;
    };
    URLSearchParams.prototype.set = function (name, value) {
      var found = false;
      for (var i = 0; i < this._pairs.length; i++) {
        if (this._pairs[i][0] === name) {
          if (!found) { this._pairs[i][1] = String(value); found = true; }
          else { this._pairs.splice(i, 1); i--; }
        }
      }
      if (!found) this.append(name, value);
    };
    URLSearchParams.prototype.delete = function (name) {
      for (var i = 0; i < this._pairs.length; i++) {
        if (this._pairs[i][0] === name) { this._pairs.splice(i, 1); i--; }
      }
    };
    URLSearchParams.prototype.toString = function () {
      var out = [];
      for (var i = 0; i < this._pairs.length; i++) {
        out.push(encodeURIComponent(this._pairs[i][0]) + '=' +
                 encodeURIComponent(this._pairs[i][1]));
      }
      return out.join('&');
    };
    window.URLSearchParams = URLSearchParams;
  }

  // ---- fetch (Chrome <42 / Android <5) ----
  // The portal only issues GET requests with { cache: "no-store" } and reads
  // res.json() / res.ok / res.status. XHR covers that; the extra options
  // (method/headers/body) are handled anyway for completeness.
  if (typeof window.fetch !== 'function') {
    window.fetch = function (url, options) {
      options = options || {};
      return new Promise(function (resolve, reject) {
        var xhr = new XMLHttpRequest();
        var method = (options.method || 'GET').toUpperCase();
        xhr.open(method, url, true);
        var headers = options.headers || {};
        for (var h in headers) {
          if (Object.prototype.hasOwnProperty.call(headers, h)) {
            xhr.setRequestHeader(h, headers[h]);
          }
        }
        xhr.onload = function () {
          var response = {
            ok: xhr.status >= 200 && xhr.status < 300,
            status: xhr.status,
            statusText: xhr.statusText,
            url: url,
            headers: { get: function (name) { return xhr.getResponseHeader(name); } },
            text: function () { return Promise.resolve(xhr.responseText); },
            json: function () {
              return new Promise(function (res, rej) {
                try { res(JSON.parse(xhr.responseText)); }
                catch (e) { rej(e); }
              });
            }
          };
          resolve(response);
        };
        xhr.onerror = function () { reject(new Error('Network request failed')); };
        xhr.ontimeout = function () { reject(new Error('Network request timed out')); };
        var body = options.body;
        if (body && typeof body === 'object' && !(body instanceof FormData) &&
            !(body instanceof Blob) && typeof body !== 'string') {
          body = JSON.stringify(body);
        }
        xhr.send(body || null);
      });
    };
  }
})();
