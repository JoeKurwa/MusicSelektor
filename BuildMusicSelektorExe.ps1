$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }

$outExe = Join-Path $scriptDir "MusicSelektor.exe"

$code = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string batPath = Path.Combine(baseDir, "MusicSelektor.bat");

        if (!File.Exists(batPath))
        {
            MessageBox.Show(
                "MusicSelektor.bat introuvable dans le dossier de l'application.",
                "MusicSelektor",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return;
        }

        var psi = new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = "/c \"\"" + batPath + "\"\"",
            WorkingDirectory = baseDir,
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Normal
        };

        Process.Start(psi);
    }
}
"@

if (Test-Path -LiteralPath $outExe) {
    Remove-Item -LiteralPath $outExe -Force
}

Add-Type -TypeDefinition $code -ReferencedAssemblies @("System.dll", "System.Windows.Forms.dll") -OutputAssembly $outExe -OutputType WindowsApplication
Write-Host "Launcher cree: $outExe"
