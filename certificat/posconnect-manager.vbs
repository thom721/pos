Set sh  = CreateObject("Shell.Application")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
args = "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File """ & dir & "\posconnect-manager.ps1"""
sh.ShellExecute "powershell.exe", args, dir, "runas", 0
