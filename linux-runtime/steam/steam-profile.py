#!/usr/bin/env python3
import argparse
import os
import re
import shutil
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

HOME = Path(os.environ.get("HOME") or os.path.expanduser("~"))
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", str(HOME / ".config")))
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", str(HOME / ".local" / "share")))
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", str(HOME / ".cache")))
PREFIX = Path(os.environ.get("WAYLANDIE_PREFIX", "/usr/local"))
BIN_DIR = Path(os.environ.get("WAYLANDIE_BIN_DIR", str(PREFIX / "bin")))
ROOT = Path(os.environ.get("WAYLANDIE_STEAM_PROFILE_ROOT", str(CONFIG_HOME / "waylandie" / "steam")))
STEAM_ROOT = Path(os.environ.get("WAYLANDIE_STEAM_ROOT", str(DATA_HOME / "Steam")))
STEAMAPPS = STEAM_ROOT / "steamapps"
DXVK_CONFIG_DIR = Path(os.environ.get("WAYLANDIE_DXVK_CONFIG_DIR", str(CONFIG_HOME / "dxvk")))
MANGOHUD_DEFAULT = Path(os.environ.get("WAYLANDIE_MANGOHUD_CONFIG", str(CONFIG_HOME / "MangoHud" / "WayLandIESteamGame.conf")))
LEGACY_METRO_ROOT = Path(os.environ.get("WAYLANDIE_LEGACY_METRO_ROOT", str(CONFIG_HOME / "waylandie-metro")))
DESKTOP_DIR = Path(os.environ.get("XDG_DESKTOP_DIR", str(HOME / "Desktop")))
APPLICATIONS_DIR = DATA_HOME / "applications"
METRO_APPID = "287390"
BOOTSTRAPPING = False
GENERIC_HOOK = str(BIN_DIR / "waylandie-steam-game-launch") + " {appid} %command%"


def die(message, code=1):
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(code)


def valid_id(value):
    return bool(re.fullmatch(r"[A-Za-z0-9_.-]+", value or ""))


