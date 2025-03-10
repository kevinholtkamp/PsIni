[CmdletBinding()]
param()

$DebugPreference = "SilentlyContinue"
$WarningPreference = "Continue"
if ($PSBoundParameters.ContainsKey('Verbose')) {
    $VerbosePreference = "Continue"
}

if (!($env:releasePath)) {
    $releasePath = "$BuildRoot\Release"
}
else {
    $releasePath = $env:releasePath
}
$env:PSModulePath = "$($env:PSModulePath);$releasePath"

Import-Module BuildHelpers

# Ensure Invoke-Build works in the most strict mode.
Set-StrictMode -Version Latest

# region debug information
Task ShowDebug {
    Write-Build Gray
    Write-Build Gray ('Project name:               {0}' -f $env:APPVEYOR_PROJECT_NAME)
    Write-Build Gray ('Project root:               {0}' -f $env:APPVEYOR_BUILD_FOLDER)
    Write-Build Gray ('Repo name:                  {0}' -f $env:APPVEYOR_REPO_NAME)
    Write-Build Gray ('Branch:                     {0}' -f $env:APPVEYOR_REPO_BRANCH)
    Write-Build Gray ('Commit:                     {0}' -f $env:APPVEYOR_REPO_COMMIT)
    Write-Build Gray ('  - Author:                 {0}' -f $env:APPVEYOR_REPO_COMMIT_AUTHOR)
    Write-Build Gray ('  - Time:                   {0}' -f $env:APPVEYOR_REPO_COMMIT_TIMESTAMP)
    Write-Build Gray ('  - Message:                {0}' -f $env:APPVEYOR_REPO_COMMIT_MESSAGE)
    Write-Build Gray ('  - Extended message:       {0}' -f $env:APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED)
    Write-Build Gray ('Pull request number:        {0}' -f $env:APPVEYOR_PULL_REQUEST_NUMBER)
    Write-Build Gray ('Pull request title:         {0}' -f $env:APPVEYOR_PULL_REQUEST_TITLE)
    Write-Build Gray ('AppVeyor build ID:          {0}' -f $env:APPVEYOR_BUILD_ID)
    Write-Build Gray ('AppVeyor build number:      {0}' -f $env:APPVEYOR_BUILD_NUMBER)
    Write-Build Gray ('AppVeyor build version:     {0}' -f $env:APPVEYOR_BUILD_VERSION)
    Write-Build Gray ('AppVeyor job ID:            {0}' -f $env:APPVEYOR_JOB_ID)
    Write-Build Gray ('Build triggered from tag?   {0}' -f $env:APPVEYOR_REPO_TAG)
    Write-Build Gray ('  - Tag name:               {0}' -f $env:APPVEYOR_REPO_TAG_NAME)
    Write-Build Gray ('PowerShell version:         {0}' -f $PSVersionTable.PSVersion.ToString())
    Write-Build Gray
}

# Synopsis: Install pandoc to .\Tools\
# Task InstallPandoc -If (-not (Test-Path Tools\pandoc.exe)) {
#     # Setup
#     if (-not (Test-Path "$BuildRoot\Tools")) {
#         $null = New-Item -Path "$BuildRoot\Tools" -ItemType Directory
#     }

#     # Get latest bits
#     $latestRelease = "https://github.com/jgm/pandoc/releases/download/1.19.2.1/pandoc-1.19.2.1-windows.msi"
#     Invoke-WebRequest -Uri $latestRelease -OutFile "$($env:temp)\pandoc.msi"

#     # Extract bits
#     $null = New-Item -Path $env:temp\pandoc -ItemType Directory -Force
#     Start-Process -Wait -FilePath msiexec.exe -ArgumentList " /qn /a `"$($env:temp)\pandoc.msi`" targetdir=`"$($env:temp)\pandoc\`""

#     # Move to Tools folder
#     Copy-Item -Path "$($env:temp)\pandoc\Pandoc\pandoc.exe" -Destination "$BuildRoot\Tools\"
#     Copy-Item -Path "$($env:temp)\pandoc\Pandoc\pandoc-citeproc.exe" -Destination "$BuildRoot\Tools\"

#     # Clean
#     Remove-Item -Path "$($env:temp)\pandoc" -Recurse -Force
# }
# endregion

# region test
Task Test RapidTest

# Synopsis: Using the "Fast" Test Suit
Task RapidTest PesterTests

# Synopsis: Warn about not empty git status if .git exists.
Task GitStatus -If (Test-Path .git) {
    $status = Exec { git status -s }
    if ($status) {
        Write-Warning "Git status: $($status -join ', ')"
    }
}

# Synopsis: Invoke Pester Tests
Task PesterTests {
    try {
        $result = Invoke-Pester -PassThru -OutputFile "$BuildRoot\TestResult.xml" -OutputFormat "NUnitXml"
        if ($env:APPVEYOR_PROJECT_NAME) {
            Add-TestResultToAppveyor -TestFile "$BuildRoot\TestResult.xml"
            Remove-Item "$BuildRoot\TestResult.xml" -Force
        }
        Assert ($result.FailedCount -eq 0) "$($result.FailedCount) Pester test(s) failed."
    }
    catch {
        throw
    }
}
# endregion

