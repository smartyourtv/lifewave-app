#!/usr/bin/env python3
"""Validate the Lifewave AI Windows packaging WITHOUT a Windows machine.

Adapted from the windows-health template validator for a FLUTTER
WINDOWS app (folder payload, not PyInstaller single-file):

  * app-config.json parses, has every required key, a fresh GUID, and
    its version matches pubspec.yaml in the Flutter project;
  * exe_name matches BINARY_NAME in app/windows/CMakeLists.txt
    (exe_name == "<BINARY_NAME>.exe");
  * naming follows the standing rule (``<App>-Setup.exe`` installer);
  * setup.iss carries the per-user contract (lowest privileges,
    {localappdata} install dir, Start Menu + desktop icons, uninstall,
    whole-folder source) and passes the Inno Setup 6 guard:
    PrivilegesRequiredOverridesAllowed, if present, may only be
    "commandline"/"dialog" (the value "no" is invalid and broke the
    windows-health build in CI on 2026-10-17);
  * build-windows.ps1 reads app-config.json and drives flutter + ISCC;
  * the GitHub Actions workflow parses as YAML (when PyYAML is
    present) and contains the required build steps.

Exit 0 = all checks passed (skips are reported, never hidden).

Usage: python packaging/validate_packaging.py [repo_root]
where repo_root is the lifewave folder (the one containing app/,
packaging/ and .github/).
"""

import json
import os
import re
import sys

REQUIRED_CONFIG_KEYS = [
    "app_id", "app_name", "display_name", "exe_name", "setup_name",
    "version", "publisher", "install_folder", "flutter_project_dir",
    "windows_release_dir",
]

