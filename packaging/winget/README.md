# winget manifests

Source of truth for the AiCodeStation entry in the Windows Package Manager repository.
These files are copied into a fork of [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)
under `manifests/a/AiCodeStation/AiCodeStation/<version>/` and submitted as a pull request.

Once accepted, Windows users install with:

```powershell
winget install AiCodeStation.AiCodeStation
```

## Confirm before submitting

Two fields cannot be determined from the download URL alone. Getting `InstallerType` wrong is
the most common reason a submission fails validation, because winget derives the silent-install
switches from it.

**1. `InstallerType`** in `AiCodeStation.AiCodeStation.installer.yaml` is currently set to `nsis`.
Verify it against the real installer:

```powershell
$exe = "$env:TEMP\AiCodeStation-Setup-1.0.30.exe"
Invoke-WebRequest -Uri "https://acsdownloads.blob.core.windows.net/releases/1.0.30/AiCodeStation-Setup-1.0.30.exe" -OutFile $exe
Select-String -Path $exe -Pattern "Nullsoft|Inno Setup|WiX|Burn" -Encoding Byte -AllMatches |
  Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value -Unique
```

| Match | Set `InstallerType` to |
|---|---|
| `Nullsoft` | `nsis` |
| `Inno Setup` | `inno` |
| `WiX` or `Burn` | `burn` |
| nothing | `exe`, and add the silent switches your installer accepts |

**2. `Scope`** is set to `user`. If the installer writes to `Program Files` and asks for
elevation, change it to `machine`.

## Validate locally before opening the pull request

```powershell
winget validate --manifest packaging\winget\1.0.30
winget install --manifest packaging\winget\1.0.30
```

The first checks the schema. The second performs a real installation from the manifest, which
is what the reviewers run.

## Submitting

1. Fork `microsoft/winget-pkgs`
2. Copy this version folder to `manifests/a/AiCodeStation/AiCodeStation/1.0.30/`
3. Open a pull request. Automated validation runs first, then a human review
4. Expect a few days. Validation failures are reported as comments on the pull request

## On every new release

Copy the version folder, update `PackageVersion`, `InstallerUrl`, `InstallerSha256`, and
`ReleaseDate` in all three files, then submit again. The SHA-256 for each build is published on
<https://aicodestation.com/downloads/> and in the signed `SHA256SUMS.txt.asc`.
