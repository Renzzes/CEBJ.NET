// FastFi devtools guard — wraps the vendored disable-devtool@0.3.9 (MIT,
// https://github.com/theajack/disable-devtool). Self-hosted under /lib so it
// works for captive-portal clients that have no internet (a CDN script would
// be blocked by nodogsplash for unauthenticated clients).
//
// Operator bypass: append ?ddtk=fastfi-admin to the page URL to skip the guard
// (the md5 below is md5("fastfi-admin"); the token is only a convenience gate
// to avoid locking the operator out — it is NOT real security since the hash
// is visible in this client-side file).
//
// Set window.FASTFI_DDT_MODE = 'admin' | 'portal' BEFORE loading this script:
//   admin  = full lockdown (right-click / text-select / copy blocked; paste
//            stays allowed so the operator can paste license keys / config).
//   portal = light (devtools-open detection + console clearing + devtools
//            shortcut blocking only; right-click / copy / select stay enabled
//            so paying customers can copy the GCash number / voucher code).
//
// detectors whitelist: DefineId(1), DateToString(3), FuncToString(4),
// Debugger(5), DebugLib(7). Excludes RegToString(0) + Size(2) (excluded by
// upstream default for false-positive reasons) AND Performance(6) — its
// big-data timing probe false-triggers on the heavy admin SPA / cheap client
// devices and would lock the operator or a paying customer out mid-flow.
(function () {
    if (typeof window.DisableDevtool !== 'function') return;
    var mode = (window.FASTFI_DDT_MODE || 'portal').toLowerCase();

    var common = {
        md5: '22ff11e2ead9380cd1929f03d7d90b48',   // md5("fastfi-admin")
        tkName: 'ddtk',
        url: './devtools-blocked.html',
        clearIntervalWhenDevOpenTrigger: false,
        clearLog: true,
        detectors: [1, 3, 4, 5, 7]
    };

    var cfg;
    if (mode === 'admin') {
        cfg = Object.assign({}, common, {
            interval: 200,
            disableMenu: true,
            disableSelect: true,
            disableCopy: true,
            disableCut: true,
            disablePaste: false   // operator may paste license keys / config
        });
    } else {
        // portal / light — preserve customer UX
        cfg = Object.assign({}, common, {
            interval: 1000,       // lighter on client devices
            disableMenu: false,
            disableSelect: false,
            disableCopy: false,
            disableCut: false,
            disablePaste: false
        });
    }

    try { window.DisableDevtool(cfg); } catch (e) {}
})();