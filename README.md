# cactusctl

CLI terpadu untuk mengelola **server Redmi 6A (Debian chroot)** — inspirasi dari
[serv00 Devil](https://docs.serv00.com/Devil/), tapi fokus hanya pada layanan yang
benar-benar jalan di server ini: `opencode2api`, Hermes, Cloudflare tunnel,
watchdog, monitor/backup, SSH chroot, Tailscale, dan bridge Android via ADB.

```
cactusctl status              # dashboard singkat
cactusctl oc2api health       # health JSON gateway
cactusctl oc2api test         # chat completion smoke test
cactusctl hermes toggle       # nyala/mati Hermes + marker Android
cactusctl tunnel restart
cactusctl update oc2api       # download -> verify sha256 -> swap -> health check -> rollback
cactusctl links edit          # semua URL download / repo disimpan di sini
```

## Kenapa ada repo ini

- Satu perintah untuk operasi harian (sebelumnya tersebar di `svc.sh`,
  `hermes-toggle.sh`, `chroot-enter.sh`, dll).
- Semua link download/repo dikumpulkan di satu file konfigurasi
  (`/etc/cactusctl/links.conf`) — gampang diganti tanpa menyunting kode.
- Update binary punya **verifikasi checksum + auto-rollback** kalau health tidak pulih.
- Repo ini juga jadi tempat skrip setup server supaya bisa diulang di perangkat lain.

## Struktur

```
cactusctl/
├── bin/cactusctl              # entrypoint
├── lib/
│   ├── common.sh              #config, warna, helper proses/HTTP
│   ├── services.sh            # oc2api, hermes, tunnel, watchdog, log, backup
│   └── system.sh              # dashboard, jaringan, update, ADB bridge
├── config/
│   ├── cactusctl.conf.example
│   └── links.conf.example     # ← isi link download/repo di sini
├── setup/
│   ├── install.sh             # pasang CLI di chroot
│   └── bootstrap.sh           # provisioning awal (server baru)
└── docs/
    ├── COMMANDS.md
    ├── SERVER-SETUP.md
    └── TROUBLESHOOTING.md
```

## Instal (di server / chroot Debian)

```sh
git clone <CACTUSCTL_REPO_URL> /root/cactusctl
cd /root/cactusctl
bash setup/install.sh
cactusctl status
```

Installer hanya menyalin file, membuat `/etc/cactusctl/`, dan symlink
`/usr/local/bin/cactusctl`. **Tidak** mengubah konfigurasi service yang sudah ada.

## Konfigurasi

| File | Isi |
|---|---|
| `/etc/cactusctl/cactusctl.conf` | path service, endpoint, API key, ADB bridge |
| `/etc/cactusctl/links.conf` | repo + URL download (diisi belakangan) |

Local API key kalau dikosongkan akan dibaca otomatis dari
`server_keys[0]` di `/opt/oc2api/config.json`.

## Update oc2api

```sh
cactusctl update check
cactusctl update oc2api
```

Tanpa `OC2API_URL`, CLI query GitHub API repo `jasonxu114514/opencode2api`,
ambil aset `linux_arm64.tar.gz` + `.sha256` terbaru, verifikasi, backup binary lama
dengan timestamp, restart gateway, lalu tunggu `/healthz` sampai `status=ok`.
Kalau gagal, binary lama dipulihkan otomatis.

## Bridge Android

Beberapa hal (reboot, battery, service.d, Tailscale) hidup di sisi Android, bukan di
chroot. CLI memakai `adb` ke `127.0.0.1:5555` (jaringan di-share dengan Android).

```sh
apt install adb                 # kalau belum ada
cactusctl android status
cactusctl reboot
```

Tanpa `adb`, perintah tetap menampilkan perintah `su -c ...` yang bisa dijalankan
lewat Termux/SSH 8022.

## Catatan

- `NO_COLOR=1` mematikan warna.
- `YES=1` menjawab "ya" otomatis untuk konfirmasi (dipakai script).
- Dirancang untuk bash + `curl` + `python3`; tidak butuh `jq`.

## Lisensi

MIT.
