param(
    [string]$LogFolder = "C:\GCS_Logs",
    [bool]$EnablePing = $true
)

# Ensure log folder exists
if (!(Test-Path -Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

$ErrorMessage = ""
$PingTime = "N/A"
$LDAP_Status = "N/A"
$LDAP_DC_Used = "N/A"
$LDAP_ResponseMS = "N/A"
$SecureChannel_Status = "N/A"

Write-Host ""
Write-Host "[ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ] Starting AD connectivity check..."

# Step 1: Get DC info (FindDomainController)
Write-Host "Step 1: Getting DC info..."
try {
    $DomainObj = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    $DC_Obj = $DomainObj.FindDomainController()
    $DC_Name = $DC_Obj.Name -replace "^[\\]+", ""

    try {
        $DC_IP = [System.Net.Dns]::GetHostAddresses($DC_Name) |
                 Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                 Select-Object -First 1
        if ($DC_IP) { $DC_IP = $DC_IP.IPAddressToString }
        else { $DC_IP = "Unresolved"; $ErrorMessage += "DNS Error: Could not resolve $DC_Name to IP. | " }
    } catch {
        $DC_IP = "Unresolved"
        $ErrorMessage += "DNS Error: $($_.Exception.Message) | "
    }
} catch {
    $DC_Name = "Lookup Failed"
    $DC_IP = "Unresolved"
    $ErrorMessage += "DC Lookup Error: $($_.Exception.Message) | "
}

# Step 2: Optional Ping
if ($EnablePing) {
    Write-Host "Step 2: Pinging DC..."
    if ($DC_IP -and $DC_IP -ne "Unresolved") {
        try {
            $PingResult = Test-Connection -ComputerName $DC_IP -Count 1 -ErrorAction Stop
            $PingTime = [math]::Round($PingResult.ResponseTime, 2)
            Write-Host "  Ping Success: $PingTime ms"
        } catch {
            $PingTime = "Unreachable"
            $ErrorMessage += "Ping Error: $($_.Exception.Message) | "
            Write-Host "  Ping Failed: $($ErrorMessage)"
        }
    } else {
        $PingTime = "Unreachable"
        $ErrorMessage += "Ping Error: No valid IP to ping. | "
        Write-Host "  Ping Failed: No valid IP to ping."
    }
} else {
    Write-Host "Step 2: Ping test skipped (disabled)."
}

# Step 3: Get actual DC used via nltest
Write-Host "Step 3: Finding actual DC used (nltest)..."
try {
    $nltestOutput = nltest /dsgetdc:$env:USERDOMAIN /server:$env:COMPUTERNAME 2>&1
    $LDAP_DC_Used = ($nltestOutput | Select-String "DC:") -replace ".*DC:\s*", ""
    $LDAP_DC_Used = $LDAP_DC_Used.Trim()

    if ($LDAP_DC_Used) {
        try {
            $ldapStart = Get-Date
            $AD = [ADSI]"LDAP://$LDAP_DC_Used"
            $AD.Name | Out-Null
            $LDAP_Status = "Success"
            $LDAP_ResponseMS = ([math]::Round((New-TimeSpan $ldapStart (Get-Date)).TotalMilliseconds,2))
            Write-Host "  LDAP bind to $LDAP_DC_Used : Success ($($LDAP_ResponseMS) ms)"
        } catch {
            $LDAP_Status = "Failed"
            $LDAP_ResponseMS = "N/A"
            $ErrorMessage += "LDAP Error ($LDAP_DC_Used): $($_.Exception.Message) | "
            Write-Host "  LDAP bind failed: $($_.Exception.Message)"
        }
    } else {
        $LDAP_DC_Used = "Unresolved"
        $LDAP_Status = "Failed"
        $LDAP_ResponseMS = "N/A"
        $ErrorMessage += "LDAP Error: Could not determine DC used. | "
        Write-Host "  LDAP Error: Could not determine DC used."
    }
} catch {
    $LDAP_DC_Used = "Error"
    $LDAP_Status = "Failed"
    $LDAP_ResponseMS = "N/A"
    $ErrorMessage += "LDAP Error: $($_.Exception.Message) | "
    Write-Host "  LDAP Error: $($_.Exception.Message)"
}

# Step 4: Test secure channel
Write-Host "Step 4: Testing Secure Channel..."
try {
    if (Test-ComputerSecureChannel -Verbose:$false) {
        $SecureChannel_Status = "Healthy"
        Write-Host "  Secure Channel: Healthy"
    } else {
        $SecureChannel_Status = "Broken"
        Write-Host "  Secure Channel: Broken"
    }
} catch {
    $SecureChannel_Status = "Error"
    $ErrorMessage += "Secure Channel Error: $($_.Exception.Message) | "
    Write-Host "  Secure Channel Test Error: $($_.Exception.Message)"
}

# Step 5: Write result to CSV
Write-Host "Step 5: Writing log file..."
$CSV_File = Join-Path $LogFolder "$($env:COMPUTERNAME)-ADCheck.csv"

$CleanErrorMessage = $ErrorMessage -replace "(`r`n|`n|`r)", " "
$CleanErrorMessage = $CleanErrorMessage.Trim()

$Result = [PSCustomObject]@{
    Timestamp             = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    ComputerName          = $env:COMPUTERNAME
    UserName              = "$env:USERDOMAIN\$env:USERNAME"
    DC_Assigned           = $DC_Name
    DC_IP                 = $DC_IP
    Ping_ResponseMS       = $PingTime
    LDAP_DC_Used          = $LDAP_DC_Used
    LDAP_ResponseMS       = $LDAP_ResponseMS
    LDAP_Status           = $LDAP_Status
    SecureChannel_Status  = $SecureChannel_Status
    Error_Message         = $CleanErrorMessage
}

$AppendHeader = -not (Test-Path $CSV_File)
$Result | Export-Csv -Path $CSV_File -NoTypeInformation -Append -Force
if ($AppendHeader) { Write-Host "  Created new CSV file: $CSV_File" }
else { Write-Host "  Appended to existing CSV: $CSV_File" }

Write-Host ""
Write-Host "[ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ] AD connectivity check completed."
