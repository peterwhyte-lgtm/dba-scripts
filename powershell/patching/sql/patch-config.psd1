# SQL Server Auto-Patch Configuration
#
# Versions and download URLs must be kept up to date manually.
# Reference: https://learn.microsoft.com/en-us/troubleshooting/sql/releases/download-and-install-latest-updates
#
# To find the direct download URL for a CU:
#   1. Open the link above and find your SQL version
#   2. Click the KB article for the CU you want
#   3. Right-click the download button → Copy link
#   4. Paste into the Url field below

@{
    # ── Servers ───────────────────────────────────────────────────────────────
    # One or more hostnames / FQDNs. Use '.' or 'localhost' for the local machine.
    # Can be overridden at runtime: .\Invoke-SqlPatch.ps1 -Server SQL01,SQL02
    Servers = @('localhost')

    # ── Patch download folder ─────────────────────────────────────────────────
    # Root on the machine running this script. Installers are also copied here
    # on remote servers (via admin share: \\server\D$\...).
    # Folder layout: {PatchRoot}\{SqlVersion}\{CU}_{KB}\{FileName}
    # Override at runtime: .\Invoke-SqlPatch.ps1 -PatchRoot C:\Patches
    PatchRoot = 'D:\SQLPatches'

    # ── Per-version CU definitions ────────────────────────────────────────────
    # MajorVersion : SQL Server major build number (13=2016, 14=2017, 15=2019, 16=2022, 17=2025)
    # CU           : label shown in status output (e.g. 'CU27', 'SP3CU17')
    # KB           : Knowledge Base article number
    # TargetVersion: ProductVersion the patch upgrades TO — used for before/after comparison
    # Url          : direct .exe download link (paste from the Microsoft page above)
    # FileName     : installer filename saved to PatchRoot
    Patches = @{

        SQL2016 = @{
            MajorVersion  = 13
            CU            = 'SP3AZ'
            KB            = 'KB5089270'
            TargetVersion = '13.0.7085.1'
            Url           = 'https://download.microsoft.com/download/f9014a03-feca-41c1-bc64-fb801e0e9799/SQLServer2016-KB5089270-x64.exe'
            FileName      = 'SQLServer2016-KB5089270-x64.exe'
        }

        SQL2017 = @{
            MajorVersion  = 14
            CU            = 'CU31'
            KB            = 'KB5050533'
            TargetVersion = '14.0.3456.2'
            Url           = 'https://download.microsoft.com/download/c/4/f/c4f908c9-98ed-4e5f-88d5-7d6a5004aebd/SQLServer2017-KB5050533-x64.exe'
            FileName      = 'SQLServer2017-KB5050533-x64.exe'
        }

        SQL2019 = @{
            MajorVersion  = 15
            CU            = 'CU32'
            KB            = 'KB5054833'
            TargetVersion = '15.0.4430.1'
            Url           = 'https://download.microsoft.com/download/6/e/7/6e72dddf-dfa4-4889-bc3d-e5d3a0fd11ce/SQLServer2019-KB5054833-x64.exe'
            FileName      = 'SQLServer2019-KB5054833-x64.exe'
        }

        SQL2022 = @{
            MajorVersion  = 16
            CU            = 'CU26'
            KB            = 'KB5093420'
            TargetVersion = '16.0.4265.3'
            # Direct exe URL not published on the KB page; download via
            # https://support.microsoft.com/help/5093420 (or the Update Catalog) into
            # the patch folder and the script picks the file up by name.
            Url           = ''
            FileName      = 'SQLServer2022-KB5093420-x64.exe'
        }

        SQL2025 = @{
            MajorVersion  = 17
            CU            = 'CU8'
            KB            = 'KB5104822'
            TargetVersion = '17.0.4075.5'
            # Direct exe URL not published on the KB page; download via
            # https://support.microsoft.com/help/5104822 (or the Update Catalog) into
            # the patch folder and the script picks the file up by name.
            Url           = ''
            FileName      = 'SQLServer2025-KB5104822-x64.exe'
        }
    }
}
