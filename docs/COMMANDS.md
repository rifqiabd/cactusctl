# Referensi perintah

Semua perintah dijalankan sebagai `cactusctl <command> [sub] [args]`.

## Monitoring

| Perintah | Fungsi |
|---|---|
| `status` | Dashboard: opencode2api, Hermes, tunnel, watchdog, sshd, Tailscale, memori, disk, SD-Linux, health publik |
| `info` | Model/ABI Android (via ADB), kernel, distro, Python |
| `disk` | `df -h` + ukuran `/opt/oc2api`, `/opt/hermes`, `/root` |
| `net` | HTTP status endpoint lokal & publik |
| `log oc2api [n]` | `tail -n n /opt/oc2api/run.log` |
| `log tunnel [n]` | `tail -n n /opt/oc2api/named.log` |
| `log hermes [n]` | `tail -n n /opt/hermes/gateway.log` |
| `log sshd [n]` | `tail -n n /var/log/sshd.log` |

## Service

| Perintah | Fungsi |
|---|---|
| `service all status\|start\|stop\|restart` | Kontak semua service sekaligus |
| `oc2api start\|stop\|restart\|status` | Wrapper `/opt/oc2api/svc.sh ... gateway` |
| `oc2api health` | JSON dari `/healthz` |
| `oc2api models` | Daftar model yang diekspos gateway |
| `oc2api test [model]` | Chat completion smoke test (default `big-pickle`) |
| `oc2api config` | Ringkasan config dengan secret di-mask |
| `hermes on\|off\|toggle` | Start/stop + marker `/data/local/.hermes-off` |
| `hermes start\|stop\|restart\|status\|logs` | Kontrol langsung `/opt/hermes/svc.sh` |
| `tunnel start\|stop\|restart\|status\|logs` | Wrapper `svc.sh ... tunnel` |
| `ssh status\|start\|stop\|restart` | sshd chroot port 22 |

## Background job

| Perintah | Fungsi |
|---|---|
| `watchdog status` | Cek proses `oc2api-watch.sh` |
| `watchdog start\|stop` | Petunjuk + eksekusi via ADB bridge |
| `reaper status\|check\|run\|dry\|log [n]` | Idle reaper Android (cron tiap 5 menit). `check` memastikan guard `gateway run` ada supaya Hermes tidak ikut dibunuh |
| `monitor status\|run\|log` | Monitor server (crond Android, tiap 5 menit) |
| `backup now\|list` | Jalankan backup / lihat arsip |

## Jaringan & sistem

| Perintah | Fungsi |
|---|---|
| `tailscale status\|fix` | Cek proses / buka MainActivity via ADB |
| `headless status\|on\|off` | `on` mematikan console launcher + Launcher3 bertahap (ukur MemAvailable tiap tahap, buat marker `.server-mode`). **SystemUI tidak dimatikan by default** — pernah memicu reboot RescueParty. `HEADLESS_FULL=1 cactusctl headless on` untuk memaksa. Rollback: `headless off` |
| `android connect\|status\|battery\|sshd\|shell <cmd>` | Bridge ADB ke Android (auto-connect) |
| `reboot` | Reboot perangkat (konfirmasi, butuh ADB) |

## Maintenance

| Perintah | Fungsi |
|---|---|
| `update check` | Versi terpasang + sumber URL |
| `update oc2api` | Download, sha256, backup, swap, restart, health-check, rollback |
| `update self` | Update cactusctl dari `CACTUSCTL_URL` |
| `links show\|edit` | Lihat/sunyi semua URL download & repo |
| `config path\|show\|edit\|reload` | Konfigurasi CLI |

## Environment

- `NO_COLOR=1` — tanpa ANSI color
- `YES=1` — auto-confirm
- `CACTUS_CONF_DIR` — lokasi config (default `/etc/cactusctl`)
- `CACTUS_PREFIX_DIR` — lokasi install (default `/opt/cactusctl`)