GUID_RE = re.compile(
    r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1
                           else os.path.join(os.path.dirname(__file__),
                                             ".."))
    pkg = os.path.join(root, "packaging")
    results = []

    def check(name, ok, note=""):
        results.append((name, bool(ok), note))

    def skip(name, note):
        results.append((name, None, note))

    # --- config -----------------------------------------------------
    cfg = None
    try:
        with open(os.path.join(pkg, "app-config.json"),
                  encoding="utf-8") as fh:
            cfg = json.load(fh)
        check("app-config.json parses", True)
    except Exception as exc:  # noqa: BLE001
        check("app-config.json parses", False, str(exc))
    if cfg is None:
        return report(results)

    for key in REQUIRED_CONFIG_KEYS:
        check("config has %s" % key, bool(cfg.get(key)))
    check("config app_id is a GUID", bool(GUID_RE.match(
        str(cfg.get("app_id", "")))))
    check("exe_name ends .exe", str(cfg.get("exe_name", ""))
          .endswith(".exe"))
    check("setup_name is <App>-Setup.exe",
          str(cfg.get("setup_name", "")).endswith("-Setup.exe"))
    check("setup_name is exactly Lifewave-Setup.exe",
          cfg.get("setup_name") == "Lifewave-Setup.exe")
    check("exe and setup names differ",
          cfg.get("exe_name") != cfg.get("setup_name"))

    # --- config vs Flutter project ----------------------------------
    app_dir = os.path.join(root, cfg.get("flutter_project_dir", "app"))
    pubspec_path = os.path.join(app_dir, "pubspec.yaml")
    pub_version = None
    if os.path.exists(pubspec_path):
        with open(pubspec_path, encoding="utf-8") as fh:
            m = re.search(r"(?m)^version:\s*([0-9][0-9A-Za-z.+-]*)",
                          fh.read())
        if m:
            pub_version = m.group(1).split("+")[0]
    check("pubspec.yaml found with a version", pub_version is not None)
    check("config version == pubspec version",
          pub_version is not None and pub_version == cfg.get("version"),
          "pubspec=%s config=%s" % (pub_version, cfg.get("version")))

    cmake_path = os.path.join(app_dir, "windows", "CMakeLists.txt")
    binary_name = None
    if os.path.exists(cmake_path):
        with open(cmake_path, encoding="utf-8") as fh:
            m = re.search(r'set\(BINARY_NAME\s+"([^"]+)"\)', fh.read())
        if m:
            binary_name = m.group(1)
    check("windows/CMakeLists.txt BINARY_NAME found",
          binary_name is not None)
    check("exe_name == BINARY_NAME + .exe",
          binary_name is not None
          and cfg.get("exe_name") == binary_name + ".exe",
          "BINARY_NAME=%s exe_name=%s" % (binary_name,
                                          cfg.get("exe_name")))
    check("windows_release_dir ends with runner/Release",
          str(cfg.get("windows_release_dir", "")).replace("\\", "/")
          .endswith("runner/Release"))

    # --- Inno Setup script -------------------------------------------
    iss_path = os.path.join(pkg, "setup.iss")
    with open(iss_path, encoding="utf-8") as fh:
        iss = fh.read()
    for token, label in (
            ("PrivilegesRequired=lowest", "per-user (no admin) install"),
            ("{localappdata}\\Programs", "installs under LocalAppData"),
            ("[Icons]", "shortcut section present"),
            ("{group}", "Start Menu shortcut"),
            ("{autodesktop}", "desktop shortcut"),
            ("UninstallDisplayName", "uninstaller in Settings > Apps"),
            ("OutputBaseFilename", "named installer output"),
            ("recursesubdirs", "whole Flutter folder payload")):
        check("setup.iss: %s" % label, token in iss)
    check("setup.iss: values are /D-overridable defines",
          iss.count("#ifndef") >= 7 and iss.count("#define") >= 7)
    check("setup.iss: default exe matches config exe_name",
          ('MyExeName "%s"' % cfg.get("exe_name")) in iss)
    check("setup.iss: default GUID matches config app_id",
          str(cfg.get("app_id", "")) in iss)
    # Inno Setup 6 guard (copied from the windows-health validator):
    # any OverridesAllowed value other than "commandline"/"dialog"
    # fails compilation — local validation missed it once, in CI.
    _ovr = re.search(
        r"(?m)^PrivilegesRequiredOverridesAllowed\s*=\s*(\S.*)$", iss)
    check("setup.iss: PrivilegesRequiredOverridesAllowed value is valid",
          _ovr is None or
          set(_ovr.group(1).lower().replace(",", " ").split()) <=
          {"commandline", "dialog"})
    check("setup.iss: no PrivilegesRequiredOverridesAllowed=no (invalid)",
          "PrivilegesRequiredOverridesAllowed=no" not in iss)

    # --- PowerShell build script -------------------------------------
    ps1_path = os.path.join(pkg, "build-windows.ps1")
    check("build-windows.ps1 exists", os.path.exists(ps1_path))
    if os.path.exists(ps1_path):
        with open(ps1_path, encoding="utf-8") as fh:
            ps1 = fh.read()
        check("build script reads app-config.json",
              "app-config.json" in ps1)
        check("build script builds the Flutter Windows app",
              "flutter build windows --release" in ps1)
        check("build script compiles with ISCC", "ISCC" in ps1)
        check("build script verifies the Release folder",
              "flutter_windows.dll" in ps1)

    # --- GitHub Actions workflow --------------------------------------
    wf = os.path.join(root, ".github", "workflows", "build-windows.yml")
    check("workflow exists", os.path.exists(wf))
    if os.path.exists(wf):
        with open(wf, encoding="utf-8") as fh:
            wf_text = fh.read()
        for token, label in (
                ("windows-latest", "runs on a Windows runner"),
                ("flutter-action", "sets up Flutter"),
                ("3.24.5", "Flutter pinned to 3.24.5"),
                ("flutter build apk --release", "builds the APK"),
                ("flutter build windows --release",
                 "builds the Windows app"),
                ("build-windows.ps1", "Inno compile via packaging script"),
                ("upload-artifact", "uploads artifacts"),
                ("Lifewave-latest.apk", "stable APK asset name"),
                ("Lifewave-Setup.exe", "stable Setup asset name"),
                ("workflow_dispatch", "manually dispatchable"),
                ("release_tag", "dispatch can publish a Release")):
            check("workflow: %s" % label, token in wf_text)
        try:
            import yaml  # optional; not a build dependency
            yaml.safe_load(wf_text)
            check("workflow is valid YAML", True)
        except ImportError:
            skip("workflow is valid YAML", "PyYAML not installed here")
        except Exception as exc:  # noqa: BLE001
            check("workflow is valid YAML", False, str(exc))

    return report(results)


def report(results):
    failed = 0
    for name, ok, note in results:
        if ok is None:
            print("  [SKIP] %s%s" % (name, (" - " + note) if note else ""))
        else:
            print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name,
                                   (" - " + note) if note else ""))
            failed += 0 if ok else 1
    print("Packaging validation: %d passed, %d failed, %d skipped"
          % (sum(1 for _, ok, _ in results if ok is True), failed,
             sum(1 for _, ok, _ in results if ok is None)))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
