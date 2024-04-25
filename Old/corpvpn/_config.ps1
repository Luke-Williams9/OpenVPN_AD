# Global config variables
$install_path = "$env:programData\corpvpn"
$global:conf = Get-Content "$install_path\config_params.json" | ConvertFrom-JSON