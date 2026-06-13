"""
POS Connect — Service système cross-platform.

Windows : python service_wrapper.py install | start | stop | remove
macOS   : python service_wrapper.py install | start | stop | remove
Linux   : python service_wrapper.py install | start | stop | remove
"""
import sys
import os
import subprocess
import platform
from pathlib import Path

SERVICE_NAME = "POSConnectServer"
SERVICE_DISPLAY = "POS Connect Server"
SERVICE_DESC = "Serveur API pour POS Connect"
BASE_DIR = Path(__file__).parent.resolve()


# ─── helpers ──────────────────────────────────────────────────────────────────

def _server_exe() -> Path:
    """Path to the compiled backend executable (Nuitka output)."""
    if platform.system() == "Windows":
        return BASE_DIR / "server" / "backend.exe"
    return BASE_DIR / "server" / "backend"


def _python_cmd() -> str:
    return sys.executable


# ══════════════════════════════════════════════════════════════════════════════
# Windows Service (pywin32)
# ══════════════════════════════════════════════════════════════════════════════

def _windows_install():
    try:
        import win32serviceutil
        import win32service
        import win32event
        import servicemanager
    except ImportError:
        print("❌  pywin32 manquant — pip install pywin32")
        sys.exit(1)

    # Register via sc.exe pointing to our compiled exe
    exe = _server_exe()
    cmd = [
        "sc", "create", SERVICE_NAME,
        f"binPath= \"{exe}\"",
        "start=", "auto",
        "DisplayName=", SERVICE_DISPLAY,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"❌  {result.stderr.strip()}")
    else:
        # Set description
        subprocess.run([
            "sc", "description", SERVICE_NAME, SERVICE_DESC
        ], capture_output=True)
        print(f"✅  Service '{SERVICE_NAME}' installé.")


def _windows_start():
    r = subprocess.run(["sc", "start", SERVICE_NAME], capture_output=True, text=True)
    print("✅  Démarré." if r.returncode == 0 else f"❌  {r.stderr.strip()}")


def _windows_stop():
    r = subprocess.run(["sc", "stop", SERVICE_NAME], capture_output=True, text=True)
    print("✅  Arrêté." if r.returncode == 0 else f"❌  {r.stderr.strip()}")


def _windows_remove():
    _windows_stop()
    r = subprocess.run(["sc", "delete", SERVICE_NAME], capture_output=True, text=True)
    print("✅  Supprimé." if r.returncode == 0 else f"❌  {r.stderr.strip()}")


def _windows_status():
    r = subprocess.run(["sc", "query", SERVICE_NAME], capture_output=True, text=True)
    print(r.stdout)


# ══════════════════════════════════════════════════════════════════════════════
# macOS — launchd
# ══════════════════════════════════════════════════════════════════════════════

MACOS_PLIST_PATH = Path(f"/Library/LaunchDaemons/com.posconnect.server.plist")

MACOS_PLIST_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.posconnect.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>{exe}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>{workdir}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/posconnect/server.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/posconnect/server_error.log</string>
</dict>
</plist>
"""


def _macos_install():
    exe = _server_exe()
    plist = MACOS_PLIST_TEMPLATE.format(exe=exe, workdir=BASE_DIR)
    Path("/var/log/posconnect").mkdir(parents=True, exist_ok=True)
    MACOS_PLIST_PATH.write_text(plist)
    subprocess.run(["launchctl", "load", "-w", str(MACOS_PLIST_PATH)])
    print(f"✅  Service launchd installé : {MACOS_PLIST_PATH}")


def _macos_start():
    subprocess.run(["launchctl", "start", "com.posconnect.server"])
    print("✅  Démarré.")


def _macos_stop():
    subprocess.run(["launchctl", "stop", "com.posconnect.server"])
    print("✅  Arrêté.")


def _macos_remove():
    subprocess.run(["launchctl", "unload", "-w", str(MACOS_PLIST_PATH)])
    if MACOS_PLIST_PATH.exists():
        MACOS_PLIST_PATH.unlink()
    print("✅  Service supprimé.")


# ══════════════════════════════════════════════════════════════════════════════
# Linux — systemd
# ══════════════════════════════════════════════════════════════════════════════

LINUX_UNIT_PATH = Path(f"/etc/systemd/system/posconnect.service")

LINUX_UNIT_TEMPLATE = """[Unit]
Description={desc}
After=network.target mysql.service

[Service]
Type=simple
ExecStart={exe}
WorkingDirectory={workdir}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=posconnect

[Install]
WantedBy=multi-user.target
"""


def _linux_install():
    exe = _server_exe()
    unit = LINUX_UNIT_TEMPLATE.format(
        desc=SERVICE_DESC, exe=exe, workdir=BASE_DIR
    )
    LINUX_UNIT_PATH.write_text(unit)
    subprocess.run(["systemctl", "daemon-reload"])
    subprocess.run(["systemctl", "enable", "posconnect"])
    print(f"✅  Service systemd installé : {LINUX_UNIT_PATH}")


def _linux_start():
    r = subprocess.run(["systemctl", "start", "posconnect"], capture_output=True)
    print("✅  Démarré." if r.returncode == 0 else "❌  Erreur (voir journalctl -u posconnect)")


def _linux_stop():
    subprocess.run(["systemctl", "stop", "posconnect"])
    print("✅  Arrêté.")


def _linux_remove():
    subprocess.run(["systemctl", "disable", "posconnect"])
    subprocess.run(["systemctl", "stop", "posconnect"])
    if LINUX_UNIT_PATH.exists():
        LINUX_UNIT_PATH.unlink()
    subprocess.run(["systemctl", "daemon-reload"])
    print("✅  Service supprimé.")


def _linux_status():
    subprocess.run(["systemctl", "status", "posconnect"])


# ══════════════════════════════════════════════════════════════════════════════
# Dispatcher
# ══════════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} install|start|stop|remove|status")
        sys.exit(1)

    action = sys.argv[1].lower()
    os_name = platform.system()

    ops = {
        "Windows": {
            "install": _windows_install,
            "start":   _windows_start,
            "stop":    _windows_stop,
            "remove":  _windows_remove,
            "status":  _windows_status,
        },
        "Darwin": {
            "install": _macos_install,
            "start":   _macos_start,
            "stop":    _macos_stop,
            "remove":  _macos_remove,
            "status":  lambda: subprocess.run(["launchctl", "list", "com.posconnect.server"]),
        },
        "Linux": {
            "install": _linux_install,
            "start":   _linux_start,
            "stop":    _linux_stop,
            "remove":  _linux_remove,
            "status":  _linux_status,
        },
    }

    if os_name not in ops:
        print(f"❌  OS non supporté : {os_name}")
        sys.exit(1)

    fn = ops[os_name].get(action)
    if not fn:
        print(f"❌  Action inconnue : {action}")
        sys.exit(1)

    fn()


if __name__ == "__main__":
    main()
