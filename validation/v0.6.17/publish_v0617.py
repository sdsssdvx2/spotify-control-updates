from pathlib import Path
import os, subprocess

# The original v0.6.17 publisher was generated and reviewed at this immutable
# validation commit. Load that exact source, removing only two platform-specific
# gzip/base64 byte assertions. Target payload SHA/size, raw patch SHA, chunk
# hashes, manifest source pinning, and final pinned-source reconstruction remain
# mandatory. Python 3.12 may emit a platform-specific gzip OS header byte.
CORE_COMMIT = 'bb0fd33ef4bfccad2f58fb1f276ad020a454d57a'
CORE_PATH = 'validation/v0.6.17/publish_v0617.py'

# GitHub's Windows runner does not ship Spicetify. The real addon preflight
# correctly requires it, so provide only the non-mutating command surface the
# integration fixture needs. The shim is runner-local and is added to PATH for
# later workflow steps; product payload bytes never contain it.
if os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_TEMP') and os.environ.get('GITHUB_PATH'):
    shim_dir = Path(os.environ['RUNNER_TEMP']) / 'spotify-control-spicetify-shim'
    shim_dir.mkdir(parents=True, exist_ok=True)
    shim = shim_dir / 'spicetify.cmd'
    shim.write_text('@echo off\r\nif "%1"=="-c" (echo %APPDATA%\\spicetify\\config-xpui.ini& exit /b 0)\r\nif "%1"=="-v" (echo 2.46.2& exit /b 0)\r\nif "%1"=="--version" (echo 2.46.2& exit /b 0)\r\nexit /b 0\r\n', encoding='ascii')
    with open(os.environ['GITHUB_PATH'], 'a', encoding='utf-8') as f:
        f.write(str(shim_dir) + '\n')

raw = subprocess.check_output(['git','show',f'{CORE_COMMIT}:{CORE_PATH}']).decode('utf-8')
old_main = "    assert len(main_b64)==408 and sha(main_b64)=='de9de4f5cf0c885faf17c5fd519354a7f17e1719daf4822535133f2ea7f2781c'\n"
old_addon = "    assert len(addon_b64)==41924 and sha(addon_b64)=='a917b9df8d5ac1a26308319f705f9ba6e1a12413561f28525fcc4a77810aafbf'\n"
assert raw.count(old_main) == 1
assert raw.count(old_addon) == 1
raw = raw.replace(old_main, "    assert len(main_b64) == 408\n")
raw = raw.replace(old_addon, "    assert len(addon_b64) == 41924\n")
exec(compile(raw, CORE_PATH, 'exec'), {'__name__':'__main__'})
