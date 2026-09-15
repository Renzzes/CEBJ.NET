import tarfile
import os

def filter_function(tarinfo):
    # Normalize paths to use forward slashes for matching
    path = tarinfo.name.replace('\\', '/')

    # Sensitive/per-device files: NEVER ship in the OTA bundle.
    sensitive_patterns = [
        'www/data',
        'etc/fastfi_admin_pass.conf',
        'etc/passwd',
        'etc/shadow'
    ]

    # Static vendor assets: shipped via the per-device .bin sysupgrade image
    # (full image, fresh-flash + asset updates), NOT the OTA .tar.gz. The
    # .tar.gz is a CODE-ONLY incremental bundle: it carries FastFi code that
    # changes between releases (admin.js, bootstrap.js, lua, libexec, etc) but
    # omits large third-party assets that are already on every deployed device
    # and essentially never change. This keeps the overlay copy-up small
    # (~1.6 MB vs ~2.8 MB) so a .tar.gz apply fits a tight 16 MB overlay even
    # under the OLDER +1 MB gate still installed on pre-v2.2.7 boxes — letting
    # "Check for Updates" self-apply without SSH or a .bin reflash.
    #
    # Caveat: to change one of these assets (new audio, a jQuery/Bootstrap/Chart
    # version bump), ship a .bin sysupgrade — the .tar.gz won't carry it.
    # Confirm a candidate asset is UNCHANGED since the previous release before
    # adding it here (git diff <prev-tag>..HEAD -- <path>).
    vendor_asset_patterns = [
        'www/audio/insert.mp3',
        'www/audio/success.mp3',
        'www/audio/coin.mp3',
        'www/css/bootstrap.min.css',
        'www/chart.min.js',
        'www/jquery/jquery.min.js',
    ]

    # uci-defaults are FIRST-BOOT-ONLY by OpenWrt design: a script in
    # /etc/uci-defaults/ runs on the next boot and then auto-deletes on exit 0.
    # The .tar.gz apply does `cp -r EXTRACT/etc/* /etc/`, which RE-DEPLOYS
    # 99-fastfi-setup onto an already-running box — so it runs AGAIN on the
    # post-OTA boot and resets operator-configured WiFi SSID/password
    # (STEP 6 UPDATE config SET wifi_* defaults) and cron (STEP 10 cp
    # root.template -> root). Operators reported losing WiFi + cron settings
    # after every OTA. Excluding the whole uci-defaults tree from the .tar.gz
    # means a running box is never re-first-booted by an OTA. The .bin sysupgrade
    # (full image) still carries uci-defaults for genuine fresh flashes, and
    # one-time migrations for EXISTING devices go in the bundle's migrate.sh
    # (the apply runs EXTRACT/migrate.sh if present — fastfi-ota.sh:700), NOT
    # in uci-defaults. So a new uci-defaults script will reach fresh-flashed
    # boxes via .bin, and existing boxes via migrate.sh.
    uci_defaults_patterns = [
        'etc/uci-defaults',
    ]

    for pattern in sensitive_patterns:
        if pattern in path or ('/' + pattern) in path:
            print(f"Excluding (sensitive): {tarinfo.name}")
            return None

    for pattern in vendor_asset_patterns:
        if path == pattern or path.endswith('/' + pattern) or ('/' + pattern + '/') in path or path.startswith(pattern + '/'):
            print(f"Excluding (vendor asset, .bin-only): {tarinfo.name}")
            return None

    for pattern in uci_defaults_patterns:
        if path == pattern or path.endswith('/' + pattern) or ('/' + pattern + '/') in path or path.startswith(pattern + '/'):
            print(f"Excluding (uci-defaults, .bin-only): {tarinfo.name}")
            return None

    # Ensure executable scripts carry +x in the archive. tarfile on Windows
    # writes 0666 (no exec bit), but the OTA apply runs EXTRACT/migrate.sh only
    # when it is executable (fastfi-ota.sh `[ -x ]` guard). Without this,
    # migrate.sh ships non-executable and is silently skipped on EVERY apply —
    # so no migration (R1 no_symlinks, SQM opkg install, ...) ever reaches
    # existing boxes. The OTA apply's post-copy chmod block covers copied scripts
    # under libexec/init.d/etc, but NOT migrate.sh, which is executed straight
    # from the extract dir. Set +x on migrate.sh and the other script paths so
    # the archive carries what a Unix-built tarball would.
    if (path == 'migrate.sh'
            or path.endswith('.sh')
            or path.startswith('etc/init.d/')
            or path.startswith('usr/libexec/fastfi/')
            or path.startswith('www/cgi-bin/')):
        tarinfo.mode = 0o755

    print(f"Adding: {tarinfo.name}")
    return tarinfo

def main():
    archive_name = "update.tar.gz"
    # migrate.sh: one-time migration for EXISTING devices. The OTA apply runs
    # EXTRACT/migrate.sh if present (fastfi-ota.sh:681). Without it in the bundle,
    # the migrate.sh mechanism is dormant and no migration ever reaches running
    # boxes — so this MUST be packaged (was missing pre-v2.3.5, a latent bug).
    targets = ["VERSION", "migrate.sh", "www", "usr/lib/lua/fastfi", "usr/libexec/fastfi", "etc"]
    
    # Remove existing update.tar.gz if it exists
    if os.path.exists(archive_name):
        try:
            os.remove(archive_name)
            print(f"Removed existing {archive_name}")
        except Exception as e:
            print(f"Warning: could not remove existing archive: {e}")
            
    print(f"Creating {archive_name}...")
    with tarfile.open(archive_name, "w:gz") as tar:
        for target in targets:
            if os.path.exists(target):
                # When adding directories recursively, tar.add uses the filter on every child path
                tar.add(target, arcname=target, filter=filter_function)
            else:
                print(f"Warning: Target path '{target}' does not exist.")
                
    print(f"Archive {archive_name} created successfully!")

if __name__ == "__main__":
    main()
