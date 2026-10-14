/*! KonekSik ESP Delete/Unbind lifecycle override (bootstrap-safe, tiny). */
(function () {
  function toast(msg, kind) {
    if (typeof showToast === "function") showToast(msg, kind || "info");
  }
  function refreshBoth() {
    if (typeof loadESPDevices === "function") loadESPDevices();
    if (typeof loadLicensePool === "function") loadLicensePool();
  }

  window.deleteESPDevice = function (espId, force, meta) {
    if (!espId) return;
    meta = meta || {};
    var lic = String(meta.license || "").trim();
    var bound = !!(lic && lic !== "—" && lic !== "-" && lic !== "null");

    function run(withForce) {
      var q =
        "/cgi-bin/api?action=delete_esp_device&slot_id=" +
        encodeURIComponent(espId) +
        (withForce ? "&force=1&confirm_unbind=1" : "");
      return fetch(q, { credentials: "include" })
        .then(function (r) {
          return r.json();
        })
        .then(function (d) {
          if (d.code === "REQUIRES_UNBIND" || d.requires_unbind) {
            var ok = confirm(
              "Unbind and Delete ESP32?\n\nMAC: " +
                (d.slot_mac || meta.mac || "—") +
                "\nLicense: " +
                (d.license_id || meta.license || "—") +
                "\n\nThis clears the live KSK binding and removes the Registered ESP row from the router database."
            );
            if (ok) return run(true);
            toast("Delete cancelled — Unbind required for bound devices", "warning");
            return null;
          }
          if (d.status !== "ok") {
            toast(d.message || d.code || "Delete failed", "error");
            return null;
          }
          toast(d.message || "Deleted", "success");
          refreshBoth();
          return d;
        });
    }

    if (force) return run(true);
    if (bound) {
      var okB = confirm(
        "Unbind and Delete ESP32?\n\nName: " +
          (meta.name || "ESP32") +
          "\nMAC: " +
          (meta.mac || "—") +
          "\nLicense: " +
          (meta.license || "—") +
          "\n\nRemoves this device from the router database. License stays as Unbound (signed .ksk kept)."
      );
      if (!okB) return;
      return run(true).catch(function (e) {
        toast(String(e), "error");
      });
    }
    var okU = confirm(
      "Delete ESP32?\n\nName: " +
        (meta.name || "ESP32") +
        "\nMAC: " +
        (meta.mac || "—") +
        "\n\nRemoves this row from the router database."
    );
    if (!okU) return;
    return run(false).catch(function (e) {
      toast(String(e), "error");
    });
  };

  window.removeESPDevice = function (espId) {
    return window.deleteESPDevice(espId, false, {});
  };

  window.unbindKskLicense = function (licenseId) {
    if (!licenseId) return;
    if (
      !confirm(
        "Unbind this ESP from " +
          licenseId +
          "?\n\nClears live_mac in the router DB. Signed .ksk is kept. Device stays in Registered until Delete."
      )
    )
      return;
    fetch(
      "/cgi-bin/api?action=esp_license_unbind&license_id=" + encodeURIComponent(licenseId),
      { credentials: "include" }
    )
      .then(function (r) {
        return r.json();
      })
      .then(function (d) {
        toast(d.message || (d.status === "ok" ? "Unbound" : "Failed"), d.status === "ok" ? "success" : "error");
        if (d.status === "ok") refreshBoth();
      })
      .catch(function (e) {
        toast(String(e), "error");
      });
  };
})();
