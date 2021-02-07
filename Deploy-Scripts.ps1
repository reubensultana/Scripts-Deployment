<#
.SYNOPSIS
    Executes a list of SQL script files agianst a list of SQL Server instances.

.DESCRIPTION
    Based on an open-source project hosted at https://github.com/reubensultana/Scripts-Deployment  
    Reads a text file containing a list of Servers, another file containing a list of TSQL Scripts, and executes all of the scripts against the list of remote servers.
    The output is stored as text in a LOG file in a subfolder, using the time stamp name for the file name.

.PARAMETER ServerListFile
    A text file containing the list of servers where the scripts will be executed/deployed.
    NOTE: the files must exist (DOH!) and have to have a SQL extension.

.PARAMETER ScriptListFile
    A text file containing the paths to the list of files that will be executed/deployed.
    NOTE: each script must contain the name of the affected database, otherwise execution will default to "master".

.PARAMETER ConnectionTimeout
    Specifies the number of seconds when this cmdlet times out if it cannot successfully connect to an instance of the Database Engine. The timeout value must be an integer value between 0 and 65534. If 0 is specified, connection attempts do not time out.

.PARAMETER QueryTimeout
    Specifies the number of seconds before the queries time out. If a timeout value is not specified, the queries do not time out. The timeout must be an integer value between 1 and 65535.

.Example
    Parameters inline: 
    .\Deploy-Scripts.ps1 -ServerListFile .\ServerList.txt -ScriptListFile .\FileList.txt -ConnectionTimeout 60 -QueryTimeout 60

.Example
    This will use defaults for ConnectionTimeout and QueryTimeout: 
    .\Deploy-Scripts.ps1 -ServerListFile .\ServerList.txt -ScriptListFile .\FileList.txt

.Example
    Parameter values in variables: 
    [string] $ServerListFile = ".\ServerList.txt"
    [string] $ScriptListFile = ".\FileList.txt"
    .\Deploy-Scripts.ps1 -ServerListFile .\ServerList.txt -ScriptListFile .\FileList.txt -ConnectionTimeout 60 -QueryTimeout 60

.Example
    This is my favourite example. Passing parameter values using Splatting:
    $Params = @{
        ServerListFile      = ".\ServerList.txt"
        ScriptListFile      = ".\FileList.txt"
        ConnectionTimeout   = 60
        QueryTimeout        = 60
        Verbose             = $true
    }
    .\Deploy-Scripts.ps1 @Params 

#>
# get generic params/configuration
[CmdletBinding()]
param(
    [Parameter(Position=0, Mandatory=$true)] [IO.FileInfo] $ServerListFile,
    [Parameter(Position=1, Mandatory=$true)] [IO.FileInfo] $ScriptListFile,
    [Parameter(Position=2, Mandatory=$false)] [int] $ConnectionTimeout = 60,
    [Parameter(Position=3, Mandatory=$false)] [int] $QueryTimeout = 60
)
Set-PSDebug -Strict
<#
# ----- TEST VALUES ----- #
[string] $ServerListFile = ".\ServerList.txt"
[string] $ScriptListFile = ".\FileList.txt"
[int] $ConnectionTimeout = 60
[int] $QueryTimeout = 60
#>

#region set default values if missing
if ($null -eq $ServerListFile)      {$ServerListFile = ".\ServerList.txt"}
if ($null -eq $ScriptListFile)      {$ScriptListFile = ".\FileList.txt"}
if ($null -eq $ConnectionTimeout)   {$ConnectionTimeout = 60}
if ($null -eq $QueryTimeout)        {$QueryTimeout = 60}
#endregion

#region set variable
[string] $ApplicationName="Script-Deployment"
[string] $ConnectionStringTemplate = "Server={0};Database={1};Integrated Security={2};Application Name={3};Connection Timeout={4};"
[string] $RemoteServerConnection = ""
[string] $ServerName = ""
[int] $ListeningPort = ""
[bool] $IsAlive = $false
$ActualServerList = New-Object System.Collections.ArrayList
$ActualFileList = New-Object System.Collections.ArrayList

# variables used for logging
[string] $LogFolder = "$($(Get-Location).Path)\LOG"
[string] $LogFileName = "$(Get-Date -Format 'yyMMddHHmmssfff')"
[string] $LogFilePath = "$LogFolder\$LogFileName.log"
# check and create logging subfolder/s
if ($false -eq $(Test-Path -Path $LogFolder -PathType Container -ErrorAction SilentlyContinue)) {
    $null = New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction SilentlyContinue
}

# NOTE: the Write-Log function has to be copied inside the RemoteScripptBlock since the functionality will run in a seperate process
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)] [string] $LogFilePath,
        [Parameter(Mandatory=$true, Position=1)] [string] $LogEntry
    )
    try {
        $LogEntry = "$(Get-Date -Format 'yy-MM-dd HH:mm:ss:fff') : $LogEntry"
        $LogEntry | Out-File -FilePath $LogFilePath -Append
        # output whatever is logged if -Verbose is defined when calling the script
        if ($VerbosePreference -eq [System.Management.Automation.ActionPreference]::Continue) {Write-Verbose $LogEntry}
    }
    catch { <# do nothing #> }
}

