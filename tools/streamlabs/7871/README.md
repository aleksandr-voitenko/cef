# CEF 7871 Windows x64 build

Builds the OBS Project CEF 7871 branch with VS 2026 and packages a Release runtime with matching PDBs and a self-contained `/MT` wrapper. The source pins match the earlier VS 2022 [v1 build](BUILD-PROVENANCE-v1.md); the completed VS 2026 package is recorded in [v2 provenance](BUILD-PROVENANCE-v2.md). A new build gets new hashes; do not reuse a recorded artifact hash.

| Repository | Revision |
| --- | --- |
| `https://github.com/obsproject/cef.git` (`7871_obsproject`) | `abc1ece6a66997894c4c953ed24937603fbd74b4` |
| Chromium `150.0.7871.287` | `e7b998fb3cd79ff00dbc0067421dc6ec118892a8` |
| depot_tools | `f4fadaf6a5ba1bced9d3d9021060667b563bf583` |

Use Windows x64, VS 2026 C++ tools, a suitable Windows SDK with `symchk.exe`, Git with long paths enabled, Python/depot_tools prerequisites, 7-Zip, and ample disk space. Install depot_tools at `<work>\depot_tools` and checkout its pin; clone CEF at `<work>\cef` and checkout its pin. The script syncs Chromium from the GitHub mirror and checks all three resulting HEADs. Set `VSDEVCMD` if VS is installed in a different edition/location, `CEF_JOBS` to cap parallel compilation, and `GIT_USR_BIN` if Git's Unix tools are not on `PATH`. The build and packaging scripts never change an existing pin themselves.

```cmd
set VSDEVCMD=C:\path\to\VS2026\Common7\Tools\VsDevCmd.bat
set CEF_JOBS=8
build-win-x64.cmd D:\cef-work
```

The build runs `automate-git.py`, CEF's GN hook, and `autoninja` for `cefclient bootstrap bootstrapc` in `Release_GN_x64`. To switch an existing pinned checkout to VS 2026, run `build-win-x64.cmd D:\cef-work --reconfigure`; it regenerates GN files without syncing sources. For an interrupted build, run `build-win-x64.cmd D:\cef-work --resume`. Generated GN args must include Release, `symbol_level=1`, `proprietary_codecs=true`, `ffmpeg_branding="Chrome"`, disabled Release DCHECKs, and x64; the packaging script checks `args.gn` before doing any work.

From a VS 2026 x64 developer command prompt with PowerShell 7, package after a successful build. OBS derives the runtime archive name from `cef_binary_VERSION_windows_ARCH_vREVISION.zip`; set the preset's Windows x64 revision to `2` for the example below.

```powershell
pwsh -NoProfile -File .\package-win-x64.ps1 -WorkRoot D:\cef-work -PackageName cef_binary_7871_windows_x64_v2
```

The packaging script calls `make_distrib.py`, reads the wrapper target's object list from GN's Ninja manifest, builds a normal COFF library with `lib.exe`, copies the distribution, embeds the Release PDBs, and creates a runtime ZIP, symbols 7z, and SHA-256 CSV inventory in `<work>\artifacts`. It checks required launch/runtime files, `/MT` wrapper compilation, normal archive format and member count, binary/PDB identity with `symchk.exe`, archive integrity and file count. Pass `-Symchk` with a full path if the SDK tool is not on `PATH`. Outputs must have a fresh package name; the script stops if any output path already exists.

The original local build needed host-specific accommodations for denied Python multiprocessing pipes, esbuild execution, AppContainer ACL stamping, and depot_tools vpython storage. They are deliberately not carried as patches: the esbuild and ACL changes were local workarounds without a portable safety proof. On a similarly restricted host, resolve and review those issues separately before building. A sandboxed CEF child-process smoke test also needs a normal Windows host and the M138+ bootstrap integration in the consuming application; archive checks alone do not establish runtime sandbox support.
