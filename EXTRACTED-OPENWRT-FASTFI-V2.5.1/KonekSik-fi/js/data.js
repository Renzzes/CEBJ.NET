/**
 * KonekSik-fi Admin Console — centralized mock data (UI prototype).
 *
 * Production: ESP32-S3-ETH serves this UI and replaces AppData with GET/POST /api/*.
 * MikroTik is reached only by the ESP32 (RouterOS API) — never from the browser.
 * See docs/ARCHITECTURE.md and docs/API.md.
 */
window.AppData = {
  auth: {
    username: "admin",
    password: "admin",
    displayName: "Admin",
    role: "Owner",
  },

  system: {
    name: "KonekSik-fi",
    location: "Main Branch — Poblacion",
    timezone: "Asia/Manila",
    language: "English",
    currency: "PHP",
    version: "v1.4.2",
    latestVersion: "v1.4.3",
    deviceId: "KSK-001",
  },

  status: {
    internet: "online",
    mikrotik: "online",
    controller: "online",
    accessPoint: "online",
  },

  kpis: {
    connectedUsersDelta: 5,
    weekSales: 7860,
    monthSales: 28450,
    totalTransactions: 412,
  },

  networkHealth: {
    latencyMs: 18,
    packetLoss: 0,
    downloadMbps: 86.4,
    uploadMbps: 12.7,
    connectionType: "PPPoE",
    isp: "PLDT",
    wanIp: "124.107.•••.•••",
    uptime: "3d 14h",
    sparkline: [62, 70, 68, 74, 81, 79, 86, 84, 88, 86, 90, 86],
  },

  mikrotik: {
    model: "hEX Refresh",
    routeros: "v7.x",
    cpu: 18,
    memory: 42,
    storage: 31,
    temperature: 48,
    uptime: "14d 7h",
    connection: "connected",
    api: "connected",
    storageTotalMb: 128,
    storageLive: false,
    storageSlices: [
      { label: "RouterOS", mb: 29.6, color: "#2D8653" },
      { label: "Admin & portal", mb: 6.0, color: "#7F2D37" },
      { label: "Backups", mb: 2.8, color: "#B37D26" },
      { label: "Other", mb: 1.3, color: "#94A3B8" },
    ],
  },

  coinRates: [
    { id: "rate-1", coin: 1, minutes: 5, label: "5 Minutes", speed: "Basic", status: "active" },
    { id: "rate-2", coin: 5, minutes: 30, label: "30 Minutes", speed: "Standard", status: "active" },
    { id: "rate-3", coin: 10, minutes: 60, label: "1 Hour", speed: "Standard", status: "active" },
    { id: "rate-4", coin: 20, minutes: 180, label: "3 Hours", speed: "Premium", status: "active" },
    { id: "rate-5", coin: 50, minutes: 720, label: "12 Hours", speed: "Premium", status: "active" },
    { id: "rate-6", coin: 15, minutes: 90, label: "90 Minutes", speed: "Custom", download: 15, upload: 8, status: "active" },
  ],

  plans: [
    { id: "plan-1", name: "Plan 50", price: 600, download: 50, upload: 20, duration: "30 days", status: "active" },
    { id: "plan-2", name: "Plan 100", price: 1000, download: 100, upload: 40, duration: "30 days", status: "active" },
    { id: "plan-3", name: "Plan 200", price: 2000, download: 200, upload: 80, duration: "30 days", status: "active" },
  ],

  /* Households / locations that availed a monthly plan, deployed on a specific AP */
  planClients: [
    { id: "cli-1", houseName: "Basera Family", houseNumber: "12", contact: "0917 552 1840", facebook: "basera.family", planId: "plan-1", apId: "AP-01", status: "active", availedOn: "Aug 01, 2026" },
    { id: "cli-2", houseName: "Apurado Family", houseNumber: "18", contact: "0995 104 7721", facebook: "apurado.family", planId: "plan-1", apId: "AP-02", status: "active", availedOn: "Aug 04, 2026" },
    { id: "cli-3", houseName: "Functional Hall", houseNumber: "Hall-A", contact: "0918 220 4491", facebook: "", planId: "plan-1", apId: "AP-03", status: "active", availedOn: "Aug 10, 2026" },
  ],

  sessions: [
    { id: "SES-10421", device: "Samsung Galaxy", type: "Android", ip: "192.168.10.21", mac: "A4:6C:F1:88:12:3A", plan: "₱10", duration: "1 Hour", start: "14:22", expires: "15:22", remaining: "42 min", remainingMin: 42, status: "active", download: "1.2 GB", upload: "340 MB", startedAt: "Aug 24, 2026 14:22" },
    { id: "SES-10418", device: "iPhone 13", type: "iPhone", ip: "192.168.10.34", mac: "F2:11:90:44:AB:09", plan: "₱20", duration: "3 Hours", start: "13:05", expires: "16:05", remaining: "2 hr", remainingMin: 120, status: "active", download: "2.8 GB", upload: "510 MB", startedAt: "Aug 24, 2026 13:05" },
    { id: "SES-10402", device: "Lenovo IdeaPad", type: "Laptop", ip: "192.168.10.12", mac: "00:1A:2B:3C:4D:5E", plan: "₱5", duration: "30 Minutes", start: "13:40", expires: "14:10", remaining: "0 min", remainingMin: 0, status: "expired", download: "420 MB", upload: "88 MB", startedAt: "Aug 24, 2026 13:40" },
    { id: "SES-10419", device: "Redmi Note", type: "Android", ip: "192.168.10.45", mac: "C8:2A:10:77:21:F4", plan: "₱10", duration: "1 Hour", start: "14:10", expires: "15:10", remaining: "1 hr", remainingMin: 48, status: "active", download: "890 MB", upload: "210 MB", startedAt: "Aug 24, 2026 14:10" },
    { id: "SES-10388", device: "OPPO A78", type: "Android", ip: "192.168.10.18", mac: "B1:90:33:12:88:01", plan: "₱1", duration: "5 Minutes", start: "12:01", expires: "12:06", remaining: "0 min", remainingMin: 0, status: "expired", download: "64 MB", upload: "12 MB", startedAt: "Aug 24, 2026 12:01" },
    { id: "SES-10422", device: "MacBook Air", type: "Laptop", ip: "192.168.10.52", mac: "88:66:AA:11:22:33", plan: "₱50", duration: "12 Hours", start: "08:12", expires: "20:12", remaining: "5 hr", remainingMin: 310, status: "active", download: "6.4 GB", upload: "1.1 GB", startedAt: "Aug 24, 2026 08:12" },
    { id: "SES-10411", device: "iPad 9", type: "Tablet", ip: "192.168.10.61", mac: "DE:AD:BE:EF:10:20", plan: "₱20", duration: "3 Hours", start: "12:30", expires: "15:30", remaining: "1 hr", remainingMin: 68, status: "active", download: "1.9 GB", upload: "240 MB", startedAt: "Aug 24, 2026 12:30" },
    { id: "SES-10395", device: "Windows PC", type: "Laptop", ip: "192.168.10.08", mac: "11:22:33:44:55:66", plan: "₱10", duration: "1 Hour", start: "11:00", expires: "12:00", remaining: "0 min", remainingMin: 0, status: "expired", download: "1.1 GB", upload: "90 MB", startedAt: "Aug 24, 2026 11:00" },
  ],

  devices: [
    { id: "dev-1", hostname: "Galaxy-A54", type: "Android", ip: "192.168.10.21", mac: "A4:6C:F1:88:12:3A", connection: "Wi-Fi", session: "₱10 / 1 Hour", usage: "1.54 GB", status: "online", auth: "authenticated", blocked: false, firstSeen: "Aug 12, 2026", lastSeen: "Now", plan: "₱10 / 1 Hour", start: "14:22", expires: "15:22", remaining: "42 min", download: "1.2 GB", upload: "340 MB", speed: "8.4 Mbps", isolation: "Enabled", planId: "plan-1", apId: "AP-01", clientId: "cli-1" },
    { id: "dev-2", hostname: "iPhone-13", type: "iPhone", ip: "192.168.10.34", mac: "F2:11:90:44:AB:09", connection: "Wi-Fi", session: "₱20 / 3 Hours", usage: "3.31 GB", status: "online", auth: "authenticated", blocked: false, firstSeen: "Jul 03, 2026", lastSeen: "Now", plan: "₱20 / 3 Hours", start: "13:05", expires: "16:05", remaining: "2 hr", download: "2.8 GB", upload: "510 MB", speed: "12.1 Mbps", isolation: "Enabled", planId: "plan-1", apId: "AP-01", clientId: "cli-1" },
    { id: "dev-3", hostname: "IdeaPad-3", type: "Laptop", ip: "192.168.10.12", mac: "00:1A:2B:3C:4D:5E", connection: "Wi-Fi", session: "—", usage: "508 MB", status: "offline", auth: "authenticated", blocked: false, firstSeen: "Aug 01, 2026", lastSeen: "14:10", plan: "₱5 / 30 Minutes", start: "13:40", expires: "14:10", remaining: "Expired", download: "420 MB", upload: "88 MB", speed: "0 Mbps", isolation: "Enabled", planId: "plan-1", apId: "AP-01", clientId: "cli-1" },
    { id: "dev-4", hostname: "Redmi-Note-12", type: "Android", ip: "192.168.10.45", mac: "C8:2A:10:77:21:F4", connection: "Wi-Fi", session: "₱10 / 1 Hour", usage: "1.10 GB", status: "online", auth: "authenticated", blocked: false, firstSeen: "Aug 18, 2026", lastSeen: "Now", plan: "₱10 / 1 Hour", start: "14:10", expires: "15:10", remaining: "48 min", download: "890 MB", upload: "210 MB", speed: "6.2 Mbps", isolation: "Enabled", planId: "plan-1", apId: "AP-01", clientId: "cli-1" },
    { id: "dev-5", hostname: "android-guest", type: "Android", ip: "192.168.10.88", mac: "AA:BB:CC:11:22:33", connection: "Wi-Fi", session: "Waiting", usage: "12 MB", status: "online", auth: "unauthenticated", blocked: false, firstSeen: "Aug 24, 2026", lastSeen: "Now", plan: "—", start: "—", expires: "—", remaining: "—", download: "8 MB", upload: "4 MB", speed: "0.4 Mbps", isolation: "Enabled", planId: "plan-1", apId: "AP-02", clientId: "cli-2" },
    { id: "dev-6", hostname: "MacBook-Air", type: "Laptop", ip: "192.168.10.52", mac: "88:66:AA:11:22:33", connection: "Wi-Fi", session: "₱50 / 12 Hours", usage: "7.50 GB", status: "online", auth: "authenticated", blocked: false, firstSeen: "Jun 22, 2026", lastSeen: "Now", plan: "₱50 / 12 Hours", start: "08:12", expires: "20:12", remaining: "5 hr", download: "6.4 GB", upload: "1.1 GB", speed: "18.6 Mbps", isolation: "Enabled", planId: "plan-1", apId: "AP-02", clientId: "cli-2" },
    { id: "dev-7", hostname: "unknown-device", type: "Android", ip: "192.168.10.91", mac: "12:34:56:78:9A:BC", connection: "Wi-Fi", session: "Blocked", usage: "0 MB", status: "offline", auth: "unauthenticated", blocked: true, firstSeen: "Aug 20, 2026", lastSeen: "Aug 21, 2026 09:14", plan: "—", start: "—", expires: "—", remaining: "—", download: "0 MB", upload: "0 MB", speed: "0 Mbps", isolation: "Enabled", planId: "plan-1", apId: "AP-03", clientId: "cli-3" },
    { id: "dev-8", hostname: "iPad-9", type: "Tablet", ip: "192.168.10.61", mac: "DE:AD:BE:EF:10:20", connection: "Wi-Fi", session: "₱20 / 3 Hours", usage: "2.14 GB", status: "online", auth: "authenticated", blocked: false, firstSeen: "Aug 09, 2026", lastSeen: "Now", plan: "₱20 / 3 Hours", start: "12:30", expires: "15:30", remaining: "1 hr", download: "1.9 GB", upload: "240 MB", speed: "9.8 Mbps", isolation: "Enabled", planId: "plan-1", apId: "AP-02", clientId: "cli-2" },
  ],

  blockedDevices: [
    { id: "blk-1", device: "Android", hostname: "unknown-device", mac: "12:34:56:78:9A:BC", date: "Aug 21, 2026 09:14", reason: "Manual block", status: "blocked" },
    { id: "blk-2", device: "Laptop", hostname: "WIN-GUEST", mac: "4C:ED:FB:90:11:02", date: "Aug 18, 2026 16:40", reason: "Abuse / excessive scanning", status: "blocked" },
    { id: "blk-3", device: "Android", hostname: "Tecno-Spark", mac: "90:AB:CD:12:34:56", date: "Aug 14, 2026 11:02", reason: "Repeated unpaid reconnects", status: "blocked" },
    { id: "blk-4", device: "iPhone", hostname: "iPhone-SE", mac: "F0:18:98:22:10:44", date: "Aug 10, 2026 19:33", reason: "Manual block", status: "blocked" },
  ],

  sales: [
    { id: "TXN-00124", datetime: "Aug 24, 2026 14:42", amount: 10, type: "Coin", plan: "1 Hour", duration: "1 Hour", status: "completed", day: "today" },
    { id: "TXN-00123", datetime: "Aug 24, 2026 14:21", amount: 5, type: "Coin", plan: "30 Minutes", duration: "30 Minutes", status: "completed", day: "today" },
    { id: "TXN-00122", datetime: "Aug 24, 2026 13:08", amount: 20, type: "Coin", plan: "3 Hours", duration: "3 Hours", status: "completed", day: "today" },
    { id: "TXN-00121", datetime: "Aug 24, 2026 12:55", amount: 10, type: "Voucher", plan: "1 Hour", duration: "1 Hour", status: "completed", day: "today" },
    { id: "TXN-00120", datetime: "Aug 24, 2026 11:16", amount: 1, type: "Coin", plan: "5 Minutes", duration: "5 Minutes", status: "completed", day: "today" },
    { id: "TXN-00119", datetime: "Aug 24, 2026 10:02", amount: 50, type: "Coin", plan: "12 Hours", duration: "12 Hours", status: "completed", day: "today" },
    { id: "TXN-00112", datetime: "Aug 23, 2026 18:40", amount: 10, type: "Coin", plan: "1 Hour", duration: "1 Hour", status: "completed", day: "yesterday" },
    { id: "TXN-00111", datetime: "Aug 23, 2026 16:12", amount: 20, type: "Voucher", plan: "3 Hours", duration: "3 Hours", status: "completed", day: "yesterday" },
    { id: "TXN-00104", datetime: "Aug 22, 2026 15:33", amount: 5, type: "Coin", plan: "30 Minutes", duration: "30 Minutes", status: "completed", day: "week" },
    { id: "TXN-00098", datetime: "Aug 20, 2026 09:18", amount: 10, type: "Coin", plan: "1 Hour", duration: "1 Hour", status: "failed", day: "week" },
    { id: "TXN-00097", datetime: "Aug 20, 2026 08:44", amount: 5, type: "Coin", plan: "30 Minutes", duration: "30 Minutes", status: "completed", day: "week" },
    { id: "TXN-00096", datetime: "Aug 19, 2026 21:10", amount: 20, type: "Coin", plan: "3 Hours", duration: "3 Hours", status: "completed", day: "week" },
    { id: "TXN-00095", datetime: "Aug 19, 2026 16:02", amount: 10, type: "Voucher", plan: "1 Hour", duration: "1 Hour", status: "completed", day: "week" },
    { id: "TXN-00094", datetime: "Aug 18, 2026 13:27", amount: 1, type: "Coin", plan: "5 Minutes", duration: "5 Minutes", status: "completed", day: "week" },
    { id: "TXN-00093", datetime: "Aug 18, 2026 11:08", amount: 50, type: "Coin", plan: "12 Hours", duration: "12 Hours", status: "completed", day: "week" },
    { id: "TXN-00081", datetime: "Aug 12, 2026 14:09", amount: 50, type: "Voucher", plan: "12 Hours", duration: "12 Hours", status: "completed", day: "month" },
    { id: "TXN-00080", datetime: "Aug 11, 2026 18:22", amount: 10, type: "Coin", plan: "1 Hour", duration: "1 Hour", status: "completed", day: "month" },
    { id: "TXN-00079", datetime: "Aug 10, 2026 09:41", amount: 20, type: "Voucher", plan: "3 Hours", duration: "3 Hours", status: "completed", day: "month" },
    { id: "TXN-00078", datetime: "Aug 09, 2026 20:15", amount: 5, type: "Coin", plan: "30 Minutes", duration: "30 Minutes", status: "completed", day: "month" },
    { id: "TXN-00077", datetime: "Aug 08, 2026 15:03", amount: 10, type: "Coin", plan: "1 Hour", duration: "1 Hour", status: "completed", day: "month" },
    { id: "TXN-00076", datetime: "Aug 07, 2026 12:48", amount: 20, type: "Coin", plan: "3 Hours", duration: "3 Hours", status: "completed", day: "month" },
    { id: "TXN-00075", datetime: "Aug 06, 2026 17:29", amount: 1, type: "Coin", plan: "5 Minutes", duration: "5 Minutes", status: "failed", day: "month" },
    { id: "TXN-00064", datetime: "Aug 04, 2026 19:51", amount: 20, type: "Coin", plan: "3 Hours", duration: "3 Hours", status: "completed", day: "month" },
    { id: "TXN-00063", datetime: "Aug 03, 2026 10:12", amount: 10, type: "Voucher", plan: "1 Hour", duration: "1 Hour", status: "completed", day: "month" },
    { id: "TXN-00062", datetime: "Aug 02, 2026 14:36", amount: 50, type: "Coin", plan: "12 Hours", duration: "12 Hours", status: "completed", day: "month" },
    { id: "TXN-00061", datetime: "Aug 01, 2026 08:05", amount: 5, type: "Coin", plan: "30 Minutes", duration: "30 Minutes", status: "completed", day: "month" },
  ],

  salesTrend: [980, 1120, 860, 1340, 1210, 1480, 1240],

  vouchers: [
    { code: "KSK-8F21A", plan: "1 Hour", duration: "1 Hour", speed: "Standard", created: "Aug 24, 2026", used: "—", status: "available" },
    { code: "KSK-91BC2", plan: "1 Hour", duration: "1 Hour", speed: "Standard", created: "Aug 24, 2026", used: "Aug 24, 2026 14:21", status: "used" },
    { code: "KSK-33DA0", plan: "3 Hours", duration: "3 Hours", speed: "Premium", created: "Aug 23, 2026", used: "Aug 23, 2026 16:12", status: "active" },
    { code: "KSK-77E11", plan: "30 Minutes", duration: "30 Minutes", speed: "Basic", created: "Aug 22, 2026", used: "—", status: "expired" },
    { code: "KSK-AA902", plan: "12 Hours", duration: "12 Hours", speed: "Premium", created: "Aug 20, 2026", used: "—", status: "available" },
    { code: "KSK-B120C", plan: "1 Hour", duration: "1 Hour", speed: "Standard", created: "Aug 20, 2026", used: "—", status: "disabled" },
    { code: "KSK-C88E4", plan: "5 Minutes", duration: "5 Minutes", speed: "Basic", created: "Aug 18, 2026", used: "—", status: "available" },
    { code: "KSK-D019F", plan: "3 Hours", duration: "3 Hours", speed: "Custom", download: 25, upload: 10, created: "Aug 16, 2026", used: "Aug 17, 2026 08:02", status: "used" },
  ],

  interfaces: [
    { name: "WAN", type: "PPPoE", status: "online", traffic: "86 Mbps" },
    { name: "LAN1", type: "Ethernet", status: "online", traffic: "32 Mbps" },
    { name: "LAN2", type: "Ethernet", status: "online", traffic: "12 Mbps" },
    { name: "LAN3", type: "Ethernet", status: "online", traffic: "8 Mbps" },
    { name: "LAN4", type: "Ethernet", status: "online", traffic: "4 Mbps" },
  ],

  segments: [
    { name: "Customer Network", vlan: "VLAN 10", cidr: "192.168.10.0/24", status: "active" },
    { name: "Management", vlan: "VLAN 20", cidr: "192.168.20.0/24", status: "active" },
    { name: "Controller", vlan: "VLAN 30", cidr: "192.168.30.0/24", status: "active" },
  ],

  dhcp: {
    status: "running",
    network: "192.168.10.0/24",
    activeLeases: 37,
    available: 217,
  },

  leases: [
    { ip: "192.168.10.21", device: "Galaxy-A54", mac: "A4:6C:F1:88:12:3A", status: "active", remaining: "18h 12m" },
    { ip: "192.168.10.34", device: "iPhone-13", mac: "F2:11:90:44:AB:09", status: "active", remaining: "21h 04m" },
    { ip: "192.168.10.12", device: "IdeaPad-3", mac: "00:1A:2B:3C:4D:5E", status: "expired", remaining: "—" },
    { ip: "192.168.10.45", device: "Redmi-Note-12", mac: "C8:2A:10:77:21:F4", status: "active", remaining: "9h 40m" },
    { ip: "192.168.10.52", device: "MacBook-Air", mac: "88:66:AA:11:22:33", status: "active", remaining: "22h 01m" },
    { ip: "192.168.10.61", device: "iPad-9", mac: "DE:AD:BE:EF:10:20", status: "active", remaining: "16h 28m" },
    { ip: "192.168.10.88", device: "android-guest", mac: "AA:BB:CC:11:22:33", status: "active", remaining: "23h 51m" },
  ],

  bandwidthProfiles: [
    { id: "bw-1", name: "Basic", download: 5, upload: 2, status: "active" },
    { id: "bw-2", name: "Standard", download: 10, upload: 5, status: "active" },
    { id: "bw-3", name: "Premium", download: 20, upload: 10, status: "active" },
  ],

  trafficHistory: {
    download: [54, 61, 58, 72, 80, 77, 84, 90, 86, 88, 92, 86],
    upload: [6, 8, 7, 9, 11, 10, 12, 14, 13, 12, 15, 13],
  },

  security: {
    firewall: "active",
    nat: "active",
    clientIsolation: "active",
    dnsProtection: "active",
    managementIsolation: "active",
    isolationEnabled: true,
  },

  contentFiltering: [
    { id: "adult", label: "Adult Content", enabled: true },
    { id: "gambling", label: "Gambling", enabled: true },
    { id: "malware", label: "Malware", enabled: true },
    { id: "phishing", label: "Phishing", enabled: true },
    { id: "social", label: "Social Media", enabled: false },
    { id: "streaming", label: "Streaming", enabled: false },
  ],

  settings: {
    systemName: "KonekSik-fi",
    locationName: "Main Branch — Poblacion",
    timezone: "Asia/Manila (GMT+8)",
    language: "English",
    currency: "PHP (₱)",
    adminName: "Site Owner",
    adminUsername: "admin",
    sessionTimeout: "30 minutes",
    theme: "light",
    compactMode: false,
    refreshInterval: "15 seconds",
    notifications: {
      internetOffline: true,
      mikrotikOffline: true,
      controllerOffline: true,
      apOffline: true,
      lowStorage: true,
      otaAvailable: true,
    },
    apRefreshSeconds: 10,
  },

  remoteAccess: {
    status: "connected",
    connection: "Secure Tunnel",
    lastConnected: "2 minutes ago",
    deviceId: "KSK-001",
    remoteSupport: true,
    enabled: true,
  },

  subVendos: [
    { id: "vendo-1", name: "KonekSik-fi #001", type: "ESP32", deviceId: "KSK-ESP-001", mac: "24:6F:28:AA:10:01", status: "online", users: 20, waiting: 5, sessions: 18, sales: 1500, uptime: "14d", location: "Main — Poblacion", apId: "AP-01", mikrotikBound: true, bindStatus: "bound" },
    { id: "vendo-2", name: "KonekSik-fi #002", type: "ESP32", deviceId: "KSK-ESP-002", mac: "24:6F:28:AA:10:02", status: "online", users: 10, waiting: 3, sessions: 8, sales: 500, uptime: "7d", location: "Annex — Market", apId: "AP-02", mikrotikBound: true, bindStatus: "bound" },
    { id: "vendo-3", name: "KonekSik-fi #003", type: "ESP32", deviceId: "KSK-ESP-003", mac: "24:6F:28:AA:10:03", status: "offline", users: 0, waiting: 0, sessions: 0, sales: 0, uptime: "—", location: "Branch — Terminal", apId: "", mikrotikBound: false, bindStatus: "unbound" },
  ],

  ota: {
    current: "v1.4.2",
    latest: "v1.4.3",
    status: "available",
    notes: {
      version: "1.4.3",
      improvements: ["Network stability", "Session management", "Coin handling"],
      fixes: ["Fixed session expiration issue", "Fixed device detection issue"],
    },
  },

  /**
   * Access Points — mock CAPsMAN remote-CAP inventory.
   * Production path:
   *   Browser → ESP32-S3-ETH → RouterOS API → CAPsMAN → CAP APs
   * APs are bridges only. Technician configures MikroTik; owner reads status here.
   */
  apLastUpdated: "16:42:12",
  apApiError: false,
  accessPoints: [
    {
      id: "AP-01",
      identity: "AP-01",
      model: "MikroTik hAP ax²",
      boardName: "hAP ax²",
      serial: "MOCK-SERIAL-001",
      baseMac: "48:A9:8A:11:22:01",
      ip: "192.168.20.11",
      status: "online",
      routeros: "v7.x",
      uptime: "14d 07h",
      connectedSince: "August 10, 2026",
      cpu: 21,
      memory: 38,
      storage: 27,
      temperature: 46,
      capsmamStatus: "connected",
      capsmamAddress: "192.168.20.1",
      speedProfile: "Custom",
      downloadLimit: 50,
      uploadLimit: 20,
      lastSeen: "Now",
      offlineReason: "",
      radios: [
        { band: "2.4 GHz", status: "active", channel: 6, width: "20 MHz", clients: 12, txPower: "Auto", mode: "AP" },
        { band: "5 GHz", status: "active", channel: 44, width: "80 MHz", clients: 8, txPower: "Auto", mode: "AP" },
      ],
      health: {
        capsmam: "healthy", ethernet: "healthy", radio24: "healthy", radio5: "healthy",
        clients: "normal", cpu: "normal", memory: "normal", temperature: "normal",
      },
      diagnostics: {
        capsmam: "passed", ip: "passed", ethernet: "passed", radio24: "passed", radio5: "passed",
      },
      traffic: { download: 42.1, upload: 6.4 },
      clients: [
        { id: "apc-1", device: "Samsung Galaxy", ip: "192.168.10.21", mac: "A4:6C:F1:88:12:3A", radio: "5 GHz", signal: "-48 dBm", uptime: "1h 22m", status: "connected", sessionId: "SES-10421" },
        { id: "apc-2", device: "iPhone 13", ip: "192.168.10.34", mac: "F2:11:90:44:AB:09", radio: "5 GHz", signal: "-52 dBm", uptime: "43m", status: "connected", sessionId: "SES-10418" },
        { id: "apc-3", device: "Lenovo IdeaPad", ip: "192.168.10.12", mac: "00:1A:2B:3C:4D:5E", radio: "2.4 GHz", signal: "-61 dBm", uptime: "21m", status: "connected", sessionId: "SES-10402" },
        { id: "apc-4", device: "Redmi Note", ip: "192.168.10.45", mac: "C8:2A:10:77:21:F4", radio: "2.4 GHz", signal: "-57 dBm", uptime: "48m", status: "connected", sessionId: "SES-10419" },
      ],
    },
    {
      id: "AP-02",
      identity: "AP-02",
      model: "MikroTik cAP ax",
      boardName: "cAP ax",
      serial: "MOCK-SERIAL-002",
      baseMac: "48:A9:8A:11:22:02",
      ip: "192.168.20.12",
      status: "online",
      routeros: "v7.x",
      uptime: "8d 14h",
      connectedSince: "August 16, 2026",
      cpu: 16,
      memory: 33,
      storage: 24,
      temperature: 44,
      capsmamStatus: "connected",
      capsmamAddress: "192.168.20.1",
      speedProfile: "Custom",
      downloadLimit: 50,
      uploadLimit: 20,
      lastSeen: "Now",
      offlineReason: "",
      radios: [
        { band: "2.4 GHz", status: "active", channel: 1, width: "20 MHz", clients: 7, txPower: "Auto", mode: "AP" },
        { band: "5 GHz", status: "active", channel: 36, width: "80 MHz", clients: 4, txPower: "Auto", mode: "AP" },
      ],
      health: {
        capsmam: "healthy", ethernet: "healthy", radio24: "healthy", radio5: "healthy",
        clients: "normal", cpu: "normal", memory: "normal", temperature: "normal",
      },
      diagnostics: {
        capsmam: "passed", ip: "passed", ethernet: "passed", radio24: "passed", radio5: "passed",
      },
      traffic: { download: 28.4, upload: 4.1 },
      clients: [
        { id: "apc-5", device: "MacBook Air", ip: "192.168.10.52", mac: "88:66:AA:11:22:33", radio: "5 GHz", signal: "-46 dBm", uptime: "5h 10m", status: "connected", sessionId: "SES-10422" },
        { id: "apc-6", device: "iPad 9", ip: "192.168.10.61", mac: "DE:AD:BE:EF:10:20", radio: "5 GHz", signal: "-55 dBm", uptime: "1h 04m", status: "connected", sessionId: "SES-10411" },
        { id: "apc-7", device: "android-guest", ip: "192.168.10.88", mac: "AA:BB:CC:11:22:33", radio: "2.4 GHz", signal: "-64 dBm", uptime: "8m", status: "connected", sessionId: "" },
      ],
    },
    {
      id: "AP-03",
      identity: "AP-03",
      model: "MikroTik hAP ax²",
      boardName: "hAP ax²",
      serial: "MOCK-SERIAL-003",
      baseMac: "48:A9:8A:11:22:03",
      ip: "192.168.20.13",
      status: "offline",
      routeros: "v7.x",
      uptime: "—",
      connectedSince: "—",
      cpu: 0,
      memory: 0,
      storage: 27,
      temperature: null,
      capsmamStatus: "disconnected",
      capsmamAddress: "192.168.20.1",
      speedProfile: "Custom",
      downloadLimit: 50,
      uploadLimit: 20,
      lastSeen: "12 minutes ago",
      offlineReason: "Connection Lost",
      radios: [
        { band: "2.4 GHz", status: "unknown", channel: "Not Available", width: "Not Available", clients: 0, txPower: "Not Available", mode: "AP" },
        { band: "5 GHz", status: "unknown", channel: "Not Available", width: "Not Available", clients: 0, txPower: "Not Available", mode: "AP" },
      ],
      health: {
        capsmam: "critical", ethernet: "unknown", radio24: "unknown", radio5: "unknown",
        clients: "unknown", cpu: "unknown", memory: "unknown", temperature: "unknown",
      },
      diagnostics: {
        capsmam: "failed", ip: "failed", ethernet: "warning", radio24: "not available", radio5: "not available",
      },
      traffic: { download: 0, upload: 0 },
      clients: [],
    },
  ],

  apEvents: [
    { time: "16:42", title: "Client connected", detail: "Samsung Galaxy · AP-01" },
    { time: "16:38", title: "5 GHz radio became active", detail: "AP-01" },
    { time: "16:21", title: "AP-02 connected to CAPsMAN", detail: "192.168.20.12" },
    { time: "15:54", title: "Client disconnected", detail: "iPhone" },
    { time: "15:20", title: "AP-03 went offline", detail: "Last seen 12 minutes ago" },
  ],

  notifications: [
    { id: "n1", type: "warning", title: "OTA update available", body: "Version 1.4.3 is ready to install.", time: "12 min ago", unread: true },
    { id: "n2", type: "info", title: "New unauthenticated client", body: "android-guest is waiting for access.", time: "28 min ago", unread: true },
    { id: "n3", type: "success", title: "Sales checkpoint", body: "Today's coin sales reached ₱1,000.", time: "1 hr ago", unread: false },
    { id: "n4", type: "danger", title: "Device blocked", body: "unknown-device was blocked manually.", time: "3d ago", unread: false },
  ],
};
