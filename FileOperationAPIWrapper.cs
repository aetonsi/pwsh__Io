// https://stackoverflow.com/a/3282481
// https://stackoverflow.com/a/71869244
// https://learn.microsoft.com/en-us/windows/win32/api/shellapi/ns-shellapi-shfileopstructw

using System;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Aetonsi;

public static class FileOperationAPIWrapper
{
    static void Main()
    { }

    /// <summary>
    /// Possible flags for the SHFileOperation method.
    /// </summary>
    [Flags]
    public enum FileOperationFlags : ushort
    {
        /// <summary>
        /// Do not show a dialog during the process
        /// </summary>
        FOF_SILENT = 0x0004,

        /// <summary>
        /// Do not ask the user to confirm selection
        /// </summary>
        FOF_NOCONFIRMATION = 0x0010,
        /// <summary>
        /// Delete the file to the recycle bin.  (Required flag to send a file to the bin
        /// </summary>
        FOF_ALLOWUNDO = 0x0040,
        /// <summary>
        /// Do not show the names of the files or folders that are being recycled.
        /// </summary>
        FOF_SIMPLEPROGRESS = 0x0100,
        /// <summary>
        /// Surpress errors, if any occur during the process.
        /// </summary>
        FOF_NOERRORUI = 0x0400,
        /// <summary>
        /// Warn if files are too big to fit in the recycle bin and will need
        /// to be deleted completely.
        /// </summary>
        FOF_WANTNUKEWARNING = 0x4000,
    }

    private static FileOperationFlags GetDefaultFlags()
    {
        return FileOperationFlags.FOF_ALLOWUNDO | FileOperationFlags.FOF_WANTNUKEWARNING;
    }

    /// <summary>
    /// File Operation Function Type for SHFileOperation
    /// </summary>
    public enum FileOperationType : uint
    {
        /// <summary>
        /// Move the objects
        /// </summary>
        FO_MOVE = 0x0001,
        /// <summary>
        /// Copy the objects
        /// </summary>
        FO_COPY = 0x0002,
        /// <summary>
        /// Delete (or recycle) the objects
        /// </summary>
        FO_DELETE = 0x0003,
        /// <summary>
        /// Rename the object(s)
        /// </summary>
        FO_RENAME = 0x0004,
    }

    /// <summary>
    /// SHFILEOPSTRUCT for SHFileOperation from COM
    /// </summary>
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct SHFILEOPSTRUCT
    {

        public IntPtr hwnd;
        [MarshalAs(UnmanagedType.U4)]
        public FileOperationType wFunc;
        public string pFrom;
        public string pTo;
        public FileOperationFlags fFlags;
        [MarshalAs(UnmanagedType.Bool)]
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT FileOp);


    private static bool CliConfirmation(string[] paths, bool permanentlyDelete)
    {
        string p =
            Environment.NewLine +
            string.Join(
                Environment.NewLine,
                paths.Select(path => "> " + path)
            ) +
            Environment.NewLine +
            "[Yes/No]> ";
        Console.Write(
            "Are you sure you want to " + (permanentlyDelete ? "permanently" : "") + " delete " +
            (paths.Length == 1 ? "this item?" : "these items?") +
            p
        );
        string r = Console.ReadLine();
        return r.ToLower().StartsWith("y");
    }

    public static bool? SendToRecycleBin(
        string path,
        bool permanentlyDelete = false,
        bool noConfirmation = false,
        bool showDialogs = true,
        FileOperationFlags? flags = null
    )
    {
        return SendToRecycleBin(
            new string[] { path },
            permanentlyDelete,
            noConfirmation,
            showDialogs,
            flags
        );
    }

    public static bool? SendToRecycleBin(
        string[] paths,
        bool permanentlyDelete = false,
        bool noConfirmation = false,
        bool showDialogs = true,
        FileOperationFlags? flags = null
    )
    {
        try
        {
            FileOperationFlags fFlags = flags ?? GetDefaultFlags();
            if (permanentlyDelete)
            {
                // disallow UNDO
                fFlags &= ~FileOperationFlags.FOF_ALLOWUNDO;
            }
            if (noConfirmation)
            {
                // remove confirmation (add NOCOFIRMATION)
                fFlags |= FileOperationFlags.FOF_NOCONFIRMATION;
            }
            if (!showDialogs)
            {
                // remove "file too big for recycle bin" warning dialog ...
                fFlags &= ~FileOperationFlags.FOF_WANTNUKEWARNING;
                // ... but still ask for confirmation, if needed
                if (!noConfirmation)
                {
                    // ask for confirmation via CLI
                    if (!CliConfirmation(paths, permanentlyDelete))
                    {
                        Console.WriteLine("canceled.");
                        // return value is NULL instead of true or false
                        return null;
                    }
                }
                // remove confirmation (add NOCOFIRMATION), add SILENT, remove error UIs (add NOERRORUI)
                fFlags |= FileOperationFlags.FOF_NOCONFIRMATION |
                    FileOperationFlags.FOF_SILENT |
                    FileOperationFlags.FOF_NOERRORUI;
            }
            var fs = new SHFILEOPSTRUCT
            {
                wFunc = FileOperationType.FO_DELETE,
                pFrom = string.Join("\0", paths) + '\0' + '\0',
                fFlags = fFlags
            };
            int result = SHFileOperation(ref fs);
            if (result == 0)
            {
                return true;
            }
            else
            {
                Console.WriteLine(
                    "Error #" + result + ": " +
                    (result switch
                    {
                        2 => "ERROR_FILE_NOT_FOUND",
                        5 => "ERROR_ACCESS_DENIED",
                        6 => "ERROR_INVALID_HANDLE",
                        1223 => "ERROR_CANCELLED",
                        _ => "[unknown]",
                    }) +
                    Environment.NewLine +
                    "( see https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shfileoperationa OR https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-erref/18d8fbe8-a967-4f1c-ae50-99ca8e491d2d OR https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499- )"
                );
                return false;
            }
        }
        catch (Exception)
        {
            return false;
        }
    }
}