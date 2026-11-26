# Troubleshooting

## `cactusctl status` menunjukkan gateway 503

- Interval pertama setelah restart wajar: katalog model butuh 1–2 menit saat
  DNS ke `models.opencode.ai` sedang lambat. Cek `cactusctl log oc2api`.
- Kalau `model_catalog_empty` bertahan > 3 menit, cek konektivitas DNS chroot:
  `/etc/resolv.conf` harus berisi nameserver cadangan.
- Restart: `cactusctl oc2api restart`.

## `invalid local API key`

Client harus mengirim `Authorization: Bearer <key>`. Key ada di
`server_keys[0]` config.json dan otomatis dipakai CLI. Kalau client masih gagal,
pastikan key di client sama persis (lihat `~/bin/oc2api-test.sh` di device).

## Dialer/telepon tidak muncul setelah pasang SIM

Gejala: SIM terdeteksi (`gsm.sim.state = LOADED`, operator muncul), tapi tidak ada
aplikasi Telepon dan `resolve-activity -a android.intent.action.DIAL` menjawab
`No activity found`.

Penyebab di device ini: `com.android.dialer`, `com.mediatek.ims`, dan
`com.android.contacts` masih `disabled-user` sisa eksperimen mematikan GSM. Pulihkan:

```sh
adb shell 'su -c "pm enable com.android.dialer"'
adb shell 'su -c "pm enable com.android.contacts"'
adb shell 'su -c "pm enable com.mediatek.ims"'
adb shell 'su -c "pm list packages -d | grep -Ei \"dialer|ims|telecom|phone\""'
```

Verifikasi:

```sh
adb shell 'cmd package resolve-activity --brief -a android.intent.action.DIAL'
adb shell 'am start -a android.intent.action.DIAL -d tel:123'
adb shell 'dumpsys telecom | grep -i phoneAccount'
```

`com.android.phone`, `com.android.server.telecom`, dan `android.ext.services`
jangan pernah di-disable. Kalau airplane mode masih `1`, matikan dengan
`settings put global airplane_mode_on 0` + broadcast, lalu `svc wifi enable`.

## Bridge Android tidak jalan

`android`, `reboot`, `watchdog start` butuh `adb` di chroot:

```sh
apt install adb
adb connect 127.0.0.1:5555
cactusctl android status
```

Kalau port 5555 mati, nyalakan lewat Termux/SSH 8022 atau reboot (boot script
`adb-tcp.sh` akan menghidupkannya lagi).

Kalau status device `unauthorized`, kunci adb di chroot belum dipercaya device.
Salin kunci yang sudah di-authorize dari PC:

```sh
scp ~/.android/adbkey ~/.android/adbkey.pub root@redmi6a:/root/.android/
adb kill-server && adb connect 127.0.0.1:5555
cactusctl android connect
```

## Hermes tidak mau nyala setelah reboot

Cek marker `/data/local/.hermes-off`. Hapus lalu `cactusctl hermes on`.

## Hermes mati sendiri tiap ~5 menit (bukan OOM)

`idle-reaper.sh` di Android jalan tiap 5 menit dan dulu membunuh proses yang
cocok pola `_hermes_closure_repair` atau `/root/.hermes/tools/python*` — pola ini
juga cocok dengan launcher Hermes versi baru. Cek:

```sh
cactusctl reaper check
cactusctl reaper log 10
```

Guard yang benar harus ada di `/data/adb/idle-reaper.sh`:
```sh
case "$(cmd_of "$p")" in *gateway\ run*) continue;; esac
```
Tanpa guard itu, reaper akan membunuh gateway meski `suspected_oom=False`.

## Update gagal / auto-rollback

CLI otomatis memulihkan `opencode2api.bak.<timestamp>` kalau `/healthz` tidak
mencapai `status=ok` dalam 150 detik. Cek log restart di
`/tmp/cactus-update-restart.log` dan `cactusctl log oc2api`.

## Device reboot sendiri setelah `headless on`

Pernah terjadi: mematikan `com.android.systemui` memicu **RescueParty reboot**
(`/proc/last_kmsg`: `Restarting system with command 'RescueParty'`), bukan OOM dan
bukan `screenoff-reboot.sh`. Gejalanya: SSH :22 mati, service boot belum naik semua.

Pemulihan:
```sh
adb shell 'su -c "pm enable com.android.systemui com.android.launcher3 com.dvil.tui_renewed"'
adb shell 'su -c "/data/adb/chroot-enter.sh \"/usr/sbin/sshd -E /var/log/sshd.log\""'
# lalu hidupkan manual: cactusctl hermes on; cactusctl tunnel start; watchdog via ADB
```

Sejak itu `headless on` **tidak mematikan SystemUI** kecuali dipaksa dengan
`HEADLESS_FULL=1`. Gain aman dari console launcher + Launcher3 ≈ 250–300 MB.

## Setelah `headless on`, service tetap jalan tapi UI hilang

Itu memang disengaja. Yang mati: navigation bar, recents, Quick Settings/notification
shade, keyboard, launcher. Yang tetap hidup: sshd chroot :22, ADB :5555,
opencode2api, Hermes, tunnel, watchdog, Tailscale, `cactusctl`.

Rollback penuh: `cactusctl headless off`. Kalau ADB tidak bisa dipakai, enable manual
lewat Termux/SSH 8022:
```sh
su -c 'pm enable com.android.systemui com.android.launcher3 com.dvil.tui_renewed'
```

## SD-Linux belum ter-mount

Butuh 2–5 menit setelah boot (loop device baru tersedia 1–2 menit setelah boot).
`cactusctl status` akan menampilkan `sd-linux not mounted` sampai tersedia.
