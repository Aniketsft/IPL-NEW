$configContent = @"
# Smart case-insensitivity (case-insensitive if pattern is all lowercase)
--smart-case

# Ignore patterns globally
--glob=!.git/*
--glob=!.vscode/*

# Add/ensure custom markdown file extensions
--type-add=md:*.{md,markdown}
"@

$targetPath = Join-Path $HOME ".ripgreprc"
[System.IO.File]::WriteAllText($targetPath, $configContent, [System.Text.Encoding]::UTF8)
Write-Output "Created config file at: $targetPath"

# Set user-level environment variable
[System.Environment]::SetEnvironmentVariable("RIPGREP_CONFIG_PATH", $targetPath, "User")
Write-Output "Set User environment variable RIPGREP_CONFIG_PATH = $targetPath"

# Verify environment variable
$check = [System.Environment]::GetEnvironmentVariable("RIPGREP_CONFIG_PATH", "User")
Write-Output "Verified User environment variable: $check"
