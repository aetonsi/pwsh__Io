Add-Type -AssemblyName System.Windows.Forms

# Filter example 'Documents (ms office only)|*.docx|SpreadSheets (ms office, openoffice)|*.xlsx,*.xls,*.ods'
# TODO suppress ALL dialogs output
function Get-OpenFileDialog(
  [string] $InitialDirectory = $PWD,
  [bool] $MultiSelect = $false,
  [string] $Filter = '',
  [string] $Title = $null,
  [string] $defaultFilename = $null,
  [bool] $addAnyFileFilter = $true
) {
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
function Get-FolderBrowserDialog(
  [string] $InitialDirectory = $PWD,
  [bool] $ShowNewFolderButton = $true,
  [string] $Title = $null
) {
  $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
    InitialDirectory       = $InitialDirectory
    ShowNewFolderButton    = $ShowNewFolderButton
    Description            = $Title
    UseDescriptionForTitle = $true
    RootFolder             = 'Desktop'
    ShowHiddenFiles        = $true
  }
  $FolderBrowser.ShowDialog() *>$null
  return $FolderBrowser.SelectedPath
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
  return $FileBrowser.FileName
}


Export-ModuleMember -Function *
