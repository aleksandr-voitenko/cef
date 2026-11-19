param(
  [Parameter(Mandatory)][string]$WorkRoot,
  [string]$PackageName = 'cef_binary_7871_windows_x64_v1',
  [string]$SevenZip = '7z',
  [string]$LibExe = 'lib.exe',
  [string]$Symchk = 'symchk.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PackageName -notmatch '^[A-Za-z0-9_-]+$') { throw 'PackageName must contain only letters, numbers, underscores, and hyphens.' }
$root = [IO.Path]::GetFullPath($WorkRoot)
$src = Join-Path $root 'download/chromium/src'
$out = Join-Path $src 'out/Release_GN_x64'
$cef = Join-Path $src 'cef'
$stageRoot = Join-Path $root 'staging'
$stage = Join-Path $stageRoot $PackageName
$symbols = Join-Path $stageRoot "${PackageName}_release_symbols"
$package = Join-Path (Join-Path $root 'package') $PackageName
$artifacts = Join-Path $root 'artifacts'
$zip = Join-Path $artifacts "$PackageName.zip"
$symbols7z = Join-Path $artifacts "${PackageName}_symbols.7z"
$inventory = Join-Path $artifacts "$PackageName.files.csv"
function Require-File([string]$path) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing: $path" } }
function Run([string]$file, [string[]]$arguments) {
  & $file @arguments
  if ($LASTEXITCODE -ne 0) { throw "$file failed with exit code $LASTEXITCODE" }
}
foreach ($path in @($stage, $symbols, $package, $zip, $symbols7z, $inventory)) {
  if (Test-Path -LiteralPath $path) { throw "Output already exists: $path (use a new PackageName or move it aside)" }
}
Require-File (Join-Path $cef 'tools/make_distrib.py')
Require-File (Join-Path $out 'obj/cef/libcef_dll_wrapper.ninja')
Require-File (Join-Path $out 'args.gn')
$gnArgs = Get-Content -LiteralPath (Join-Path $out 'args.gn') -Raw
foreach ($setting in @('is_debug=false','is_official_build=false','symbol_level=1','proprietary_codecs=true','ffmpeg_branding="Chrome"','dcheck_always_on=false','dcheck_is_configurable=false','target_cpu="x64"')) {
  if (-not $gnArgs.Contains($setting)) { throw "GN args do not include $setting" }
}
$expected = @{ cef='abc1ece6a66997894c4c953ed24937603fbd74b4'; chromium='e7b998fb3cd79ff00dbc0067421dc6ec118892a8'; depot='f4fadaf6a5ba1bced9d3d9021060667b563bf583' }
foreach ($entry in @(@($cef,$expected.cef),@($src,$expected.chromium),@((Join-Path $root 'depot_tools'),$expected.depot))) {
  $actual = (& git -C $entry[0] rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or $actual -ne $entry[1]) { throw "Revision mismatch: $($entry[0])" }
}
$python = Join-Path $root 'depot_tools/python3.bat'
Require-File $python
$env:PATH = "$(Join-Path $root 'depot_tools');$env:PATH"
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
$env:DEPOT_TOOLS_UPDATE = '0'
New-Item -ItemType Directory -Path $stageRoot,$artifacts,(Split-Path $package) -Force | Out-Null
Push-Location $cef
try { Run $python @('tools/make_distrib.py','--output-dir',$stageRoot,'--distrib-subdir',$PackageName,'--ninja-build','--x64-build','--allow-partial','--no-docs','--no-archive','--no-format') }
finally { Pop-Location }
if (-not (Test-Path -LiteralPath $stage -PathType Container)) { throw 'make_distrib did not create the distribution' }
if (-not (Test-Path -LiteralPath $symbols -PathType Container)) { throw 'make_distrib did not create Release symbols' }

# The GN archive uses /llvmlibthin. Rebuild a self-contained archive from its exact target object list.
$manifest = Get-Content -LiteralPath (Join-Path $out 'obj/cef/libcef_dll_wrapper.ninja')
if (-not @($manifest | Where-Object { $_ -match '^cflags = .* /MT(?: |$)' })) { throw 'GN wrapper target does not compile with /MT' }
$target = @($manifest | Where-Object { $_ -match '^build obj/cef/libcef_dll_wrapper\.lib: alink ' })
if ($target.Count -ne 1) { throw 'Expected exactly one GN wrapper archive target' }
$objectPart = (($target[0] -split '\s+\|\s+',2)[0] -replace '^build obj/cef/libcef_dll_wrapper\.lib: alink ','')
$objects = @($objectPart -split '\s+' | Where-Object { $_ -match '^obj/cef/libcef_dll_wrapper/.+\.obj$' })
if ($objects.Count -lt 100 -or $objects.Count -ne @($objects | Select-Object -Unique).Count) { throw "Unexpected wrapper object list: $($objects.Count)" }
foreach ($object in $objects) { Require-File (Join-Path $out $object) }
$wrapperDir = Join-Path $package 'build/libcef_dll_wrapper/Release'
New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null
$wrapper = Join-Path $wrapperDir 'libcef_dll_wrapper.lib'
$response = Join-Path $package 'wrapper-objects.rsp'
try {
  [IO.File]::WriteAllLines($response, $objects, [Text.Encoding]::ASCII)
  Push-Location $out
  try { Run $LibExe @('/NOLOGO',"/OUT:$wrapper","@$response") }
  finally { Pop-Location }
} finally { Remove-Item -LiteralPath $response -ErrorAction SilentlyContinue }
Require-File $wrapper
$header = New-Object byte[] 8
$stream = [IO.File]::OpenRead($wrapper)
try { [void]$stream.Read($header,0,8) } finally { $stream.Dispose() }
if ([Text.Encoding]::ASCII.GetString($header) -ne "!<arch>`n") { throw 'Wrapper is not a normal COFF archive' }
$members = @(& $LibExe /NOLOGO /LIST $wrapper)
if ($LASTEXITCODE -ne 0 -or $members.Count -ne $objects.Count) { throw 'Wrapper archive member count differs from GN manifest' }

& robocopy $stage $package /E /XD (Join-Path $stage 'build') /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
$tests = Join-Path $package 'tests'
if (Test-Path -LiteralPath $tests) { Rename-Item -LiteralPath $tests -NewName 'tests.disabled' }
$release = Join-Path $package 'Release'
foreach ($required in @('bootstrap.exe','bootstrapc.exe','chrome_elf.dll','libcef.dll','libcef.lib')) {
  Require-File (Join-Path $release $required)
}
$pdbs = @(Get-ChildItem -LiteralPath $symbols -Filter '*.pdb' -File)
if ($pdbs.Count -lt 9) { throw "Expected at least nine Release PDBs; got $($pdbs.Count)" }
foreach ($pdb in $pdbs) {
  $binary = Join-Path $release ($pdb.Name -replace '\.pdb$','')
  Require-File $binary
  Copy-Item -LiteralPath $pdb.FullName -Destination (Join-Path $release $pdb.Name)
}
Require-File (Join-Path $release 'libcef.dll.pdb')
$symchkCommand = Get-Command $Symchk -ErrorAction SilentlyContinue
if (-not $symchkCommand) { throw 'symchk.exe is required to verify binary/PDB identity; pass -Symchk with its full path.' }
foreach ($pdb in $pdbs) { Run $symchkCommand.Source @('/q',(Join-Path $release ($pdb.Name -replace '\.pdb$','')),'/s',$release) }

$files = @(Get-ChildItem -LiteralPath $package -File -Recurse | Sort-Object FullName)
$rows = foreach ($file in $files) {
  [pscustomobject]@{ Path = $file.FullName.Substring($package.Length + 1).Replace('\','/'); Bytes = $file.Length; SHA256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
}
$rows | Export-Csv -LiteralPath $inventory -NoTypeInformation
Push-Location $package
try { Run $SevenZip @('a','-tzip','-mx=7',$zip,'.\*') }
finally { Pop-Location }
Push-Location $symbols
try { Run $SevenZip @('a','-t7z','-mx=7',$symbols7z,'.\*') }
finally { Pop-Location }
Run $SevenZip @('t',$zip)
Run $SevenZip @('t',$symbols7z)
$zipList = @(& $SevenZip l -slt $zip)
if ($LASTEXITCODE -ne 0) { throw 'Could not list runtime ZIP' }
$archivedFiles = @($zipList | Where-Object { $_ -eq 'Folder = -' }).Count
if ($archivedFiles -ne $rows.Count) { throw "ZIP has $archivedFiles files; inventory has $($rows.Count)" }
foreach ($artifact in @($zip,$symbols7z,$inventory)) {
  $item = Get-Item -LiteralPath $artifact
  Write-Host ("{0} {1} {2}" -f $item.Name,$item.Length,(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash)
}
