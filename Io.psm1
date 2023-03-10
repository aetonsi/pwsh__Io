# save/open dialogs Filter example: 'Documents (ms office only)|*.docx|SpreadSheets (ms office, openoffice)|*.xlsx,*.xls,*.ods'

using namespace Microsoft.PowerShell.Commands

Import-Module "$PSScriptRoot/pwsh__String/String.psm1"


function path_cleanup([parameter(ValueFromPipeline)][string] $path) {
  $result = $path | Get-UnquotedString # remove quotes if present
  if ($result -eq '.') { $result = $PWD.Path } # resolve the dot
  if ($result -eq '..') { $result = "$($PWD.Path)/.." } # resolve the double dot
  if ($result -like '*:') { $result = "$path/" } # normalizes drives roots
  $result = [System.IO.Path]::TrimEndingDirectorySeparator($result) # strips the final slash if present
  return $result
}


function Get-Dirname ([parameter(ValueFromPipeline)][string] $path) {
  $result = $path | path_cleanup
  $result = [System.IO.Path]::GetDirectoryName($result)
  if (! $result) { $result = [System.IO.Path]::GetFullPath($path) } # for drive roots getdirectoryname() would return null
  $result = [System.IO.Path]::GetFullPath("$result/..")
  return ($result | path_cleanup)
}
function Get-Basename ([parameter(ValueFromPipeline)][string] $path, [switch] $stripExtension) {
  $result = $path | path_cleanup
  $result = [System.IO.Path]::GetFullPath($path)
  if ($stripExtension) {
    $result = [System.IO.Path]::GetFileNameWithoutExtension($result)
  }
  else {
    $result = [System.IO.Path]::GetFileName($result)
  }
  return $result
}
function Get-Realpath ([parameter(ValueFromPipeline)][string] $path) {
  $result = $path | path_cleanup
  $result = [System.IO.Path]::GetFullPath($result)
  return ($result | path_cleanup)
}


function Get-TypedPath (
  [TestPathType] $pathType = ([TestPathType]::Any),
  [switch] $mustExist = $false,
  [switch] $allowMultiple = $false,
  [bool] $returnAbsolutePath = $true
) {
  $pathType = [TestPathType]::Leaf
  switch ($pathType) {
    ([TestPathType]::Any) { $typeStr = 'file or folder' ; break }
    ([TestPathType]::Container) { $typeStr = 'folder' ; break }
    ([TestPathType]::Leaf) { $typeStr = 'file' ; break }
    default { throw "unknown path type: $pathType" }
  }
  $promptStr = "$(
    if($mustExist){
      if($allowMultiple){'one or more existing'}else{'an existing'}
    }else{
      if($allowMultiple){'one or more'}else{'a'}
    }) $typeStr"


  if ($allowMultiple) {
    $promptStr += ' [you can enter multiple paths separating them with a space; if a path contains a space, you MUST enclose it with double quotes]'
  }

  $invalidPaths = $null
  do {
    if ($null -ne $invalidPaths) {
      Write-Warning "The following path(s) you entered do(es) not exist or is not of the correct type ($typeStr):`n$invalidPaths"
    }
    $paths = Read-Host -Prompt "Please type a path to ${promptStr}"
    if (! $paths) { $invalidPaths = @('') ; continue }
    if ($allowMultiple) {
      $paths = Get-TokenizedCommandLine $paths
    }
    else {
      $paths = [string[]] @($paths)
    }
    $invalidPaths = @()
    for ($i = 0; $i -lt $paths.Length ; $i++) {
      if ($mustExist) {
        # checks both for existance AND type (folder/file)
        if (! (Test-Path -PathType $pathType -Path ($paths[$i] | path_cleanup))) {
          $invalidPaths += $paths[$i]
        }
      }
      else {
        # manually check if dir or file (can only distinguish them by the trailing slash)
        if (($pathType -eq [TestPathType]::Leaf) -and ($paths[$i] -match '.*[/\\:]$')) {
          $invalidPaths += $paths[$i]
        }
      }
    }
  } until($invalidPaths.Length -eq 0)

  if ($returnAbsolutePath) {
    for ($i = 0; $i -lt $paths.Length ; $i++) {
      $paths[$i] = Get-Realpath $paths[$i]
    }
  }
  if ($allowMultiple) {
    return , $paths
  }
  else {
    return $paths[0]
  }
}