def q(value):
    text = str(value)
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`")
    return f'"{text}"'


def parse_env(path):
    env = OrderedDict()
    if not path or not Path(path).is_file():
        return env
    for raw in Path(path).read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            continue
        if len(value) >= 2 and value[0] == value[-1] == '"':
            value = value[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        env[key] = value
    return env


def write_env(path, env, header=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    if header:
        lines.append(f"# {header}")
    for key, value in env.items():
        if value is None or value == "":
            continue
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            continue
        lines.append(f"{key}={q(value)}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, **kwargs)


def game_dir(appid):
    return ROOT / "games" / str(appid)


def profiles_dir(appid):
    return game_dir(appid) / "profiles"


def active_path(appid):
    return game_dir(appid) / "active.env"


def game_env_path(appid):
    return game_dir(appid) / "game.env"


def templates_dir():
    return ROOT / "templates"


def default_common(appid):
    appid = str(appid)
    return OrderedDict([
        ("PROTON_NO_NTSYNC", "0"),
        ("PROTON_USE_NTSYNC", "1"),
        ("WINEDEBUG", "-all"),
        ("DXVK_LOG_LEVEL", "none"),
        ("DXVK_STATE_CACHE", "1"),
        ("DXVK_STATE_CACHE_PATH", str(STEAMAPPS / "shadercache" / appid / "DXVK_state_cache")),
        ("FEX_APP_CONFIG", str(ROOT / "fex" / "safeperf.json")),
        ("FEX_APP_CONFIG_LOCATION", str(STEAM_ROOT / "compatibilitytools.d" / "Proton11ARM" / "files" / "share" / "fex-emu")),
        ("MANGOHUD", "1"),
        ("MANGOHUD_CONFIGFILE", str(MANGOHUD_DEFAULT)),
        ("VK_DRIVER_FILES", "/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"),
        ("MESA_LOADER_DRIVER_OVERRIDE", "kgsl"),
        ("MESA_VK_DEVICE_SELECT", "5143:44050a31"),
        ("MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE", "1"),
        ("WAYLANDIE_STEAM_CPUSET", "4-7"),
        ("WAYLANDIE_STEAM_UCLAMP_MIN", "768"),
        ("WAYLANDIE_STEAM_UCLAMP_MAX", "1024"),
        ("WAYLANDIE_STEAM_NICE", "-10"),
        ("WAYLANDIE_STEAM_MONITOR_SECONDS", "21600"),
    ])


def built_in_profiles(appid):
    appid = str(appid)
    base = default_common(appid)

    def make(profile_id, label, summary, extra):
        env = OrderedDict()
        env["WAYLANDIE_STEAM_PROFILE_ID"] = profile_id
        env["WAYLANDIE_STEAM_PROFILE_LABEL"] = label
        env["WAYLANDIE_STEAM_PROFILE_SUMMARY"] = summary
        env["WAYLANDIE_STEAM_APPID"] = appid
        env.update(base)
        env.update(extra)
        return env

    stock = str(ROOT / "dxvk" / "stock-proton-current")
    qcom_root = ROOT / "qcom-adreno" / "custom"
    return OrderedDict([
        ("dxvk-binsem-2.7.1-gplasync", make(
            "dxvk-binsem-2.7.1-gplasync",
            "DXVK BinSem GPLAsync",
            "The412Banner BinSem/GPLAsync x64 DXVK with timeline semaphores disabled",
            OrderedDict([
                ("DXVK_ASYNC", "1"),
                ("DXVK_DISABLE_TIMELINE_SEMAPHORES", "1"),
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight-gplall.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", str(ROOT / "dxvk" / "binsem-2.7.1-gplasync")),
            ]),
        )),
        ("dxvk-gplall-2.7.1-4-sse2", make(
            "dxvk-gplall-2.7.1-4-sse2",
            "DXVK GPLALL 2.7.1-4 SSE2",
            "Digger GPLAsync/LowLatency x64 DXVK with async cache",
            OrderedDict([
                ("DXVK_ASYNC", "1"),
                ("DXVK_GPLASYNCCACHE", "1"),
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight-gplall.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", str(ROOT / "dxvk" / "gplall-2.7.1-4-sse2")),
            ]),
        )),
        ("dxvk-official-2.7.1", make(
            "dxvk-official-2.7.1",
            "Official DXVK 2.7.1",
            "Official upstream x64 DXVK 2.7.1 comparison profile",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", str(ROOT / "dxvk" / "official-2.7.1")),
            ]),
        )),
        ("dxvk-stock-proton-current", make(
            "dxvk-stock-proton-current",
            "Restore Stock Proton DXVK",
            "Restores the backed-up Proton DXVK DLL set before launch",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", stock),
            ]),
        )),
        ("dxvk-custom-slot", make(
            "dxvk-custom-slot",
            "Custom DXVK DLL Slot",
            "Manual x64 d3d11.dll/dxgi.dll slot for quick experiments",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", str(ROOT / "dxvk" / "custom")),
            ]),
        )),
        ("qcom-custom-slot", make(
            "qcom-custom-slot",
            "Custom Qualcomm Adreno Vulkan Slot",
            "Experimental proprietary Qualcomm Linux Vulkan path imported by waylandie-import-qcom-adreno-driver",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", stock),
                ("VK_DRIVER_FILES", str(qcom_root / "icd-shim" / "qcom_icd_shim.json")),
                ("QCOM_VULKAN_ICD_LIB", str(qcom_root / "active" / "libvulkan_adreno.so.1")),
                ("GBM_BACKENDS_PATH", str(qcom_root / "active" / "gbm")),
                ("GBM_BACKEND", "msm"),
                ("LD_LIBRARY_PATH", f"{qcom_root / 'active'}:${{LD_LIBRARY_PATH:-}}"),
                ("__EGL_VENDOR_LIBRARY_FILENAMES", str(qcom_root / "egl_adreno_abs.json")),
                ("VK_LOADER_LAYERS_DISABLE", "*MESA*,*MANGOHUD*,*VALVE*,*FROG*"),
                ("MANGOHUD", "0"),
                ("MESA_LOADER_DRIVER_OVERRIDE", ""),
                ("MESA_VK_DEVICE_SELECT", ""),
                ("MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE", ""),
            ]),
        )),
        ("turnip-current", make(
            "turnip-current",
            "Current Turnip + Proton DXVK",
            "Known-good Turnip/Freedreno path with stock Proton DXVK and external boosts",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", stock),
            ]),
        )),
        ("turnip-mailbox", make(
            "turnip-mailbox",
            "Turnip Mailbox Present",
            "Forces Mesa Vulkan WSI mailbox present mode",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", stock),
                ("MESA_VK_WSI_PRESENT_MODE", "mailbox"),
                ("vblank_mode", "3"),
            ]),
        )),
        ("turnip-immediate", make(
            "turnip-immediate",
            "Turnip Immediate Present",
            "Forces Mesa Vulkan WSI immediate present mode",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", stock),
                ("MESA_VK_WSI_PRESENT_MODE", "immediate"),
            ]),
        )),
        ("turnip-submit-thread", make(
            "turnip-submit-thread",
            "Turnip Submit Thread",
            "Enables Mesa Vulkan submit thread to test CPU submission overhead",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", stock),
                ("MESA_VK_ENABLE_SUBMIT_THREAD", "1"),
            ]),
        )),
        ("turnip-custom-icd-slot", make(
            "turnip-custom-icd-slot",
            "Custom Turnip ICD Slot",
            "Uses a dropped-in native aarch64 Turnip/Mesa ICD and library set",
            OrderedDict([
                ("DXVK_CONFIG_FILE", str(DXVK_CONFIG_DIR / "metro-lastlight.conf")),
                ("WAYLANDIE_STEAM_DXVK_DLL_DIR", stock),
                ("VK_DRIVER_FILES", str(ROOT / "turnip" / "custom" / "freedreno_icd.aarch64.json")),
                ("LD_LIBRARY_PATH", f"{ROOT / 'turnip' / 'custom'}:${{LD_LIBRARY_PATH:-}}"),
            ]),
        )),
    ])


def add_legacy_metro_keys(env):
    if env.get("WAYLANDIE_STEAM_APPID") != METRO_APPID:
        return env
    mapped = OrderedDict(env)
    if "WAYLANDIE_STEAM_PROFILE_ID" in env:
        mapped["WAYLANDIE_METRO_PROFILE_ID"] = env["WAYLANDIE_STEAM_PROFILE_ID"]
    if "WAYLANDIE_STEAM_PROFILE_LABEL" in env:
        mapped["WAYLANDIE_METRO_PROFILE_LABEL"] = env["WAYLANDIE_STEAM_PROFILE_LABEL"]
    if "WAYLANDIE_STEAM_PROFILE_SUMMARY" in env:
        mapped["WAYLANDIE_METRO_PROFILE_SUMMARY"] = env["WAYLANDIE_STEAM_PROFILE_SUMMARY"]
    if "WAYLANDIE_STEAM_DXVK_DLL_DIR" in env:
        mapped["WAYLANDIE_METRO_DXVK_DLL_DIR"] = env["WAYLANDIE_STEAM_DXVK_DLL_DIR"]
    if "WAYLANDIE_STEAM_CPUSET" in env:
        mapped["WAYLANDIE_METRO_CPUSET"] = env["WAYLANDIE_STEAM_CPUSET"]
    if "WAYLANDIE_STEAM_UCLAMP_MIN" in env:
        mapped["WAYLANDIE_METRO_UCLAMP_MIN"] = env["WAYLANDIE_STEAM_UCLAMP_MIN"]
    if "WAYLANDIE_STEAM_UCLAMP_MAX" in env:
        mapped["WAYLANDIE_METRO_UCLAMP_MAX"] = env["WAYLANDIE_STEAM_UCLAMP_MAX"]
    if "WAYLANDIE_STEAM_NICE" in env:
        mapped["WAYLANDIE_METRO_NICE"] = env["WAYLANDIE_STEAM_NICE"]
    if "WAYLANDIE_STEAM_MONITOR_SECONDS" in env:
        mapped["WAYLANDIE_METRO_MONITOR_SECONDS"] = env["WAYLANDIE_STEAM_MONITOR_SECONDS"]
    return mapped


def is_tool_manifest(name):
    lowered = name.lower()
    prefixes = [
        "steam linux runtime",
        "proton ",
        "proton-",
        "steamworks common redistributables",
    ]
    return any(lowered.startswith(prefix) for prefix in prefixes)


def appmanifests(include_tools=True):
    games = []
    for manifest in sorted(STEAMAPPS.glob("appmanifest_*.acf")):
        data = parse_simple_acf(manifest)
        appid = data.get("appid") or manifest.stem.replace("appmanifest_", "")
        name = data.get("name") or f"App {appid}"
        if not include_tools and is_tool_manifest(name):
            continue
        installdir = data.get("installdir") or name
        gamedir = STEAMAPPS / "common" / installdir
        games.append({"appid": str(appid), "name": name, "installdir": installdir, "game_dir": str(gamedir)})
    return games


def parse_simple_acf(path):
    data = {}
    pattern = re.compile(r'^\s*"([^"]+)"\s+"(.*)"\s*$')
    for line in Path(path).read_text(encoding="utf-8", errors="ignore").splitlines():
        match = pattern.match(line)
        if match:
            data[match.group(1)] = match.group(2)
    return data


def infer_process_name(appid, name):
    if str(appid) == METRO_APPID:
        return "metro.exe"
    lowered = name.lower()
    if "metro" in lowered and "last light" in lowered:
        return "metro.exe"
    return ""


def ensure_link_or_copy(src, dst):
    src = Path(src)
    dst = Path(dst)
    if not src.exists() or dst.exists() or dst.is_symlink():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        dst.symlink_to(src, target_is_directory=src.is_dir())
    except OSError:
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)


def bootstrap(args=None):
    global BOOTSTRAPPING
    if BOOTSTRAPPING:
        return
    BOOTSTRAPPING = True
    try:
        for directory in [
            ROOT, templates_dir(), ROOT / "dxvk", ROOT / "turnip", ROOT / "turnip" / "custom",
            ROOT / "fex", ROOT / "backups", ROOT / "games", DXVK_CONFIG_DIR,
            MANGOHUD_DEFAULT.parent, DESKTOP_DIR, APPLICATIONS_DIR,
        ]:
            directory.mkdir(parents=True, exist_ok=True)

        legacy_dxvk = LEGACY_METRO_ROOT / "dxvk"
        for slot in ["stock-proton-current", "official-2.7.1", "gplall-2.7.1-4-sse2", "binsem-2.7.1-gplasync", "custom"]:
            ensure_link_or_copy(legacy_dxvk / slot, ROOT / "dxvk" / slot)
        ensure_link_or_copy(LEGACY_METRO_ROOT / "turnip" / "custom", ROOT / "turnip" / "custom")

        legacy_fex = LEGACY_METRO_ROOT / "fex" / "safeperf.json"
        if not (ROOT / "fex" / "safeperf.json").exists() and legacy_fex.exists():
            shutil.copy2(legacy_fex, ROOT / "fex" / "safeperf.json")
        legacy_mangohud = MANGOHUD_DEFAULT.parent / "MetroLastLight.conf"
        if not MANGOHUD_DEFAULT.exists() and legacy_mangohud.exists():
            shutil.copy2(legacy_mangohud, MANGOHUD_DEFAULT)

        for game in appmanifests():
            appid = game["appid"]
            genv = OrderedDict([
                ("WAYLANDIE_STEAM_APPID", appid),
                ("WAYLANDIE_STEAM_GAME_NAME", game["name"]),
                ("WAYLANDIE_STEAM_GAME_DIR", game["game_dir"]),
                ("WAYLANDIE_STEAM_PROCESS_NAME", infer_process_name(appid, game["name"])),
            ])
            if not game_env_path(appid).exists():
                write_env(game_env_path(appid), genv, f"WayLandIE Steam game metadata for {game['name']}")
            ensure_default_profiles(appid)

        if game_env_path(METRO_APPID).exists() and not active_path(METRO_APPID).exists():
            current = parse_env(LEGACY_METRO_ROOT / "active.env")
            if current:
                current = metro_to_generic(current)
                write_env(active_path(METRO_APPID), current, "Imported active Metro profile")
            else:
                set_profile(METRO_APPID, "dxvk-binsem-2.7.1-gplasync", quiet=True)

        print(f"profile_root={ROOT}")
        print(f"games={len(appmanifests())}")
    finally:
        BOOTSTRAPPING = False


def ensure_default_profiles(appid):
    pdir = profiles_dir(appid)
    pdir.mkdir(parents=True, exist_ok=True)
    for profile_id, env in built_in_profiles(appid).items():
        target = pdir / f"{profile_id}.env"
        if not target.exists():
            write_env(target, add_legacy_metro_keys(env), f"Built-in WayLandIE Steam profile {profile_id}")


def metro_to_generic(env):
    mapped = OrderedDict()
    for key, value in env.items():
        if key.startswith("WAYLANDIE_METRO_PROFILE_"):
            mapped[key.replace("WAYLANDIE_METRO_", "WAYLANDIE_STEAM_", 1)] = value
        elif key == "WAYLANDIE_METRO_DXVK_DLL_DIR":
            mapped["WAYLANDIE_STEAM_DXVK_DLL_DIR"] = value.replace(str(LEGACY_METRO_ROOT / "dxvk"), str(ROOT / "dxvk"))
        elif key.startswith("WAYLANDIE_METRO_"):
            mapped[key.replace("WAYLANDIE_METRO_", "WAYLANDIE_STEAM_", 1)] = value
        else:
            mapped[key] = value.replace(str(LEGACY_METRO_ROOT / "dxvk"), str(ROOT / "dxvk")) if isinstance(value, str) else value
    mapped["WAYLANDIE_STEAM_APPID"] = METRO_APPID
    return add_legacy_metro_keys(mapped)


def list_games(args):
    bootstrap_silent()
    rows = []
    for game in appmanifests(include_tools=args.all):
        active = parse_env(active_path(game["appid"]))
        profile = active.get("WAYLANDIE_STEAM_PROFILE_ID") or active.get("WAYLANDIE_METRO_PROFILE_ID") or "none"
        hook = "hooked" if launch_option_status(game["appid"]).get("compatible") else "no-hook"
        rows.append((game["appid"], game["name"], profile, hook, game["game_dir"]))
    for row in rows:
        print("\t".join(row))


def list_profiles(args):
    bootstrap_silent()
    appid = str(args.appid)
    ensure_default_profiles(appid)
    active = parse_env(active_path(appid)).get("WAYLANDIE_STEAM_PROFILE_ID", "")
    for path in sorted(profiles_dir(appid).glob("*.env")):
        env = parse_env(path)
        pid = env.get("WAYLANDIE_STEAM_PROFILE_ID") or path.stem
        label = env.get("WAYLANDIE_STEAM_PROFILE_LABEL") or pid
        summary = env.get("WAYLANDIE_STEAM_PROFILE_SUMMARY") or ""
        state = "active" if pid == active else ""
        print("\t".join([pid, label, summary, state]))


def set_profile(appid, profile_id, quiet=False):
    appid = str(appid)
    if not valid_id(profile_id):
        die(f"invalid profile id: {profile_id}", 2)
    if not BOOTSTRAPPING:
        bootstrap_silent()
    ensure_default_profiles(appid)
    src = profiles_dir(appid) / f"{profile_id}.env"
    if not src.is_file():
        die(f"profile not found: {src}", 3)
    env = parse_env(src)
    if not env.get("WAYLANDIE_STEAM_PROFILE_ID"):
        env["WAYLANDIE_STEAM_PROFILE_ID"] = profile_id
    env["WAYLANDIE_STEAM_APPID"] = appid
    genv = parse_env(game_env_path(appid))
    if genv.get("WAYLANDIE_STEAM_GAME_DIR"):
        env.setdefault("WAYLANDIE_STEAM_GAME_DIR", genv["WAYLANDIE_STEAM_GAME_DIR"])
    env = add_legacy_metro_keys(env)
    write_env(active_path(appid), env, f"Active WayLandIE Steam profile for appid {appid}")
    if appid == METRO_APPID:
        write_env(LEGACY_METRO_ROOT / "active.env", env, "Compatibility copy for existing Metro launcher")
    if not quiet:
        print(f"active_appid={appid}")
        print(f"active_profile={profile_id}")
        status(argparse.Namespace(appid=appid))


def set_profile_cmd(args):
    set_profile(args.appid, args.profile)


def status(args):
    bootstrap_silent()
    appid = str(args.appid)
    game = parse_env(game_env_path(appid))
    env = parse_env(active_path(appid))
    hook = launch_option_status(appid)
    print(f"appid={appid}")
    print(f"name={game.get('WAYLANDIE_STEAM_GAME_NAME', '')}")
    print(f"active_profile={env.get('WAYLANDIE_STEAM_PROFILE_ID') or env.get('WAYLANDIE_METRO_PROFILE_ID') or 'none'}")
    print(f"label={env.get('WAYLANDIE_STEAM_PROFILE_LABEL') or env.get('WAYLANDIE_METRO_PROFILE_LABEL') or ''}")
    print(f"launch_hook={'compatible' if hook.get('compatible') else 'not-installed'}")
    if hook.get("launch_options"):
        print(f"launch_options={hook['launch_options']}")
    checks = [
        ("dxvk_dll_dir", env.get("WAYLANDIE_STEAM_DXVK_DLL_DIR") or env.get("WAYLANDIE_METRO_DXVK_DLL_DIR"), ["d3d11.dll", "dxgi.dll"]),
        ("dxvk_config", env.get("DXVK_CONFIG_FILE"), []),
        ("mangohud_config", env.get("MANGOHUD_CONFIGFILE"), []),
        ("fex_config", env.get("FEX_APP_CONFIG"), []),
        ("vk_driver_files", env.get("VK_DRIVER_FILES"), []),
        ("qcom_vulkan_icd", env.get("QCOM_VULKAN_ICD_LIB"), []),
        ("vk_layer_path", env.get("VK_LAYER_PATH"), []),
        ("gbm_backends_path", env.get("GBM_BACKENDS_PATH"), []),
    ]
    for label, value, children in checks:
        if not value:
            continue
        ok = Path(value).exists()
        for child in children:
            ok = ok and (Path(value) / child).exists()
        print(f"{label}={value} {'OK' if ok else 'MISSING'}")
    for key in ["PROTON_USE_NTSYNC", "DXVK_ASYNC", "DXVK_GPLASYNCCACHE", "DXVK_DISABLE_TIMELINE_SEMAPHORES", "MESA_VK_WSI_PRESENT_MODE", "MESA_VK_ENABLE_SUBMIT_THREAD", "VK_INSTANCE_LAYERS", "GBM_BACKEND", "VK_LOADER_LAYERS_DISABLE", "WAYLANDIE_STEAM_CPUSET"]:
        if key in env:
            print(f"{key}={env[key]}")


def launch(args):
    bootstrap_silent()
    appid = str(args.appid)
    process = args.process or parse_env(game_env_path(appid)).get("WAYLANDIE_STEAM_PROCESS_NAME") or ""
    timeout = str(args.timeout)
    cmd = [str(BIN_DIR / "waylandie-steam-launch-app"), appid]
    if process:
        cmd.append(process)
        cmd.append(timeout)
    print(" ".join(cmd))
    raise SystemExit(run(cmd).returncode)


def bootstrap_silent():
    if BOOTSTRAPPING:
        return
    marker = ROOT / ".bootstrapped"
    if marker.exists():
        return
    saved = sys.stdout
    try:
        with open(os.devnull, "w") as devnull:
            sys.stdout = devnull
            bootstrap()
    finally:
        sys.stdout = saved
    marker.write_text("1\n", encoding="utf-8")


def tokenize_vdf(text):
    tokens = []
    i = 0
    while i < len(text):
        c = text[i]
        if c.isspace():
            i += 1
            continue
        if c in "{}":
            tokens.append(c)
            i += 1
            continue
        if c == '"':
            i += 1
            out = []
            while i < len(text):
                c = text[i]
                if c == "\\" and i + 1 < len(text):
                    out.append(text[i + 1])
                    i += 2
                    continue
                if c == '"':
                    i += 1
                    break
                out.append(c)
                i += 1
            tokens.append(("s", "".join(out)))
            continue
        start = i
        while i < len(text) and not text[i].isspace() and text[i] not in "{}":
            i += 1
        tokens.append(("s", text[start:i]))
    return tokens


def parse_vdf_obj(tokens, index=0):
    obj = OrderedDict()
    while index < len(tokens):
        tok = tokens[index]
        if tok == "}":
            return obj, index + 1
        if tok == "{":
            raise ValueError("unexpected object start")
        key = tok[1]
        index += 1
        if index >= len(tokens):
            obj[key] = ""
            break
        nxt = tokens[index]
        if nxt == "{":
            value, index = parse_vdf_obj(tokens, index + 1)
        else:
            value = nxt[1]
            index += 1
        obj[key] = value
    return obj, index


def parse_vdf(path):
    tokens = tokenize_vdf(Path(path).read_text(encoding="utf-8", errors="ignore"))
    obj, _ = parse_vdf_obj(tokens)
    return obj


def vdf_quote(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def dump_vdf_obj(obj, indent=0):
    lines = []
    tab = "\t" * indent
    for key, value in obj.items():
        if isinstance(value, OrderedDict) or isinstance(value, dict):
            lines.append(f"{tab}{vdf_quote(key)}")
            lines.append(f"{tab}" + "{")
            lines.extend(dump_vdf_obj(value, indent + 1))
            lines.append(f"{tab}" + "}")
        else:
            lines.append(f"{tab}{vdf_quote(key)}\t\t{vdf_quote(value)}")
    return lines


def find_localconfig():
    candidates = sorted((STEAM_ROOT / "userdata").glob("*/config/localconfig.vdf"))
    return candidates[0] if candidates else None


def steam_apps_obj(root):
    node = root.setdefault("UserLocalConfigStore", OrderedDict())
    for key in ["Software", "Valve", "Steam", "apps"]:
        node = node.setdefault(key, OrderedDict())
    return node


def launch_option_status(appid):
    path = find_localconfig()
    if not path:
        return {"compatible": False, "launch_options": "", "path": ""}
    try:
        root = parse_vdf(path)
        apps = steam_apps_obj(root)
        launch_options = apps.get(str(appid), {}).get("LaunchOptions", "") if isinstance(apps.get(str(appid), {}), dict) else ""
    except Exception:
        text = path.read_text(encoding="utf-8", errors="ignore")
        launch_options = ""
        if f'waylandie-steam-game-launch {appid}' in text:
            launch_options = "detected-by-text-scan"
    compatible = f"waylandie-steam-game-launch {appid}" in launch_options
    return {"compatible": compatible, "launch_options": launch_options, "path": str(path)}


def hook(args):
    bootstrap_silent()
    appid = str(args.appid)
    path = find_localconfig()
    if not path:
        die("Steam localconfig.vdf not found", 4)
    root = parse_vdf(path)
    apps = steam_apps_obj(root)
    app = apps.setdefault(appid, OrderedDict())
    old = app.get("LaunchOptions", "")
    new = GENERIC_HOOK.format(appid=appid)
    if old == new:
        print(f"launch_hook=already-installed appid={appid}")
        return
    backup = path.with_suffix(path.suffix + ".waylandie-profile-bak")
    if not backup.exists():
        shutil.copy2(path, backup)
    app["LaunchOptions"] = new
    path.write_text("\n".join(dump_vdf_obj(root)) + "\n", encoding="utf-8")
    print(f"launch_hook=installed appid={appid}")
    print(f"old_launch_options={old}")
    print(f"new_launch_options={new}")
    print(f"backup={backup}")
    if find_steam_pid():
        print("note=Steam is currently running; restart Steam once if the Launch Options UI does not reflect this immediately.")


def find_steam_pid():
    try:
        out = subprocess.check_output(["pgrep", "-n", "-x", "steam"], text=True, stderr=subprocess.DEVNULL).strip()
        return out
    except Exception:
        return ""


def create_dxvk_profile(args):
    bootstrap_silent()
    profile_id = args.profile or f"dxvk-{args.slot}"
    if not valid_id(profile_id) or not valid_id(args.slot):
        die("invalid slot/profile id", 2)
    appids = [game["appid"] for game in appmanifests(include_tools=False)] if str(args.appid).lower() == "all" else [str(args.appid)]
    for appid in appids:
        create_dxvk_profile_for_app(appid, args.slot, profile_id, args.label, args.summary, args.activate)


def create_dxvk_profile_for_app(appid, slot, profile_id, label, summary, activate):
    env = built_in_profiles(appid)["dxvk-custom-slot"]
    env["WAYLANDIE_STEAM_PROFILE_ID"] = profile_id
    env["WAYLANDIE_STEAM_PROFILE_LABEL"] = label or f"DXVK {slot}"
    env["WAYLANDIE_STEAM_PROFILE_SUMMARY"] = summary or f"Custom DXVK slot {slot}"
    env["WAYLANDIE_STEAM_DXVK_DLL_DIR"] = str(ROOT / "dxvk" / slot)
    env["WAYLANDIE_STEAM_APPID"] = appid
    env = add_legacy_metro_keys(env)
    write_env(profiles_dir(appid) / f"{profile_id}.env", env, f"Custom DXVK profile {profile_id}")
    print(f"profile={profiles_dir(appid) / (profile_id + '.env')}")
    if activate:
        set_profile(appid, profile_id)


def create_turnip_profile(args):
    bootstrap_silent()
    profile_id = args.profile or f"turnip-{args.slot}"
    if not valid_id(profile_id) or not valid_id(args.slot):
        die("invalid slot/profile id", 2)
    appids = [game["appid"] for game in appmanifests(include_tools=False)] if str(args.appid).lower() == "all" else [str(args.appid)]
    for appid in appids:
        create_turnip_profile_for_app(appid, args.slot, profile_id, args.label, args.summary, args.activate)


def create_turnip_profile_for_app(appid, slot, profile_id, label, summary, activate):
    env = built_in_profiles(appid)["turnip-custom-icd-slot"]
    env["WAYLANDIE_STEAM_PROFILE_ID"] = profile_id
    env["WAYLANDIE_STEAM_PROFILE_LABEL"] = label or f"Turnip {slot}"
    env["WAYLANDIE_STEAM_PROFILE_SUMMARY"] = summary or f"Custom Turnip/Mesa slot {slot}"
    env["VK_DRIVER_FILES"] = str(ROOT / "turnip" / slot / "freedreno_icd.aarch64.json")
    env["LD_LIBRARY_PATH"] = f"{ROOT / 'turnip' / slot}:${{LD_LIBRARY_PATH:-}}"
    env["WAYLANDIE_STEAM_APPID"] = appid
    env = add_legacy_metro_keys(env)
    write_env(profiles_dir(appid) / f"{profile_id}.env", env, f"Custom Turnip profile {profile_id}")
    print(f"profile={profiles_dir(appid) / (profile_id + '.env')}")
    if activate:
        set_profile(appid, profile_id)


def create_qcom_profile(args):
    bootstrap_silent()
    profile_id = args.profile or f"qcom-{args.slot}"
    if not valid_id(profile_id) or not valid_id(args.slot):
        die("invalid slot/profile id", 2)
    appids = [game["appid"] for game in appmanifests(include_tools=False)] if str(args.appid).lower() == "all" else [str(args.appid)]
    for appid in appids:
        create_qcom_profile_for_app(appid, args.slot, profile_id, args.label, args.summary, args.activate)


def create_qcom_profile_for_app(appid, slot, profile_id, label, summary, activate):
    slot_root = ROOT / "qcom-adreno" / slot
    slot_env = parse_env(slot_root / "qcom-driver.env")
    if not slot_env:
        die(f"Qualcomm slot metadata not found: {slot_root / 'qcom-driver.env'}", 4)
    env = built_in_profiles(appid)["qcom-custom-slot"]
    env["WAYLANDIE_STEAM_PROFILE_ID"] = profile_id
    env["WAYLANDIE_STEAM_PROFILE_LABEL"] = label or f"Qualcomm Adreno {slot}"
    env["WAYLANDIE_STEAM_PROFILE_SUMMARY"] = summary or f"Imported Qualcomm Adreno Vulkan slot {slot}"
    env["WAYLANDIE_STEAM_APPID"] = appid
    env.update(slot_env)
    env = add_legacy_metro_keys(env)
    write_env(profiles_dir(appid) / f"{profile_id}.env", env, f"Custom Qualcomm Adreno profile {profile_id}")
    print(f"profile={profiles_dir(appid) / (profile_id + '.env')}")
    if activate:
        set_profile(appid, profile_id)


def zenity(args, input_text=None):
    proc = subprocess.run(["zenity", *args], input=input_text, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def gui(args):
    bootstrap_silent()
    if not shutil.which("zenity"):
        die("zenity not installed; use CLI commands", 5)
    while True:
        rows = []
        for game in appmanifests(include_tools=False):
            active = parse_env(active_path(game["appid"]))
            profile = active.get("WAYLANDIE_STEAM_PROFILE_LABEL") or active.get("WAYLANDIE_STEAM_PROFILE_ID") or "none"
            hook_state = "Hooked" if launch_option_status(game["appid"]).get("compatible") else "No hook"
            rows.extend([game["appid"], game["name"], profile, hook_state])
        selected = zenity([
            "--list", "--title=WayLandIE Steam Game Profiles", "--text=Choose a Steam game",
            "--column=AppID", "--column=Game", "--column=Active profile", "--column=Steam hook",
            "--width=980", "--height=520",
        ], "\n".join(rows) + "\n")
        if not selected:
            return
        appid = selected.split("|", 1)[0].strip()
        action = zenity([
            "--list", "--title=WayLandIE Steam Game Profiles", f"--text=AppID {appid}: choose action",
            "--column=Action", "--column=What it does", "--width=780", "--height=360",
        ], "\n".join([
            "Apply profile\nChoose DXVK/Turnip/FEX/MangoHud/NTSYNC profile for next launch",
            "Apply and launch\nApply a profile, then launch through Steam URL",
            "Install Steam hook\nSet Steam Launch Options to the generic profile wrapper",
            "Status\nShow active profile and missing-file checks",
            "Edit active env\nOpen the active profile env for manual flags",
            "Quit\nClose this selector",
        ]) + "\n")
        if not action or action.startswith("Quit"):
            return
        if action.startswith("Apply"):
            profile = choose_profile(appid)
            if not profile:
                continue
            set_profile(appid, profile, quiet=True)
            message = capture_status(appid)
            if action.startswith("Apply and launch"):
                zenity(["--info", "--title=Profile Applied", f"--text={message}\n\nLaunching through Steam now."])
                launch(argparse.Namespace(appid=appid, process="", timeout=120))
            else:
                zenity(["--info", "--title=Profile Applied", f"--text={message}\n\nRestart the game for driver/FEX changes to take effect."])
        elif action.startswith("Install"):
            try:
                output = capture_output(lambda: hook(argparse.Namespace(appid=appid)))
                zenity(["--info", "--title=Steam Hook", f"--text={output}"])
            except SystemExit as exc:
                zenity(["--error", "--title=Steam Hook Failed", f"--text={exc}"])
        elif action.startswith("Status"):
            zenity(["--info", "--title=Profile Status", f"--text={capture_status(appid)}", "--width=820"])
        elif action.startswith("Edit"):
            edit_active_env(appid)


def choose_profile(appid):
    rows = []
    for path in sorted(profiles_dir(appid).glob("*.env")):
        env = parse_env(path)
        rows.extend([
            env.get("WAYLANDIE_STEAM_PROFILE_ID") or path.stem,
            env.get("WAYLANDIE_STEAM_PROFILE_LABEL") or path.stem,
            env.get("WAYLANDIE_STEAM_PROFILE_SUMMARY") or "",
        ])
    return zenity([
        "--list", "--title=Choose Profile", "--text=Pick the profile for the next launch",
        "--column=ID", "--column=Profile", "--column=What changes", "--width=980", "--height=470",
    ], "\n".join(rows) + "\n")


def capture_output(fn):
    import io
    old = sys.stdout
    buf = io.StringIO()
    sys.stdout = buf
    try:
        fn()
    finally:
        sys.stdout = old
    return buf.getvalue().strip()


def capture_status(appid):
    return capture_output(lambda: status(argparse.Namespace(appid=appid)))


def edit_active_env(appid):
    path = active_path(appid)
    if not path.exists():
        set_profile(appid, "turnip-current", quiet=True)
    edited = zenity(["--text-info", "--editable", f"--filename={path}", "--title=Edit Active Profile", "--width=980", "--height=620"])
    if edited is None:
        return
    path.write_text(edited.rstrip() + "\n", encoding="utf-8")
    if str(appid) == METRO_APPID:
        LEGACY_METRO_ROOT.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, LEGACY_METRO_ROOT / "active.env")
    zenity(["--info", "--title=Saved", f"--text=Saved {path}\n\nRestart the game for changes to take effect."])


def main():
    parser = argparse.ArgumentParser(description="Per-game Steam DXVK/FEX/Turnip profile manager")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("bootstrap").set_defaults(func=bootstrap)
    sub.add_parser("gui").set_defaults(func=gui)
    p = sub.add_parser("list-games")
    p.add_argument("--all", action="store_true", help="include Proton runtimes and redistributables")
    p.set_defaults(func=list_games)
    p = sub.add_parser("list-profiles")
    p.add_argument("appid", help="Steam appid, or all")
    p.set_defaults(func=list_profiles)
    p = sub.add_parser("set")
    p.add_argument("appid", help="Steam appid, or all")
    p.add_argument("profile")
    p.set_defaults(func=set_profile_cmd)
    p = sub.add_parser("status")
    p.add_argument("appid")
    p.set_defaults(func=status)
    p = sub.add_parser("launch")
    p.add_argument("appid")
    p.add_argument("--process", default="")
    p.add_argument("--timeout", type=int, default=120)
    p.set_defaults(func=launch)
    p = sub.add_parser("hook")
    p.add_argument("appid")
    p.set_defaults(func=hook)
    p = sub.add_parser("create-dxvk-profile")
    p.add_argument("appid")
    p.add_argument("slot")
    p.add_argument("--profile", default="")
    p.add_argument("--label", default="")
    p.add_argument("--summary", default="")
    p.add_argument("--activate", action="store_true")
    p.set_defaults(func=create_dxvk_profile)
    p = sub.add_parser("create-turnip-profile")
    p.add_argument("appid")
    p.add_argument("slot")
    p.add_argument("--profile", default="")
    p.add_argument("--label", default="")
    p.add_argument("--summary", default="")
    p.add_argument("--activate", action="store_true")
    p.set_defaults(func=create_turnip_profile)
    p = sub.add_parser("create-qcom-profile")
    p.add_argument("appid")
    p.add_argument("slot")
    p.add_argument("--profile", default="")
    p.add_argument("--label", default="")
    p.add_argument("--summary", default="")
    p.add_argument("--activate", action="store_true")
    p.set_defaults(func=create_qcom_profile)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
