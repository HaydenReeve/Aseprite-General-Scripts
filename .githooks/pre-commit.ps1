Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8NoBom
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom

function Get-RepoPathExtension {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $leafName = (($Path -replace '\\', '/') -split '/')[-1]
    if ([string]::IsNullOrEmpty($leafName)) {
        return ''
    }

    if ($leafName.StartsWith('.') -and $leafName.IndexOf('.', 1) -lt 0) {
        return $leafName.ToLowerInvariant()
    }

    $lastDot = $leafName.LastIndexOf('.')
    if ($lastDot -le 0) {
        return ''
    }

    return $leafName.Substring($lastDot).ToLowerInvariant()
}

$stagedFiles = @(
    & git -c core.quotepath=false diff --cached --name-only --diff-filter=ACMR
)

if ($LASTEXITCODE -ne 0 -or $stagedFiles.Count -eq 0) {
    exit 0
}

$pathRules = @(
    @{
        Name = 'settings-profiles local device data'
        Pattern = '^(?i)\.obsidian/plugins/settings-profiles/data\.json$'
    },
    @{
        Name = 'historical Workday source folders'
        Pattern = '^(?i)(Verbrec/)?Timesheets/Sources/'
    },
    @{
        Name = 'Workday PDF exports'
        Pattern = '(?i)Time_Calendar_for_.*\.pdf$'
    },
    @{
        Name = 'saved Workday HTML exports'
        Pattern = '(?i)Enter Time by Type - Workday(?:\.html|_files/.*)$'
    }
)

$contentRules = @(
    @{
        Name = 'user-specific Windows profile path'
        Pattern = 'C:\\Users\\[^\\\s''"`]+'
    },
    @{
        Name = 'machine-specific vault path'
        Pattern = 'D:\\Obsidian\\'
    },
    @{
        Name = 'old OneDrive organisation path'
        Pattern = ('One' + 'Drive - [A-Za-z0-9][A-Za-z0-9 .&()_-]{1,}')
    },
    @{
        Name = 'legacy named vault path'
        Pattern = 'OneDrive\\Personal Obsidian Vault|Downloads\\Obsidian Verbrec Vault'
    },
    @{
        Name = 'GitHub personal access token'
        Pattern = 'github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}'
    },
    @{
        Name = 'AWS access key'
        Pattern = 'AKIA[0-9A-Z]{16}'
    },
    @{
        Name = 'Slack token'
        Pattern = 'xox[baprs]-[A-Za-z0-9-]{10,}'
    },
    @{
        Name = 'private key block'
        Pattern = '-----BEGIN (?:RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY-----'
    }
)

$textExtensions = @(
    '.md', '.txt', '.json', '.js', '.css', '.html', '.htm', '.ps1',
    '.cmd', '.lua', '.toml', '.ini', '.yml', '.yaml', '.gitignore',
    '.gitattributes'
)

$issues = New-Object System.Collections.Generic.List[string]

foreach ($file in $stagedFiles) {
    if ([string]::IsNullOrWhiteSpace($file)) {
        continue
    }

    $normalisedPath = $file.Replace('\', '/')

    foreach ($rule in $pathRules) {
        if ($normalisedPath -match $rule.Pattern) {
            $issues.Add("$normalisedPath -> blocked path: $($rule.Name)")
        }
    }

    $extension = Get-RepoPathExtension -Path $normalisedPath
    if ($textExtensions -notcontains $extension) {
        continue
    }

    $stagedContent = & git show ":$normalisedPath" 2>$null
    if ($LASTEXITCODE -ne 0) {
        continue
    }

    $text = ($stagedContent -join "`n")

    foreach ($rule in $contentRules) {
        if ($text -match $rule.Pattern) {
            $issues.Add("$normalisedPath -> blocked content: $($rule.Name)")
        }
    }
}

if ($issues.Count -gt 0) {
    Write-Host 'Pre-commit sanitisation check failed.' -ForegroundColor Red
    Write-Host 'Remove or generalise the following staged content before committing:' -ForegroundColor Yellow
    foreach ($issue in $issues | Sort-Object -Unique) {
        Write-Host " - $issue"
    }
    exit 1
}

exit 0
