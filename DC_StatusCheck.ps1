# ===============================
# AD Secure Channel and LDAP Check
# ===============================

# Configuration
$DomainFQDN = "d11-ads.prm01.gcs.cloud"
$LogFolder = "C:\GCS_Logs"
$UserName = "$env:USERDOMAIN\$env:USERNAME"
$ComputerName = $env:COMPUTERNAME
$TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

# --- Create log folder if not exists ---
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory | Out-Null
}

# --- Step 1: Discover Domain Controller ---
try {
    $DCInfo = nltest /dsgetdc:$DomainFQDN
    $DC_Used = ($DCInfo | Select-String "DC:" | ForEach-Object { $_.ToString().Split(":")[1].Trim() })
} catch {
    $DC_Used = "Unknown"
}

# --- Step 2: Resolve actual DC name to IP ---
try {
    $dcHost = ($DC_Used -replace '\\','').Trim()
    $dnsResult = Resolve-DnsName $dcHost -ErrorAction Stop
    $DC_IP = ($dnsResult | Where-Object {$_.Type -eq 'A'}).IPAddress
} catch {
    $DC_IP = "Resolution failed for $dcHost"
}

# --- Step 3: Ping DC ---
try {
    $Ping = Test-Connection -ComputerName $dcHost -Count 1 -ErrorAction Stop
    $Ping_ResponseMS = [math]::Round($Ping.ResponseTime, 2)
} catch {
    $Ping_ResponseMS = "Unreachable"
}

# --- Step 4: Test LDAP Connection ---
try {
    $LDAP_Test = [ADSI]"LDAP://$DomainFQDN"
    $LDAP_Status = "Success"
} catch {
    $LDAP_Status = "Failed"
}

# --- Step 5: Test Secure Channel ---
try {
    if (Test-ComputerSecureChannel -Verbose:$false) {
        $SecureChannel_Status = "Healthy"
    } else {
        $SecureChannel_Status = "Broken"
    }
} catch {
    $SecureChannel_Status = "Error"
}

# --- Step 6: Build log data ---
$LogData = [PSCustomObject]@{
    Timestamp             = $TimeStamp
    ComputerName          = $ComputerName
    UserName              = $UserName
    DomainFQDN            = $DomainFQDN
    DC_Used               = $DC_Used
    DC_IP                 = $DC_IP
    Ping_ResponseMS       = $Ping_ResponseMS
    LDAP_Status           = $LDAP_Status
    SecureChannel_Status  = $SecureChannel_Status
    Error_Message         = ""
}

# --- Step 7: Export result to CSV ---
$LogFile = Join-Path $LogFolder "$ComputerName-ADCheck.csv"

if (-not (Test-Path $LogFile)) {
    $LogData | Export-Csv -Path $LogFile -NoTypeInformation
} else {
    $LogData | Export-Csv -Path $LogFile -Append -NoTypeInformation
}

Write-Host "[$TimeStamp] AD connectivity check completed. Log saved to $LogFile" -ForegroundColor Cyan
