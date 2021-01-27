<#
.SYNOPSIS
	Deploys a list of scripts to one or more databases.
.DESCRIPTION
    Based on an open-source project hosted at https://github.com/reubensultana/Scripts-Deployment
    Reads a text file containing a list of databases, another file containing a list of scripts, and executes all of the scripts against the list of databases.
    The output is stored as text in a LOG file in the specified folder, using the database name for the file name.
.PARAMETER scriptListFile
	The path to the list of scripts that will be executed against the list of databases. This parameter is mandatory.
.PARAMETER databaseListFile
	The path to the list of databases that will be affected by the list of scripts. This parameter is mandatory.
.PARAMETER serverInstance
    The name of the SQL Server hosting the databases. This parameter is mandatory and defaults to "localhost".
.PARAMETER sqlAuthCredential
    The PSCredential object holding the credentials used for SQL Authentication ONLY. This is an optional parameter.
.PARAMETER logFilePath
	The full path to the folder where the log/s will be written. Does not need to exist. This parameter is required.
.PARAMETER queryTimeout
    Specifies the number of seconds before the queries time out. If not specified it will default to 3600 (1 hour). The timeout must be an integer value between 1 and 65535.
.EXAMPLE
Using Windows Authentication
	.\Deploy-Scripts.ps1 -scriptListFile ".\scriptslist.txt" -databaseListFile ".\databaselist.txt" -serverInstance "localhost" -logFilePath "C:\TEMP" -QueryTimeout 7200
.EXAMPLE
    Using SQL Authentication and code
    First create a PSCredential object to avoid entering the Username and Password in clear text
    [string] $username="testuser"
    [System.Security.SecureString] $pass = ConvertTo-SecureString "testuserpassword" -AsPlainText -Force
    $sqlAuthCredential = New-Object System.Management.Automation.PSCredential ($username, $pass)

    Another approach would be to launch a prompt window
    $sqlAuthCredential = Get-Credential -Message "Enter credentials used for SQL Authentication"

    .\Deploy-Scripts.ps1 -scriptListFile ".\scriptslist.txt" -databaseListFile ".\databaselist.txt" -serverInstance "localhost" -sqlAuthCredential $sqlAuthCredential -logFilePath "C:\TEMP" -QueryTimeout 7200
.EXAMPLE
    Using SQL Authentication with prompt window
    $sqlAuthCredential = Get-Credential -Message "Enter credentials used for SQL Authentication"

    .\Deploy-Scripts.ps1 -scriptListFile ".\scriptslist.txt" -databaseListFile ".\databaselist.txt" -serverInstance "localhost" -sqlAuthCredential $sqlAuthCredential -logFilePath "C:\TEMP" -QueryTimeout 7200
.OUTPUTS
	None, unless -Verbose is specified. In fact, -Verbose is recommended so you can see what's going on and when.
.NOTES
    No additional information at this time.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [IO.FileInfo] $scriptListFile,
    [Parameter(Mandatory=$true)] [IO.FileInfo] $databaseListFile,
    [Parameter(Mandatory=$true)] [String] $serverInstance = "localhost",
    [Parameter(Mandatory=$false)] [PSCredential] $sqlAuthCredential, # Optional: if empty Windows Authentication will be used
    [Parameter(Mandatory=$true)] [String] $logFilePath, # using specific data type to ensure target folder exists
    [Parameter(Mandatory=$false)] [int] $queryTimeout = 3600  # Optional: in seconds => defaults to 60 minutes
)
#---------------------------------------------------------[Initialisations]--------------------------------------------------------
Set-StrictMode -Version Latest;
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force;

Clear-Host;

#----------------------------------------------------------[Declarations]----------------------------------------------------------
[string] $logFileNameTemplate = "$logFilePath\$($serverInstance.Replace("\", "$"))_{0}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log";
[string] $logFileName = "";
[string] $scriptExecPath = "";

#-----------------------------------------------------------[Functions]------------------------------------------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True, Position=0)]  [String] $LogFilePath,
        [Parameter(Mandatory=$False, Position=1)] [String] $Entry = '',
        [Parameter(Mandatory=$False, Position=2)] [Bool]   $OutputAnyway = $False
    )
    try {
        # prepend date and time
        $Entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') : $Entry";

        $Entry | Out-File -FilePath $LogFilePath -Append;
        # write output (visible only when the "Verbose" parameter is set)
        # output to console if Verbose if not selected
        if ($True -eq $OutputAnyway) { Write-Output $Entry }
        else { Write-Verbose $Entry };
    }
    catch { <# do nothing #> }
}