#region get list of remote servers and files to execute
# check Server List
if ($false -eq (Test-Path $ServerListFile -PathType Leaf)) {
    Write-Log -LogFilePath $LogFilePath -LogEntry "The Server List file could not be found."
    return
}
else { $SQLServers = Get-Content -Path $ServerListFile }
# check File List
if ($false -eq (Test-Path $ScriptListFile -PathType Leaf)) {
    Write-Log -LogFilePath $LogFilePath -LogEntry "The File List file could not be found."
    return
}
else { $InputFileList = Get-Content -Path $ScriptListFile }
# apply more checks and build the list of actual Servers and SQL files
# check if any
if ($SQLServers.Count -eq 0) {
    Write-Log -LogFilePath $LogFilePath -LogEntry "No servers were provided." 
    return
}
# verify connectivity to each server
Write-Log -LogFilePath $LogFilePath -LogEntry "Verifying connectivity to the list of servers - this might take a while..."
foreach ($Server in $SQLServers) {
    # extract parts
    $ServerName = $Server.Split(",")[0]
    $ListeningPort = $Server.Split(",")[1]
    # one more check to remove instance name...
    if ($true -eq $ServerName.Contains("\")) {$ServerName = $ServerName.Split("\")[0]}
    # check TCP connection on the specified port and stop execution on failure
    try { (New-Object System.Net.Sockets.TcpClient).Connect($ServerName,$ListeningPort); $IsAlive = $true } 
    catch { $IsAlive = $false } 
    finally {} 
    # add to the array
    if ($true -eq $IsAlive) { 
        $ActualServerList.Add($Server.ToString()) > $null # suppress output
        Write-Log -LogFilePath $LogFilePath -LogEntry "Adding $Server to the actual list."
    }
    else { 
        Write-Log -LogFilePath $LogFilePath -LogEntry "The $Server could not be reached."
    }
}
# check again...
if ($ActualServerList.Count -eq 0) {
    Write-Log -LogFilePath $LogFilePath -LogEntry "No valid servers were provided."
    return
}

# check if any
if ($InputFileList.Count -eq 0) {
    Write-Log -LogFilePath $LogFilePath -LogEntry "No script files were provided." 
    return
}
# verify existence of each file
Write-Log -LogFilePath $LogFilePath -LogEntry "Verifying the list of script files"
foreach ($File in $InputFileList) {
    # only SQL files allowed; and check if file exists
    if (($File -like "*.sql") -and (Test-Path $File -PathType Leaf)) {
        # add to the array
        $ActualFileList.Add($(Resolve-Path -Path $File).Path) > $null # suppress output
        Write-Log -LogFilePath $LogFilePath -LogEntry "Adding $File to the actual list."
    }
    else { 
        Write-Log -LogFilePath $LogFilePath -LogEntry "The file $File has been excluded."
    }
}
# check again...
if ($ActualFileList.Count -eq 0) {
    Write-Log -LogFilePath $LogFilePath -LogEntry "No valid script files were provided." 
    return
}
#endregion
<# -------------------------------------------------- #>
# if all good, then continue...


#region remote script - this is the workhorse
$RemoteScriptBlock = { 
    param(
        [Parameter(Position=1, Mandatory=$true)] [string] $RemoteServerName,
        [Parameter(Position=2, Mandatory=$true)] [string] $RemoteServerConnection,
        [Parameter(Position=3, Mandatory=$true)] [System.Array] $FileList,
        [Parameter(Position=4, Mandatory=$true)] [int]    $QueryTimeout = 60,
        [Parameter(Position=5, Mandatory=$true)] [string] $LogFilePath
    )
<#
# test the Remote Script Block
[string] $RemoteServerName = "MyDatabaseServer.contoso.com,1433"
[string] $RemoteServerConnection = "Server=MyDatabaseServer.contoso.com,1433;Database=master;Integrated Security=true;Application Name=Script-Deployment;Connection Timeout=60;"
[System.Array] $FileList = @(
    '.\foo.sql',
    '.\man.sql'
    '.\choo.sql'
)
[int]    $QueryTimeout = 600
#>
    $Err = $null
    [int] $Success = 0
    [string] $ErrorMessage = ""
    
    # NOTE: the function has to be copied inside the RemoteScripptBlock since the functionality will run in a seperate process
    function Write-Log {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true, Position=0)] [string] $LogFilePath,
            [Parameter(Mandatory=$true, Position=1)] [string] $LogEntry
        )
        try {
            $LogEntry = "$(Get-Date -Format 'yy-MM-dd HH:mm:ss:fff') : $LogEntry"
            $LogEntry | Out-File -FilePath $LogFilePath -Append
            # output whatever is logged if -Verbose is defined when calling the script
            if ($VerbosePreference -eq [System.Management.Automation.ActionPreference]::Continue) {Write-Verbose $LogEntry}
        }
        catch { <# do nothing #> }
    }

    # check if any files (even though we checked earlier)
    if ($FileList.Count -gt 0) {
        Write-Log -LogFilePath $LogFilePath -LogEntry "  Processing $RemoteServerName"
        # start file loop
        foreach ($SqlFile in $FileList) {
            try {
                Write-Log -LogFilePath $LogFilePath -LogEntry "  Running $($SqlFile.ToString())"
                # execute remote query, using Windows Authentication
                Invoke-Sqlcmd -ConnectionString $RemoteServerConnection -InputFile $($SqlFile.ToString()) -QueryTimeout $QueryTimeout `
                    -MaxCharLength 32768 -OutputSqlErrors $true -ErrorAction Stop
            
                # report success
                $Success = 1
                $ErrorMessage = ""
                Write-Log -LogFilePath $LogFilePath -LogEntry "  File executed successfully."
            }
            catch { 
                # Write-Host "Caught an exception:" -ForegroundColor Red
                # Write-Host "Exception type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
                # Write-Host "Exception message: $($_.Exception.Message)" -ForegroundColor Red
                # Write-Host "Error: " $_.Exception -ForegroundColor Red   
                $Err = $_
                $Success = 0
                $ErrorMessage = $($_.Exception.Message)
                Write-Log -LogFilePath $LogFilePath -LogEntry "  $ErrorMessage"
                break # On Error Exit the ForEach Loop (?)
                }
            finally { 
                # clean up
            }
        } # end file loop
        Write-Log -LogFilePath $LogFilePath -LogEntry "  Process complete."
    } # end check

    # return
    return $Err
}
#endregion


#region set up Runspace Pool
[int] $MaxRunningJobs = $($env:NUMBER_OF_PROCESSORS + 1) # number of Logical CPUs
$DefaultRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
$RunspacePool = [RunspaceFactory]::CreateRunspacePool(1,$MaxRunningJobs)
$RunspacePool.ApartmentState = "MTA" # avalable values: MTA (multithreaded), STA (single-threaded) 
$RunspacePool.Open()
$Runspaces = @()
#endregion


#region execute script on remote servers
[string] $InstanceLongPortName = ""
Write-Log -LogFilePath $LogFilePath -LogEntry "Starting job on:"
$timer = [System.Diagnostics.Stopwatch]::StartNew()

# Log Collector Start
# start jobs on all servers
ForEach($Server in $ActualServerList) { 
    $InstanceLongPortName = $Server
    Write-Log -LogFilePath $LogFilePath -LogEntry "> $InstanceLongPortName"
    # build connection string from template
    $RemoteServerConnection = $ConnectionStringTemplate -f $InstanceLongPortName, "master", "true", $ApplicationName, $ConnectionTimeout
    
    $ConcurrentQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $Runspace = [PowerShell]::Create()
    $null = $Runspace.AddScript($RemoteScriptBlock)
    $null = $Runspace.AddArgument($InstanceLongPortName)
    $null = $Runspace.AddArgument($RemoteServerConnection)
    $null = $Runspace.AddArgument($ActualFileList)
    $null = $Runspace.AddArgument($QueryTimeout)
    $null = $Runspace.AddArgument($LogFilePath)
    $Runspace.RunspacePool = $RunspacePool
    $Runspaces += [PSCustomObject]@{ Pipe = $Runspace; Status = $Runspace.BeginInvoke() }
    
    # While streaming ...
    while ($Runspaces.Status.IsCompleted -notcontains $true) {
        $item = $null
        if ($ConcurrentQueue.TryDequeue([ref]$item)) { "$item" }
    }
    # Drain the stream as the Runspace is closed, just to be safe
    if ($ConcurrentQueue.IsEmpty -ne $true) {
        $item = $null
        while ($ConcurrentQueue.TryDequeue([ref]$item)) { "$item" }
    }
    foreach ($Runspace in $Runspaces) {
        [void]$Runspace.Pipe.EndInvoke($Runspace.Status) # EndInvoke method retrieves the results of the asynchronous calls
        $Runspace.Pipe.Dispose()
    }

}

[int] $secs = $timer.Elapsed.TotalSeconds
Write-Log -LogFilePath $LogFilePath -LogEntry "----------"
Write-Log -LogFilePath $LogFilePath -LogEntry "Servers processed: $($ActualServerList.Count)"
Write-Log -LogFilePath $LogFilePath -LogEntry "Duration: $secs seconds"

$RunspacePool.Close()
$RunspacePool.Dispose()

# clean up SQL connections and reset Default Runspace
[System.Data.SQLClient.SqlConnection]::ClearAllPools()
[System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $DefaultRunspace
#endregion

#region clean up

#endregion
