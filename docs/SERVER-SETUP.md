# Setup server (ringkasan)

Catatan lengkap ada di `/REDMI6A-SERVER-GUIDE.md` di dalam chroot. Dokumen ini
hanya ringkasan urutan yang penting supaya CLI tahu "di mana apa".

## Topologi

```
PC  --SSH :22--> Debian chroot (/data/local/debian)
        |          /opt/oc2api   -> opencode2api :8080 + cloudflared
        |          /opt/hermes   -> Hermes gateway
        |          watchdog/monitor/backup dijalankan dari sisi Android
        |
        --ADB :5555--> Android (Magisk root, Termux, Tailscale, ACC)
                          |
                    Cloudflare tunnel -> https://oc.thibbilqulub.my.id
```

## Prasyarat

- Redmi 6A, Android 12, ARM64, 2 GB RAM
- Magisk >= 25, root lewat `su -c`
- Tailscale always-on VPN (IP `100.x`)
- Chroot Debian asli (`chroot`, bukan proot) di `/data/local/debian`

## Layanan utama

| Komponen | Path | Kontrol |
|---|---|---|
| Gateway API | `/opt/oc2api/opencode2api` | `cactusctl oc2api ...` |
| Config gateway | `/opt/oc2api/config.json` | `cactusctl oc2api config` |
| Tunnel | `/opt/oc2api/cloudflared` | `cactusctl tunnel ...` |
| Hermes | `/opt/hermes/svc.sh` | `cactusctl hermes ...` |
| Watchdog | Android `/data/adb/oc2api-watch.sh` | `cactusctl watchdog status` |
| Monitor/backup | Android `/data/adb/server-*.sh` | `cactusctl monitor ...` |
| sshd chroot | `/usr/sbin/sshd`, port 22 | `cactusctl ssh ...` |

## Boot chain (Magisk service.d)

Skrip di `/data/adb/service.d/*.sh`, wajib `chmod 755`:

- `debian-sshd.sh` — sshd chroot port 22 (tailnet-only via iptables SSHGUARD)
- `termux-sshd.sh` — sshd Termux port 8022 (lifeline)
- `oc2api-boot.sh` — start gateway + tunnel + watchdog
- `hermes-boot.sh` — start Hermes (hormati marker `.hermes-off`)
- `tailscale-boot.sh` — always-on VPN
- `crond.sh` — monitor tiap 5 menit, backup 03:15
- `adb-tcp.sh` — adb over TCP :5555
- `screenoff-reboot.sh` — patch marker `.server-mode` supaya tidak reboot

## Hardening yang sudah dipakai

- `PermitRootLogin prohibit-password`, `PasswordAuthentication no` (key only)
- `AllowUsers root`, SSHGUARD membatasi port 22/2222 ke tailnet
- ACC: pause <= 85%, resume >= 60%
- Swapfile sementara saat install berat (JANGAN di SD card)
- DNS cadangan: 1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4

## Instal CLI di server baru

```sh
git clone <CACTUSCTL_REPO_URL> /root/cactusctl
cd /root/cactusctl
bash setup/install.sh
bash setup/bootstrap.sh --check     # lihat yang belum terpasang
cactusctl status
```

Isi link download di `/etc/cactusctl/links.conf` sebelum memakai `update oc2api`.