#-----------------------------------------------------------[Execution]------------------------------------------------------------
# build an array of databases, in the order they will be affected
$databaselist = New-Object System.Collections.ArrayList
# read list of files from the "configuration" text file
$databases = Get-Content -Path $databaseListFile
# verify that the files adhere to specific criteria
ForEach ($database in $databases) {
    $databaselist.Add($database.ToString()) > $null
}

# build an array of files, in the order they have to be executed
$filelist = New-Object System.Collections.ArrayList
# read list of files from the "configuration" text file
$ScriptFiles = Get-Content -Path $scriptListFile
# verify that the files adhere to specific criteria
ForEach ($ScriptFile in $ScriptFiles) {
    # only SQL files allowed; check if the file exists
    if (($ScriptFile -like "*.sql") -and (Test-Path $ScriptFile -PathType Leaf)) {
        # NOTE: The "> $null" part is to remove the array item index output
        $filelist.Add($ScriptFile.ToString()) > $null;
    }
    else { "File '{0}' could not be found or does not have a valid file extension." -f $ScriptFile.ToString() }
}

if ((Test-Path -Path $logFilePath -PathType Container) -eq $false) {
    # if the folder does not exist, create it and do not return any output
    New-Item -Path $logFilePath -ItemType Directory -ErrorAction SilentlyContinue > $null;
}

# read and deploy scripts to the SQL Server instance
if (($databaselist.Count -gt 0) -and ($filelist.Count -gt 0)) {
    # load and run the scripts listed against each database

    # write some output
    Write-Host ""
    Write-Host "Deploying these files:"
    ForEach ($script In $filelist) { Write-Host " > $($script.ToString())" }
    Write-Host ""
    Write-Host "To these databases:"
    ForEach ($dbname In $databaselist) { Write-Host " > $($dbname.ToString())" }
    Write-Host ""

    # start loop
    ForEach ($dbname In $databaselist) {
        # create a log file for each database
        $logFileName = $($logFileNameTemplate -f $dbname);
        Write-Log -LogFilePath $logFileName -Entry $("Starting deployment of $($filelist.Count) scripts to $dbname database on $serverInstance") -OutputAnyway $True;
        Write-Log -LogFilePath $logFileName -Entry "---------------------------------------------------------------------------";

        try {
            ForEach ($script In $filelist) {
                $scriptExecPath = $script.ToString()
                # check if the file exists, again
                if (Test-Path $scriptexecpath -PathType Leaf) {
                    Write-Log -LogFilePath $logFileName -Entry $("Running script: $scriptExecPath");
                    try { 
                        if ($null -eq $sqlAuthCredential) { 
                            # use Windows Authentication
                            Invoke-Sqlcmd -ServerInstance $serverInstance -Database $dbname -InputFile $scriptExecPath -AbortOnError -QueryTimeout $QueryTimeout; }
                        else { 
                            # use SQL Authentication (NOTE: Username and Password sent in clear text - this is by design)
                            Invoke-Sqlcmd -ServerInstance $serverInstance -Database $dbname -InputFile $scriptExecPath -AbortOnError -QueryTimeout $QueryTimeout -Credential $sqlAuthCredential; }
                    }
                    catch { 
                        Write-Log -LogFilePath $logFileName -Entry $($error[0].Exception);
                        break 
                    } # On Error, exit the script ForEach Loop and start next database
                }
                else { 
                    Write-Log -LogFilePath $logFileName -Entry $("Script '$scriptExecPath' could not be found");
                }
            }
            # end script file loop
        }
        catch { 
            #throw;
        }
        Write-Log -LogFilePath $logFileName -Entry "---------------------------------------------------------------------------";
        Write-Log -LogFilePath $logFileName -Entry "Script execution complete";
        Write-Verbose "";
    }
    # end database loop
    Write-Host "Process complete.";
}


#-----------------------------------------------------------[ClearMemory]------------------------------------------------------------
# deallocate variables
$databaselist = $null
$filelist = $null
$script = $null
$scriptexecpath = $null
