Set FSO = CreateObject("Scripting.FileSystemObject")
ParentDir = FSO.GetParentFolderName(WScript.ScriptFullName)
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = ParentDir
Cmd = "cmd /c powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & chr(34) & ParentDir & "\MusicPlayer.ps1" & chr(34) & " 1^>^>" & chr(34) & "%TEMP%\MusicPlayer.startup.out.log" & chr(34) & " 2^>^>" & chr(34) & "%TEMP%\MusicPlayer.startup.error.log" & chr(34)
WshShell.Run Cmd, 0
Set WshShell = Nothing
