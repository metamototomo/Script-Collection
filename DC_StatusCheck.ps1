# ==================================================================
# DC_StatusCheck.ps1
# Lightweight tool to check DC connectivity and authentication status
# Author: Nobu
# ==================================================================

# --- Configuration ---
$DomainFQDN = "d11-ads.prm01.gcs.cloud"       # Your domain FQDN
$LogFolder  = "C:\Logs"                       # Change if needed
$LogFile    = Join-Path $LogFolder "DC_Status_Log.csv"

# --- Ensure log folder exists ---
if (!(Test-Path $LogFolder)) {
    try {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    } catch {
        Write-Output "Failed to create log folder: $LogFolder"
        exit 1
    }
}

# --- Prepare environment ---
$Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ComputerName = $env:COMPUTERNAME
$UserName     = "$env:USERDOMAIN\$env:USERNAME"

# --- Step 1: Resolve Domain FQDN to IP ---
try {
    $dnsResult = Resolve-DnsName $DomainFQDN -ErrorAction Stop
    $DC_IP = ($dnsResult | Where-Object {$_.Type -eq 'A'}).IPAddress
} catch {
    $DC_IP = "DNS Resolution Failed"
}

# --- Step 2: Ping test ---
if ($DC_IP -and $DC_IP -ne "DNS Resolution Failed") {
    $ping = Test-Connection -ComputerName $DC_IP -Count 1 -ErrorAction SilentlyContinue
    $PingTime = if ($ping) { $ping.ResponseTime } else { "No reply" }
} else {
    $PingTime = "N/A"
}

# --- Step 3: Determine actual DC used by this machine ---
try {
    $dcInfo = nltest /dsgetdc:$($env:USERDOMAIN)
    $DC_Used = ($dcInfo | Select-String "DC:").ToString().Split(":")[1].Trim()
} catch {
    $DC_Used = "Failed to determine DC"
}

# --- Step 4: LDAP (ADSI) connectivity test ---
try {
    $ads = [ADSI]"LDAP://$env:USERDOMAIN"
    $ads.psbase.Name | Out-Null
    $LDAP_Status = "Success"
    $LDAP_Error  = ""
} catch {
    $LDAP_Status = "Failed"
    $LDAP_Error  = $_.Exception.Message
}

# --- Step 5: Secure Channel test ---
try {
    $SecureChannel_OK = Test-ComputerSecureChannel -ErrorAction Stop
    $SecureChannel_Status = if ($SecureChannel_OK) { "Healthy" } else { "Broken" }
} catch {
    $SecureChannel_Status = "Error"
}

# --- Step 6: Build result record ---
$result = [PSCustomObject]@{
    Timestamp            = $Timestamp
    ComputerName         = $ComputerName
    UserName             = $UserName
    DomainFQDN           = $DomainFQDN
    DC_Used              = $DC_Used
    DC_IP                = $DC_IP
    Ping_ResponseMS      = $PingTime
    LDAP_Status          = $LDAP_Status
    SecureChannel_Status = $SecureChannel_Status
    Error_Message        = $LDAP_Error
}

# --- Step 7: Save result ---
try {
    if (!(Test-Path $LogFile)) {
        $result | Export-Csv -Path $LogFile -NoTypeInformation
    } else {
        $result | Export-Csv -Path $LogFile -Append -NoTypeInformation
    }
} catch {
    Write-Output "Failed to write log file: $LogFile"
}

# --- Step 8: Optional console output (for testing) ---
Write-Output ("[{0}] {1} -> DC:{2} | LDAP:{3} | Channel:{4} | Ping:{5}ms" -f `
    $Timestamp, $ComputerName, $DC_Used, $LDAP_Status, $SecureChannel_Status, $PingTime)

