#Requires -Version 2.0

# Add custom type and format data
split-path $MyInvocation.MyCommand.Path | foreach-object {
    if (($path = join-path $_ My.types.ps1xml) -and (test-path $path)) { $path | update-typedata }
    if (($path = join-path $_ My.format.ps1xml) -and (test-path $path)) { $path | update-formatdata }
}

# Aliases
if (test-path alias:\curl) {
    remove-item alias:\curl
}

if (-not [Environment]::Is64BitProcess) {
    new-alias curl "${env:SystemRoot}\SysNative\curl.exe"
}

# Set up drive roots for convenience
if ((test-path ~\Source\Repos) -and -not (test-path Repos:\)) {
    $null = new-psdrive -name Repos -psprovider FileSystem -root ~\Source\Repos
}

# Preferences
[bool] $global:PromptExecutionTimePreference = $true

# Change the defualt prompt.
function global:prompt
{
    $ESC    = [char]0x1b
    $SEP    = [char]0xe0b0
    $GT     = [char]0xe0b1
    $BRANCH = [char]0xe0a0

    $BLUE   = 31
    $GRAY2  = 236
    $GRAY4  = 240
    # $GRAY9  = 250
    # $GRAY10 = 252
    $PURPLE = 55
    $RED    = 1
    $WHITE  = 231

    $script:prevstr, $script:prevfg, $script:prevbg = $null, 0, 0
    @(
        {if ($PSDebugContext) {'DBG', $WHITE, $RED}}
        {'PS', $WHITE, $PURPLE}
        {if ($PromptExecutionTimePreference -and ($h = get-history -count 1)) {
            $h.ExecutionTime.ToString('hh\:mm\:ss\.fff'), $WHITE, $BLUE
        }}
        {$PWD, $WHITE, $GRAY4}
        {"`n"}
        {if ($repo = &$Profile_GetBranch -and $repo.Branch) {("$BRANCH " + $repo.Branch), $WHITE, $GRAY2}}
        {('+' * $global:ExecutionContext.SessionState.Path.LocationStack($null).Count), $WHITE, $GRAY4}
        {("$GT" * $NestedPromptLevel), $WHITE, $GRAY4}
    ) | foreach-object -process {
        $str, $fg, $bg = $_.Invoke()

        if (!$str) {
            return
        }

        if ($str -eq "`n") {
            " $ESC[0;38;5;${prevbg}m$SEP$ESC[0m`n"
            $script:prevstr, $script:prevfg, $script:prevbg = $null, 0, $GRAY4
            return
        } elseif ($prevstr) {
            " $ESC[0;38;5;$prevbg;48;5;${bg}m$SEP "
        }

        "$ESC[0;38;5;$fg;48;5;${bg}m$str"
        $script:prevstr, $script:prevfg, $script:prevbg = $str, $fg, $bg
    } -end {
        if ($prevstr) {
            ' '
        }

        "$ESC[0;38;5;${prevbg}m$SEP$ESC[0m "
    } | join-string -separator ''
}

# Increase history count.
$global:MaximumHistoryCount = 100

# Private functions

if (-not (test-path variable:\Profile_GetBranch)) {
new-variable Profile_GetBranch -option Constant -visibility Private -value {

    if ($dir = &$Profile_GetRepo) {

        $repo = new-object PSObject -property @{ 'Branch' = $null; 'SCM' = $dir.SCM }

        switch ($dir.SCM) {
            'Git' {
                $branch = if (($path = join-path $dir 'HEAD') -and (test-path $path)) {
                    resolve-path $path | get-content
                }

                if ($branch -match 'ref: refs/heads/(?<b>[\w_\.\-/]+)') {
                    $branch = $Matches['b']

                } elseif ($branch.length -ge 7) {
                    $branch = 'hash: ' + $branch.Substring(0, 7)

                }

                $repo.Branch = $branch
            }

            'Hg' {
                $branch = if (($path = join-path $dir 'branch') -and (test-path $path)) {
                    resolve-path $path | get-content
                }

                $repo.Branch = $branch
            }
        }

        $repo
    }
}
}

if (-not (test-path variable:\Profile_GetRepo)) {
new-variable Profile_GetRepo -option Constant -visibility Private -value {

    if ((test-path env:GIT_DIR) -and (test-path $env:GIT_DIR -pathtype 'Container')) {
        return (resolve-path $env:GIT_DIR | add-member -type NoteProperty -name 'SCM' -value 'Git' -passthru)
    }

    &$Profile_SearchParent {

        if (($gd = join-path $dir '.git') -and (test-path $gd -pathtype 'Container')) {
            # check if git repository
            return (resolve-path $gd | add-member -type NoteProperty -name 'SCM' -value 'Git' -passthru)

        } elseif (test-path $gd -pathtype 'Leaf') {
            # check if git submodule
            if ((resolve-path $gd | get-content) -match 'gitdir: (?<d>.+)') {
                # join-path simply concatenates both paths so use path.combine if gitdir is absolute
                if (($gd = [io.path]::combine($dir, $Matches['d'])) -and (test-path $gd -pathtype 'Container')) {
                    return (resolve-path $gd | add-member -type NoteProperty -name 'SCM' -value 'Git' -passthru)
                }
            }

        } elseif (($gd = join-path $dir '.hg') -and (test-path $gd)) {
            # check if hg repository
            return (resolve-path $gd | add-member -type NoteProperty -name 'SCM' -value 'Hg' -passthru)
        }
    }
}
}

if (-not (test-path variable:\Profile_SearchParent)) {
new-variable Profile_SearchParent -option Constant -visibility Private -value {

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true, Position=0)]
        [scriptblock] $Filter
    )

    $dir = resolve-path .

    while ($dir) {

        # pass the path to the filter script
        if ($out = &$Filter $dir) {
            return $out
        }

        $dir = if (($parent = split-path $dir -parent) -and (test-path $parent)) {
            resolve-path $parent
        }
    }
}
}

# Useful variables.

if (-not (test-path variable:\Git)) {
new-object PSObject | `
    add-member -name Branch -type ScriptProperty -value { (&$Profile_GetBranch).Branch } -passthru | `
    add-member -name Root -type ScriptProperty -value { (&$Profile_GetRepo).Path } -passthru | `
    new-variable -name Git -option Constant -scope Global
}

# Chocolatey profile

$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

# Parameter completions

Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
     param($commandName, $wordToComplete, $cursorPosition)
     dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
     }
 }

# vim: set et sts=4 sw=4 ts=8:
