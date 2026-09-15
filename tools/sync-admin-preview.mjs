import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const www = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "EXTRACTED-OPENWRT-FASTFI-V2.5.1",
  "rootfs",
  "www",
);

let html = readFileSync(join(www, "admin.html"), "utf8");
html = html.replace(/<title>.*?<\/title>/i, "<title>CEBJ.NET Admin</title>");
html = html.replace(
  /content="KonekSik-Fi WiFi Vendo administration dashboard[^"]*"/i,
  'content="CEBJ.NET WiFi Vendo administration dashboard — manage sessions, rates, vouchers, and network settings."',
);
html = html.replace(
  /<script>window\.FASTFI_DDT_MODE=['"]admin['"];?<\/script>\s*/i,
  "<!-- preview: anti-devtools disabled -->\n",
);
html = html.replace(/<script src="\.\/lib\/disable-devtool[^"]*"><\/script>\s*/gi, "");
html = html.replace(/<script src="\.\/lib\/devtool-guard[^"]*"><\/script>\s*/gi, "");
if (!html.includes("ui-preview.js")) {
  html = html.replace(
    /(<script src="\/?admin\.js[^"]*"><\/script>)/i,
    '<script src="./ui-preview.js?v=dev"></script>\n    $1',
  );
}
writeFileSync(join(www, "admin-preview.html"), html);
const out = readFileSync(join(www, "admin-preview.html"), "utf8");
console.log(
  "admin-preview synced:",
  out.includes("captivePortalLivePreview"),
  out.includes("Live Preview is in the column"),
  out.includes("portal-live-preview.css"),
);
