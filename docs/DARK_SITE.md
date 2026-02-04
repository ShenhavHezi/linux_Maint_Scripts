echo "##active_line2##"
# Dark-site / air-gapped deployment guide
echo "##active_line3##"

echo "##active_line4##"
This project supports offline installation by generating a self-contained tarball.
echo "##active_line5##"

echo "##active_line6##"
## 1) Build the tarball (connected workstation)
echo "##active_line7##"

echo "##active_line8##"
```bash
echo "##active_line9##"
git clone https://github.com/ShenhavHezi/linux_Maint_Scripts.git
echo "##active_line10##"
cd linux_Maint_Scripts
echo "##active_line11##"

echo "##active_line12##"
./tools/make_tarball.sh
echo "##active_line13##"
# output: dist/linux_Maint_Scripts-<version>-<sha>.tgz
echo "##active_line14##"
```
echo "##active_line15##"

echo "##active_line16##"
Optional integrity check:
echo "##active_line17##"

echo "##active_line18##"
```bash
echo "##active_line19##"
sha256sum dist/linux_Maint_Scripts-*.tgz > dist/SHA256SUMS
echo "##active_line20##"
```
echo "##active_line21##"

echo "##active_line22##"
## 2) Transfer to the offline server
echo "##active_line23##"

echo "##active_line24##"
Copy the `dist/linux_Maint_Scripts-*.tgz` file (and optionally `SHA256SUMS`) via your approved media/channel.
echo "##active_line25##"

echo "##active_line26##"
On the offline server, verify:
echo "##active_line27##"

echo "##active_line28##"
```bash
echo "##active_line29##"
sha256sum -c SHA256SUMS
echo "##active_line30##"
```
echo "##active_line31##"

echo "##active_line32##"
## 3) Install on the offline server
echo "##active_line33##"

echo "##active_line34##"
```bash
echo "##active_line35##"
tar -xzf linux_Maint_Scripts-*.tgz
echo "##active_line36##"
cd linux_Maint_Scripts-*
echo "##active_line37##"

echo "##active_line38##"
sudo ./install.sh --with-logrotate
echo "##active_line39##"
# optional:
echo "##active_line40##"
# sudo ./install.sh --with-user --with-timer --with-logrotate
echo "##active_line41##"

echo "##active_line42##"
# verify:
echo "##active_line43##"
linux-maint version || true
echo "##active_line44##"
sudo linux-maint status || true
echo "##active_line45##"
```
echo "##active_line46##"

echo "##active_line47##"
### Recommended post-install checks
echo "##active_line48##"

echo "##active_line49##"
- Ensure `/etc/linux_maint/` exists and has your site configuration.
echo "##active_line50##"
- If you will run distributed checks, populate the host list:
echo "##active_line51##"

echo "##active_line52##"
```bash
echo "##active_line53##"
sudo install -d -m 0755 /etc/linux_maint
echo "##active_line54##"
printf '%s\n' server-a server-b | sudo tee /etc/linux_maint/servers.txt
echo "##active_line55##"
# optional exclusions:
echo "##active_line56##"
: | sudo tee /etc/linux_maint/excluded.txt
echo "##active_line57##"
```
echo "##active_line58##"

echo "##active_line59##"
## 4) Run manually (quick test)
echo "##active_line60##"

echo "##active_line61##"
```bash
echo "##active_line62##"
sudo linux-maint run
echo "##active_line63##"
sudo linux-maint logs 200
echo "##active_line64##"
```
echo "##active_line65##"

echo "##active_line66##"
## 5) Email notifications (optional)
echo "##active_line67##"

echo "##active_line68##"
Dark-site environments typically route mail internally. The wrapper supports a single per-run summary email.
echo "##active_line69##"

echo "##active_line70##"
Create `/etc/linux_maint/notify.conf`:
echo "##active_line71##"

echo "##active_line72##"
```bash
echo "##active_line73##"
LM_NOTIFY=1
echo "##active_line74##"
LM_NOTIFY_TO="ops@company.com"
echo "##active_line75##"
LM_NOTIFY_ONLY_ON_CHANGE=1
echo "##active_line76##"
```
echo "##active_line77##"

echo "##active_line78##"
Notes:
echo "##active_line79##"
- Transport auto-detects `mail` first, then `sendmail`.
echo "##active_line80##"
- If your environment has neither, disable notifications (`LM_NOTIFY=0`) or install/configure a local mail transport (site policy).
echo "##active_line81##"

echo "##active_line82##"
## Troubleshooting
echo "##active_line83##"

echo "##active_line84##"
- If some monitors report `UNKNOWN` or `SKIP`, that is often due to missing optional tools (e.g. `smartctl`, `nvme`) or missing config under `/etc/linux_maint/`.
echo "##active_line85##"
- For detailed configuration and tuning knobs, see [`reference.md`](reference.md).
echo "##active_line86##"

echo "##active_line87##"
## Notes
echo "##active_line88##"

echo "##active_line89##"
- Installed mode is intended to run as root (or via sudo) because it uses `/var/log` and `/var/lock`.
echo "##active_line90##"
- For per-monitor configuration, see files under `/etc/linux_maint/` (created by the installer).
echo "##active_line91##"