function Test-IsDir(
  [Parameter(Position = 0, ValueFromPipeline = $true, Mandatory = $true)][string] $dir,
  [Parameter(Mandatory = $false)][switch] $mustExist = $false
) {
  if ($mustExist -and (!(Test-Path $dir))) { throw "$dir does not exist" }
  # return (Get-Item $dir) -is [System.IO.DirectoryInfo]
  return Test-Path $dir -PathType Container
}

function Test-IsFile(
  [Parameter(Position = 0, ValueFromPipeline = $true, Mandatory = $true)][string] $file,
  [Parameter(Mandatory = $false)][switch] $mustExist = $false
) {
  if ($mustExist -and (!(Test-Path $file))) { throw "$file does not exist" }
  # return (Get-Item $file) -is [System.IO.FileInfo]
  return Test-Path $file -PathType Leaf
}


function New-TemporaryDirectory {
  # https://stackoverflow.com/a/34559554
  $parent = [System.IO.Path]::GetTempPath()
  $name = [System.IO.Path]::GetRandomFileName()
  return New-Item -ItemType Directory -Path (Join-Path $parent $name)
}


function Get-OpenFileDialog(
  [string] $InitialDirectory = $PWD,
  [bool] $MultiSelect = $false,
  [string] $Filter = '',
  [string] $Title = $null,
  [string] $defaultFilename = $null,
  [bool] $addAnyFileFilter = $true
) {
  if ($IsWindows) {
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
      InitialDirectory             = $InitialDirectory
      MultiSelect                  = $MultiSelect
      Filter                       = $Filter + ($addAnyFileFilter ? (($Filter ? '|' : '') + 'Any file|*') : '')
      Title                        = $Title
      FileName                     = $defaultFilename
      CheckFileExists              = $true
      CheckPathExists              = $true
      ShowHiddenFiles              = $true
      SupportMultiDottedExtensions = $true
      ShowReadOnly                 = $false
      AddExtension                 = $true
    }
    $FileBrowser.ShowDialog() *>$null
    return $MultiSelect ? ([string[]] $FileBrowser.FileNames) : $FileBrowser.FileName
  }
  elseif ($IsLinux) {
    $path = Get-TypedPath -pathType Leaf -mustExist -allowMultiple:$MultiSelect
  }
  return $path
}

function Get-FolderBrowserDialog(
  [string] $InitialDirectory = $PWD,
  [bool] $ShowNewFolderButton = $true,
  [string] $Title = $null
) {
  if ($IsWindows) {
    Add-Type -AssemblyName System.Windows.Forms
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
      InitialDirectory       = $InitialDirectory
      ShowNewFolderButton    = $ShowNewFolderButton
      Description            = $Title
      UseDescriptionForTitle = $true
      RootFolder             = 'Desktop'
      ShowHiddenFiles        = $true
    }
    $FolderBrowser.ShowDialog() *>$null
    $path = $FolderBrowser.SelectedPath
  }
  elseif ($IsLinux) {
    $path = Get-TypedPath -pathType Container -mustExist
  }
  return $path
}

function Get-SaveFileDialog(
  [string] $InitialDirectory = $PWD,
  [bool] $OverwritePrompt = $true,
  [string] $Filter = '',
  [string] $Title = $null,
  [string] $defaultFilename = $null,
  [bool] $CheckWriteAccess = $false,
  [bool] $CreatePrompt = $false,
  [bool] $addAnyFileFilter = $true
) {
  if ($IsWindows) {
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog -Property @{
      InitialDirectory             = $InitialDirectory
      CheckWriteAccess             = $CheckWriteAccess
      OverwritePrompt              = $OverwritePrompt
      CreatePrompt                 = $CreatePrompt
      Filter                       = $Filter + ($addAnyFileFilter ? (($Filter ? '|' : '') + 'Any file|*') : '')
      Title                        = $Title
      FileName                     = $defaultFilename
      CheckPathExists              = $true
      ShowHiddenFiles              = $true
      SupportMultiDottedExtensions = $true
      AddExtension                 = $true
    }
    $FileBrowser.ShowDialog() *>$null
    $path = $FileBrowser.FileName
  }
  elseif ($IsLinux) {
    $path = Get-TypedPath -pathType Leaf
  }
  return $path
}


Export-ModuleMember -Function *-*