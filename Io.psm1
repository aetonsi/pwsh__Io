# save/open dialogs Filter example: 'Documents (ms office only)|*.docx|SpreadSheets (ms office, openoffice)|*.xlsx,*.xls,*.ods'

using namespace Microsoft.PowerShell.Commands

Import-Module -Scope local "$PSScriptRoot/pwsh__Utils/Utils.psm1"
Import-Module -Scope local "$PSScriptRoot/pwsh__String/String.psm1"

Add-Type -Path "$PSScriptRoot/FileOperationAPIWrapper.cs"


function path_cleanup([parameter(ValueFromPipeline)][string] $path) {
  $result = $path | Get-UnquotedString # remove quotes if present
  if ($IsWindows) { $result = $result -replace '/', '\' }
  $result = $result.TrimEnd('\') # [System.IO.Path]::TrimEndingDirectorySeparator($result) DOESNT WORK in powershell.exe
  if ($result -eq '.') { $result = $PWD.Path } # resolve the dot
  if ($result -eq '..') { $result = "$($PWD.Path)\.." } # resolve the double dot
  if ($result -like '*:') { $result = "$path\" } # normalizes drives roots
  return $result
}


Function Get-SafeFileName(
  [Parameter(ValueFromPipeline = $true )][String] $Name,
  [string] $Replacement = '_'
) {
  # https://stackoverflow.com/a/23067832
  # https://stackoverflow.com/questions/23066783/how-to-strip-illegal-characters-before-trying-to-save-filenames#comment132875243_23067832

  $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
  return ($Name -replace "[$([RegEx]::Escape($invalidChars))]", $Replacement)
}
Set-Alias -Option AllScope -Scope 'Global' -Force -Name 'Remove-InvalidFileNameCharacters' -Value Get-SafeFileName



function Read-FolderSize([Parameter(ValueFromPipeline, Mandatory)] $Dir, [switch] $OnlyBytes) {
  $ls = Get-ChildItem -Recurse -Force $Dir
  $size = $ls | Measure-Object -Property Length -Sum
  $dircount = $ls.count - $size.count
  $filescount = $size.count

  $result = if ($OnlyBytes) {
    $size.Sum
  } else {
    [pscustomobject]@{
      Directories       = $dircount
      Files             = $filescount
      BytesSize         = [string]($size.Sum) # cast to remove decimals
      HumanReadableSize = $size.Sum | Get-HumanReadableSize
    }
  }
  return $result
}


function Get-FriendlySize([Parameter(ValueFromPipeline)][double] $Bytes, [int] $DecimalPrecision = 2, [switch] $ShortForm, [switch] $LocaleForm) {
  # adapted from: https://martin77s.wordpress.com/2017/05/20/display-friendly-file-sizes-in-powershell/
  $SIprefixes = ',Kilo,Mega,Giga,Tera,Peta,Exa,Zetta,Yotta' -split ',' # TODO use global enum?
  $prefix = ''
  $convertedQuantity = $Bytes
  $i = 1
  while (($convertedQuantity -ge 1kb) -and ($i -in 0..($SIprefixes.Length - 1))) {
    $convertedQuantity /= 1kb
    $prefix = $SIprefixes[$i]
    $i++
  }

  # $isInteger = $convertedQuantity -eq [System.Math]::Truncate($convertedQuantity)
  $isInteger = 0 -eq ($convertedQuantity % 1)

  $formatModifier = if ($LocaleForm) { 'N' } else { 'f' }
  $decimalDigits = if ($isinteger) { 0 } else { $DecimalPrecision }
  $measurementUnit = $prefix + 'Byte' + $(if ($convertedQuantity -eq 1) { '' }else { 's' })
  if ($ShortForm) { $measurementUnit = $measurementUnit.ToCharArray().Where({ [System.Char]::IsUpper($_) }) }
  $result = "{0:${formatModifier}${decimalDigits}} {1}" -f $convertedQuantity, $measurementUnit

  return $result
}
Set-Alias -Option AllScope -Scope 'Global' -Force -Name 'Get-HumanReadableSize' -Value Get-FriendlySize


function Get-RandomFileInFolder($Folder = '.', [switch] $ReturnFileNameOnly) {
  $files = Get-ChildItem $Folder
  $result = Get-Random -InputObject $files
  if ($ReturnFileNameOnly) {
    return $result.Name
  } else {
    return $result
  }
}


function Move-ToRecycleBin (
  [Parameter(ValueFromPipeline)] $Files,
  [Alias('Force', 'Permanently', 'Forever')][switch] $DeletePermanently,
  [switch] $NoConfirmation,
  [switch] $NoDialogs
) {
  if ($local:Error) { $local:Error.clear() }

  $Files = Get-Item $Files -ErrorAction Continue

  return [Aetonsi.FileOperationAPIWrapper]::SendToRecycleBin(
    [string[]] $Files,
    $DeletePermanently,
    $NoConfirmation,
    !$NoDialogs
  )

  <# if ($DeletePermanently -and !$AskForConfirmation) {
    $Files | ForEach-Object { Remove-Item -Force -Recurse -ErrorAction Continue }
  } #>
  <# if ($exe = (Get-Command -CommandType Application -Name 'recycle').Path) {
    # Depends on maddog's Recycle.exe from cmdutils package: http://www.maddogsw.com/cmdutils/
    $f = if ($DeletePermanently) { '-f' } else { '' }
    $paths = ($Files | ForEach-Object { $_ | Get-QuotedString }) -join ' '
    & $exe $f $paths
  } #>
  <# Add-Type -AssemblyName Microsoft.VisualBasic
  $showUI = if (!$AskForConfirmation) { [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs } else { [Microsoft.VisualBasic.FileIO.UIOption]::AllDialogs }
  $recycle = if ($DeletePermanently) { [Microsoft.VisualBasic.FileIO.RecycleOption]::DeletePermanently } else { [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin }
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
    $Files,
    $showUI,
    $recycle,
    [Microsoft.VisualBasic.FileIO.UICancelOption]::DoNothing
  ) #>
  <# return (($local:Error.count -eq 0) -and !(Test-Path $Files)) #>
}
New-Alias -Option AllScope -Name 'Send-ToRecycleBin' -Value Move-ToRecycleBin


function Get-Dirname ([parameter(ValueFromPipeline)][string] $path, [switch] $IdentityOnDriveRoot) {
  $result = $path | path_cleanup
  $result = [System.IO.Path]::GetDirectoryName($result)
  if (($null -eq $result) -and $IdentityOnDriveRoot) {
    $result = [System.IO.Path]::GetFullPath(($path | path_cleanup))
  }
  return $result
}
function Get-Basename ([parameter(ValueFromPipeline)][string] $path, [switch] $stripExtension) {
  $result = $path | path_cleanup
  if ($stripExtension) {
    $result = [System.IO.Path]::GetFileNameWithoutExtension($result)
  } else {
    $result = [System.IO.Path]::GetFileName($result)
  }
  return $result
}
function Get-Realpath ([parameter(ValueFromPipeline)][string] $path) {
  $result = $path | path_cleanup
  $result = [System.IO.Path]::GetFullPath($result)
  return $result
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
    $paths = @($paths) # stop array enumeration

    $invalidPaths = @()
    for ($i = 0; $i -lt $paths.Length ; $i++) {
      if ($mustExist) {
        # checks both for existance AND type (folder/file)
        if (! (Test-Path -PathType $pathType -Path ($paths[$i] | path_cleanup))) {
          $invalidPaths += $paths[$i]
        }
      } else {
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
  } else {
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

function build_anyfile_filter([bool] $AddAnyFileFilter, [string] $Filter) {
  $filterStr = $Filter
  if ($AddAnyFileFilter) {
    if ($Filter) { $filterStr += '|' }
    $filterStr += 'Any file|*'
  }
  return $filterStr
}


function Get-OpenFileDialog(
  [string] $InitialDirectory = $PWD.Path,
  [bool] $MultiSelect = $false,
  [string] $Filter = '',
  [string] $Title = $null,
  [string] $DefaultFilename = $null,
  [bool] $AddAnyFileFilter = $true
) {
  if ($IsWindows) {
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
      InitialDirectory             = $InitialDirectory
      MultiSelect                  = $MultiSelect
      Filter                       = build_anyfile_filter $AddAnyFileFilter $Filter
      Title                        = $Title
      FileName                     = $DefaultFilename
      CheckFileExists              = $true
      CheckPathExists              = $true
      ShowHiddenFiles              = $true
      SupportMultiDottedExtensions = $true
      ShowReadOnly                 = $false
      AddExtension                 = $true
    }
    $FileBrowser.ShowDialog() *>$null
    if ($MultiSelect) { return $FileBrowser.FileNames }
    else { return $FileBrowser.FileName }
  } elseif ($IsLinux) {
    $path = Get-TypedPath -pathType Leaf -mustExist -allowMultiple:$MultiSelect
  } else {
    throw 'unsupported OS'
  }
  return $path
}

function Get-FolderBrowserDialog(
  [string] $InitialDirectory = $PWD.Path,
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
  } elseif ($IsLinux) {
    $path = Get-TypedPath -pathType Container -mustExist
  } else {
    throw 'unsupported OS'
  }
  return $path
}

function Get-SaveFileDialog(
  [string] $InitialDirectory = $PWD.Path,
  [bool] $OverwritePrompt = $true,
  [string] $Filter = '',
  [string] $Title = $null,
  [string] $DefaultFilename = $null,
  [bool] $CheckWriteAccess = $false,
  [bool] $CreatePrompt = $false,
  [bool] $AddAnyFileFilter = $true
) {
  if ($IsWindows) {
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog -Property @{
      InitialDirectory             = $InitialDirectory
      CheckWriteAccess             = $CheckWriteAccess
      OverwritePrompt              = $OverwritePrompt
      CreatePrompt                 = $CreatePrompt
      Filter                       = build_anyfile_filter $AddAnyFileFilter $Filter
      Title                        = $Title
      FileName                     = $DefaultFilename
      CheckPathExists              = $true
      ShowHiddenFiles              = $true
      SupportMultiDottedExtensions = $true
      AddExtension                 = $true
    }
    $FileBrowser.ShowDialog() *>$null
    $path = $FileBrowser.FileName
  } elseif ($IsLinux) {
    $path = Get-TypedPath -pathType Leaf
  } else {
    throw 'unsupported OS'
  }
  return $path
}


Export-ModuleMember -Function *-* -Alias *