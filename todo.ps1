
# refs:
#   https://jdhitsolutions.com/blog/powershell/7024/managing-the-recycle-bin-with-powershell/
#       ALTERNATIVE: https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shqueryrecyclebina
#   https://learn.microsoft.com/en-us/windows/win32/shell/folder
#   https://learn.microsoft.com/en-us/windows/win32/shell/folderitem
#   https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_script_blocks?view=powershell-5.1
#   https://learn.microsoft.com/en-us/windows/win32/shell/shellfolderitem-extendedproperty
#   https://learn.microsoft.com/en-us/windows/win32/stg/structured-storage-serialized-property-set-format
function Get-RecycleBin([char] $DriveLetter = '*') {
    $rb = (New-Object -ComObject Shell.Application).Namespace(10)
    $rbItems = @($rb.Items()) | Where-Object { $_.Path -ilike "${DriveLetter}:" }
    $items = ($rbItems | Get-Prop -Prop 'Path') | Get-ChildItem
    $itemsSize = $rbItems | Get-Prop -Prop 'Size' | Get-ReducedArray -BeginScriptBlock { $total = 0 } -ProcessScriptBlock { $total += $_ } -EndScriptBlock { return $total }
    $result = [PSCustomObject]@{
        DriveLetter = $DriveLetter
        Count       = $items.Length
        Size        = $itemsSize
        Items       = $items
    }
    $result.Items | ForEach-Object {
        Add-Member -InputObject $rb -MemberType NoteProperty -Name '__RecycleBinFilename' -Value $_.FullName
        Add-Member -InputObject $rb -MemberType NoteProperty -Name '__OriginalFilename' -Value ((($_.ExtendedProperty('infotip')).Split("`n") | Select-Object -Last 1).Split(':', 2) | Select-Object -Last 1).Trim()
        Add-Member -InputObject $rb -MemberType NoteProperty -Name '__DateDeletedUTC' -Value $_.ExtendedProperty('DateDeleted')
        Add-Member -InputObject $rb -MemberType NoteProperty -Name '__DateDeleted' -Value $_.__DateDeletedUTC.ToLocalTime()
        Add-Member -InputObject $rb -MemberType ScriptMethod -Name 'Delete' -Value ({
                Param([switch] $Force, [switch] $Recurse, [bool] $Confirm = $true, [switch] $Verbose)
                return (Remove-Item -Force:$Force -Recurse:$Recurse -Confirm:$Confirm -Verbose:$Verbose -Path $_.__RecycleBinFilename)
            })
        Add-Member -InputObject $rb -MemberType ScriptMethod -Name 'Restore' -Value ({
                Param([switch] $Force, [bool] $Confirm = $true, [switch] $Verbose)
                return (Move-Item -Path $_.__RecycleBinFilename -Destination $_.__OriginalFilename -Force:$Force -Confirm:$Confirm -Verbose:$Verbose)
            })
    }
    return $result
}