# region build
# Synopsis: Build shippable release
# Task Build GenerateRelease, GenerateDocs, UpdateManifest
Task Build GenerateRelease, UpdateManifest

# Synopsis: Generate .\Release structure
Task GenerateRelease {
    # Setup
    if (-not (Test-Path "$releasePath\PSIni")) {
        $null = New-Item -Path "$releasePath\PSIni" -ItemType Directory
    }

    # Copy module
    Copy-Item -Path "$BuildRoot\PSIni\*" -Destination "$releasePath\PSIni" -Recurse -Force
    # Copy additional files
    $additionalFiles = @(
        # "$BuildRoot\CHANGELOG.md"
        "$BuildRoot\LICENSE"
        "$BuildRoot\README.md"
    )
    Copy-Item -Path $additionalFiles -Destination "$releasePath\PSIni" -Force
}

# Synopsis: Update the manifest of the module
Task UpdateManifest GetVersion, {
    Update-Metadata -Path "$releasePath\PSIni\PSIni.psd1" -PropertyName ModuleVersion -Value $script:Version
    # Update-Metadata -Path "$releasePath\PSIni\PSIni.psd1" -PropertyName FileList -Value (Get-ChildItem $releasePath\PSIni\PSIni -Recurse).Name
    Set-ModuleFunctions -Name "$releasePath\PSIni\PSIni.psd1"
}

Task GetVersion {
    $manifestContent = Get-Content -Path "$releasePath\PSIni\PSIni.psd1" -Raw
    if ($manifestContent -notmatch '(?<=ModuleVersion\s+=\s+'')(?<ModuleVersion>.*)(?='')') {
        throw "Module version was not found in manifest file,"
    }

    $currentVersion = [Version] $Matches.ModuleVersion
    if ($env:APPVEYOR_BUILD_NUMBER) {
        $newRevision = $env:APPVEYOR_BUILD_NUMBER
    }
    else {
        $newRevision = 0
    }
    $script:Version = New-Object -TypeName System.Version -ArgumentList $currentVersion.Major,
    $currentVersion.Minor,
    $newRevision
}

# Synopsis: Generate documentation
# Task GenerateDocs GenerateMarkdown, ConvertMarkdown

# # Synopsis: Generate markdown documentation with platyPS
# Task GenerateMarkdown {
#     Import-Module platyPS -Force
#     Import-Module "$releasePath\PSIni.psd1" -Force
#     $null = New-MarkdownHelp -Module PSIni -OutputFolder "$releasePath\PSIni\docs" -Force
#     Remove-Module PSIni, platyPS
# }

# # Synopsis: Convert markdown files to HTML.
# # <http://johnmacfarlane.net/pandoc/>
# $ConvertMarkdown = @{
#     Inputs  = { Get-ChildItem "$releasePath\PSIni\*.md" -Recurse }
#     Outputs = {process {
#             [System.IO.Path]::ChangeExtension($_, 'htm')
#         }
#     }
# }
# Synopsis: Converts *.md and *.markdown files to *.htm
# Task ConvertMarkdown -Partial @ConvertMarkdown InstallPandoc, {process {
#         Write-Build Green "Converting File: $_"
#         Exec { Tools\pandoc.exe $_ --standalone --from=markdown_github "--output=$2" }
#     }
# }
# endregion

# region publish
Task Deploy -If ($env:APPVEYOR_REPO_BRANCH -eq 'master' -and (-not($env:APPVEYOR_PULL_REQUEST_NUMBER))) RemoveMarkdown, {
    Remove-Module PSIni -ErrorAction SilentlyContinue
}, PublishToGallery

Task PublishToGallery {
    Assert ($env:PSGalleryAPIKey) "No key for the PSGallery"

    Import-Module $releasePath\PSIni\PSIni.psd1 -ErrorAction Stop
    Publish-Module -Name PSIni -NuGetApiKey $env:PSGalleryAPIKey
}

# Synopsis: Push with a version tag.
Task PushRelease GitStatus, GetVersion, {
    # Done in appveyor.yml with deploy provider.
    # This is needed, as I don't know how to athenticate (2-factor) in here.
    Exec { git checkout master }
    $changes = Exec { git status --short }
    Assert (!$changes) "Please, commit changes."

    Exec { git push }
    Exec { git tag -a "v$Version" -m "v$Version" }
    Exec { git push origin "v$Version" }
}
# endregion

#region Cleaning tasks
Task Clean RemoveGeneratedFiles
# Synopsis: Remove generated and temp files.
Task RemoveGeneratedFiles {
    $itemsToRemove = @(
        'Release'
        '*.htm'
        'TestResult.xml'
    )
    Remove-Item $itemsToRemove -Force -Recurse -ErrorAction 0
}

# Synopsis: Remove Markdown files from Release
Task RemoveMarkdown -If { Get-ChildItem "$releasePath\PSIni\*.md" -Recurse } {
    Remove-Item -Path "$releasePath\PSIni" -Include "*.md" -Recurse
}
# endregion

Task . ShowDebug, Test, Build, Deploy #, Clean
