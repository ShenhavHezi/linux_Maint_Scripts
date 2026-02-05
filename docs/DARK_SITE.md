# Dark-site / air-gapped deployment guide

This project supports offline installation by generating a self-contained tarball.

## 1) Build the tarball (connected workstation)

```bash
git clone https://github.com/ShenhavHezi/linux_Maint_Scripts.git
cd linux_Maint_Scripts

./tools/make_tarball.sh
# output: dist/linux_Maint_Scripts-<version>-<sha>.tgz
```

Optional (recommended) integrity file:

```bash
sha256sum dist/linux_Maint_Scripts-*.tgz > dist/SHA256SUMS
```

## 2) Transfer into the offline environment (staging / hop)

Move the tarball using your approved process. In many environments this is a multi-step “hop”, for example:

- connected workstation → staging machine / scanning station → removable media → offline network → target servers

Copy:
- `dist/linux_Maint_Scripts-*.tgz`
- `dist/SHA256SUMS` (optional)

On the offline side you can verify:

```bash
sha256sum -c SHA256SUMS
```

## 3) Install on the offline server(s)

On each target server (after you copy the tarball over, it will usually be in your working directory — not under `dist/`):

```bash
tar -xzf linux_Maint_Scripts-*.tgz
cd linux_Maint_Scripts-*

sudo ./install.sh --with-logrotate
# optional:
# sudo ./install.sh --with-user --with-timer --with-logrotate

# verify:
linux-maint version || true
sudo linux-maint status || true
```


## 4) Minimal startup (after installation)

1) Review the generated configs under `/etc/linux_maint/` (the installer creates defaults).
2) Run once manually to validate everything works:

```bash
sudo linux-maint run
sudo linux-maint status
```

3) If you installed the timer (`--with-timer`), confirm it is active:

```bash
systemctl status linux-maint.timer --no-pager || true
systemctl list-timers | grep -i linux-maint || true
```


## 5) Run manually (quick test)

```bash
sudo linux-maint run
sudo linux-maint logs 200
```

## Notes

- Installed mode is intended to run as root (or via sudo) because it uses `/var/log` and `/var/lock`.
- For per-monitor configuration, see files under `/etc/linux_maint/` (created by the installer).
- Full reference: [`reference.md`](reference.md)


## Verify integrity (recommended)

When transferring tarballs/packages into an air-gapped environment, verify integrity:

```bash
sha256sum linux-maint-*.tar.gz > linux-maint.sha256
# transfer both files
sha256sum -c linux-maint.sha256
```

If you use an internal artifact repository, store the checksum alongside the artifact.

## What to transfer

At minimum transfer:
- the release tarball (or git checkout) of this repository
- any required OS packages / dependencies (via your internal mirrors)
- your environment-specific config files under `/etc/linux_maint/`

Tip: `linux-maint make-tarball` can help create a self-contained bundle for offline use.
