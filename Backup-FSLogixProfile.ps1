param(
    [parameter(Mandatory)][validateNotNullOrEmpty()][string]$ProfilePath,
    [parameter(Mandatory)][validateNotNullOrEmpty()][string]$BackupPath,
    [parameter(Mandatory)][validateNotNullOrEmpty()][string]$LogPath,
    [validateNotNullOrEmpty()][string]$MountFolder = "X:\Mount"
)

#region class LogFile

class logFile {
    [string]$Path
    hidden [string]$DateTimePattern = "yyyyMMdd-HHmmss"
    logFile([string]$Path) {
        $this.Path = $Path
        $this.InitLogFile()
    }
    [void]InitLogFile() {
        if (-not (Test-Path $this.Path -ErrorAction SilentlyContinue)) {
            new-item -ItemType File -Path (Split-Path -Path $this.Path -Parent) -Name (Split-Path -Path $this.Path -Leaf) | Out-Null
        } 
        Add-Content -Path $this.Path -Value $("*" * 50)
        $message = "Log Initilized {0:$($this.DateTimePattern)}" -f $(get-date)
        Add-Content -Path $this.Path -Value $($message)
    }
    hidden [string]DateStamp([string]$message) {
        return $("[{0:$($this.DateTimePattern)}]" -f (get-date)) +$message
    }
    hidden [void]WriteFile([string]$message){
        Add-Content -Path $this.Path $this.DateStamp($message)
    }
    hidden [void]WriteScreen([string]$message){
        Write-Information $this.DateStamp($message) -InformationAction Continue
    }
    [void]Write([boolean]$echo,[string]$Severity,[string]$Message) {
        $prefix = ""
        switch ($Severity) {
            'Error' {
                $prefix = "[Error]";
            }
            'Warn' {
                $prefix = "[Warn]";
            }
            'Info' {
                $prefix = "[Info]";
            }
            default {
                $prefix = "[Info]"
            }
        }
        if ($echo) { $this.WriteScreen($prefix + $message) }
        $this.WriteFile($prefix + $message) 
    }
    [void]Write([string]$Message) {
        $this.write("Info",$Message)
    }
    [void]Write([string]$Severity,[string]$Message) {
        $this.write($true,$severity,$message)
    }
}
#endregion

#region Backup Strategy Interfaces 

class BackupInterface {
    [string]$Source
    [string]$Destination
    hidden [string]$robocopyLog
    BackupInterface([string]$Source,[string]$Destination) {
        $this.Source = $Source
        $this.Destination = $Destination
        $this.robocopyLog = (New-TemporaryFile).FullName
    }
    [void]Backup() {
    }
    [string[]]GetFullLog() {
        #This might require some adjustment - the robocopy log can be HUGE on the initial backup
        $templog = @()
        $templog = get-content -Path $this.robocopyLog
        Remove-Item -Path $this.robocopyLog -Force -ErrorAction SilentlyContinue | Out-Null
        return $templog
    }
    [string[]]GetLog() {
        #This might require some adjustment - the robocopy log can be HUGE on the initial backup
        $templog = @()
        $templog = get-content -Path $this.robocopyLog
        $toplog = $templog | Select-Object -First 20
        $bottomlog = $templog | Select-Object -Last 10
        $summaryLog = $toplog + $bottomlog
        Remove-Item -Path $this.robocopyLog -Force -ErrorAction SilentlyContinue | Out-Null
        return $summaryLog
    }
}
class iProfileBackup : BackupInterface {
    iProfileBackup([string]$Source,[string]$Destination):base($Source,$Destination) {
    }
    [void]Backup() {
        $src = Join-Path -Path $this.Source -ChildPath "Profile"
        #robocopy "$src" "$($this.Destination)" /XO /XF *.ost /XJ /XD "System Volume Information" "$src\Appdata\Local" "$src\Appdata\LocalLow" /E /W:0 /R:0 /MT:100 /LOG:"$($this.robocopyLog)"
        robocopy "$src" "$($this.Destination)" /XO /XF *.ost *.lnk /XJ /XD "System Volume Information" "$src\Appdata\Local" "$src\Appdata\LocalLow" /E /PURGE /W:0 /R:0 /MT:100 /LOG:"$($this.robocopyLog)"
    }
}

class iODFCBackup : BackupInterface {
    #This Particular interface definetly has some optimization available to it.
    #Not really sure on what does and does not need to be excluded
    iODFCBackup([string]$Source,[string]$Destination):base($Source,$Destination) {
    }
    [void]Backup() {
        $src = Join-Path -Path $this.Source -ChildPath "ODFC"
        #robocopy "$src" "$($this.Destination)" /XO /XF *.ost /XJ /XD "System Volume Information" "$src\Appdata\Local" "$src\Appdata\LocalLow" /E /W:0 /R:0 /MT:100 /LOG:"$($this.robocopyLog)"
        robocopy "$src" "$($this.Destination)" /XO /XF *.ost *.lnk /XJ /XD "System Volume Information" "$src\Appdata\Local" "$src\Appdata\LocalLow" /E /PURGE /W:0 /R:0 /MT:100 /LOG:"$($this.robocopyLog)"
    }
}

#endregion

#region Cleanup Strategy Interfaces 
class CleanupInterface {
    [string]$TargetPath
    hidden [string]$cleanupLog
    CleanupInterface([string]$TargetPath) {
        $this.TargetPath = $TargetPath
        $this.cleanupLog = (New-TemporaryFile).FullName
    }
    [void]Cleanup(){
        #Virtual Implementation        
    }
    [void]Log([string]$Message) {
        add-Content $message -Path $this.cleanuplog
    }
    [string[]]GetLog() {
        $templog = @()
        $templog = get-content -path $this.cleanupLog
        remove-item -Path $this.cleanupLog -Force -ErrorAction SilentlyContinue | Out-Null
        return $templog
    }
}

class iProfileCleanup : CleanupInterface {
    iProfileCleanup([string]$TargetPath):base ($TargetPath) {
    }
    [void]Cleanup() {
        #Profile specific cleanup focus
        #temp files under appdata\local\temp
        $profilepath = join-path -Path $this.TargetPath -ChildPath "Profile"
        $AppData = join-path -path $profilepath -ChildPath "AppData"
        $LocalAppData = join-path $AppData -ChildPath "Local"
        $TempFolder = join-path $LocalAppData -ChildPath "Temp"
        if (test-path -Path $TempFolder -ErrorAction SilentlyContinue) {
            $this.Log("TempFolder Path is $TempFolder")
            $Contents = Get-ChildItem -Path $tempfolder -Recurse
            $SizeInMb = ($contents | Where-Object { ! $_.PSIsContainer} | Select-Object -ExpandProperty Length | Measure-Object -Sum).sum / 1mb
            $this.log("TempFolder is $SizeInMb MB in size")
            $this.log("Removing temp files")
            $contents | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

class iODFCCleanup: CleanupInterface {
    iODFCCleanup([String]$targetPath):base($targetPath){
    }
    [void]Cleanup(){
        #Not Implemented, not sure what to cleanup from these yet
    }
}
#endregion

#region BackupTarget Class hierarchy 
class BackupTarget {
    #Abstract
    hidden [string]$DevicePath
    hidden [string]$UserName
    hidden [string]$VHDType
    BackupTarget([string]$DevicePath,[string]$UserName) {
       $this.DevicePath = $DevicePath
       $this.UserName = $UserName
    }
    [string]getPath() { return $(Join-path -Path $this.DevicePath -ChildPath $this.UserName) }
    [void]InitPath() {
        if (-not ( Test-Path $this.getPath() ) ) { new-item -ItemType Directory -Path $this.getPath() }
    }
}

class ProfileBackupTarget : BackupTarget {
    ProfileBackupTarget ([string]$DevicePath,[string]$UserName) : base ($DevicePath, $UserName) {
        $this.InitPath()
    }
    [string]getPath() {
        return $(join-path -path ([BackupTarget]$this).getPath() -ChildPath "Profile")
    }
}
class ODFCBackupTarget : BackupTarget {
    ODFCBackupTarget([string]$DevicePath,[string]$UserName) : base ($DevicePath, $UserName) {
        $this.InitPath()
    }
    [string]getPath() {
        return $(join-path -path ([BackupTarget]$this).getPath() -ChildPath "ODFC")
    }
}

#endregion 

#region FSLogixProfile Class

class FSLogixProfile {
    hidden [string]$UserName
    hidden [string]$ProfileDiskPath = $null
    hidden [string]$ODFCDiskPath = $null
    FSLogixProfile([System.IO.DirectoryInfo]$ProfilePath) {
        $NullResult = $ProfilePath.Name -match "S-1-\d{1,2}-\d{2}-\d{8,10}-\d{8,10}-\d{8,10}-\d{1,5}"
        write-debug -Message "Regex output: $NullResult"
        $this.UserName = $ProfilePath.name.replace($Matches[0],"").replace("_","")
        $this.ProfileDiskPath = $ProfilePath | Get-ChildItem | Where-Object { $_.name -like "Profile*" } | Select-Object -ExpandProperty Fullname
        $this.ODFCDiskPath = $ProfilePath | Get-ChildItem | Where-Object { $_.name -like "ODFC*" } | Select-Object -ExpandProperty Fullname
    }
    [string]getUserName(){ return $this.UserName}
    [string]getProfileDiskPath() { return $this.ProfileDiskPath }
    [string]getODFCDiskPath() { return $this.ODFCDiskPath }
    [boolean]hasProfileDisk() { if ($this.ProfileDiskPath) { return $true } else { return $false } }
    [boolean]hasODFCDisk() { if ($this.ODFCDiskPath) { return $true } else { return $false } }
}

#endregion

#region Job Class hierarchy


class job {
    [string]$Name
    job([string]$Name){
        $this.name = $name
    }
    [void]Main([logFile]$Log) {
        $log.write("Starting job $($this.name)")
    }
    [void]Cancel([logFile]$Log) {
        $log.write("Canceling job $($this.name)")
    }
}

class VHDXBackupJob : Job {
    [string]$VHDXPath
    [string]$BackupPath
    [string]$MountFolder
    hidden [PSObject]$MountPoint
    [BackupInterface]$BackupStragety
    [CleanupInterface]$CleanupStrategy
    VHDXBackupjob([string]$Name,[string]$VHDXPath,[string]$BackupPath,[string]$MountFolder) : base ($Name) {
        $this.VHDXPath = $VHDXPath
        $this.BackupPath = $BackupPath
        $this.MountFolder = $MountFolder
    }
    hidden [boolean]TestOpenFile() {
        $fileInfo = New-Object System.IO.FileInfo $this.VHDXPath
        try {
            $fileStream = $fileInfo.Open( [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None )
            $filestream.Close()
            return $false
        } catch {
            return $true
        }
    }
    hidden [boolean]DestroyMountFolder() {
        if (Test-Path $this.mountFolder -ErrorAction SilentlyContinue) {
            $directoryInfo = Get-ChildItem $this,mountFolder -ErrorAction SilentlyContinue | Measure-Object
            #$directoryInfo.count #Returns the count of all of the files in the directory
            If ($directoryInfo.count -eq 0) {                            
                    Remove-Item $this.mountFolder -Recurse -Force
                    return $true
            } else {
                return $false
            }                                       
        } else {
            return $true 
        }
    }
    hidden [boolean]CreateMountFolder() {
        if (Test-Path $this.MountFolder -ErrorAction SilentlyContinue) {
            Remove-Item -Path $this.MountFolder -Force -Recurse
        }
        New-Item -ItemType Directory -Path (split-path -Path $this.MountFolder -Parent) -Name (Split-Path -Path $this.MountFolder -Leaf)
        if (Test-Path $this.MountFolder -ErrorAction SilentlyContinue)  {
            return $true
        } else {
            return $false
        }
    }
    hidden [void]MountWithAccessPath() {
        $this.mountPoint=Mount-VHD $this.VHDXPath -Passthru -Verbose | Get-Disk | Get-Partition | Where-Object {$_.Type -eq "Basic"} | Add-PartitionAccessPath -AccessPath $this.MountFolder -PassThru -Verbose | get-volume | select-object *        
    }
    hidden [void]RemoveAccessPath() {
        $diskNumber = (get-volume | Where-Object {$_.FileSystemLabel -eq $this.mountPoint.FileSystemLabel} | Get-Partition| Where-Object {$_.Type -eq "Basic"} | Get-disk).Number
        $partitionNumber = (get-volume | Where-Object {$_.FileSystemLabel -eq $this.mountPoint.FileSystemLabel} | Get-Partition| Where-Object {$_.Type -eq "Basic"}).PartitionNumber
        Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $partitionNumber -AccessPath $this.mountFolder
    }
    hidden [void]Dismount() {
        Dismount-VHD -Path $this.VHDXPath -Passthru -Verbose | out-null
    }
    hidden [double]MeasureSize() {
        return [math]::Round((Get-Item -Path $this.VHDXPath | Select-Object -ExpandProperty length)/1mb,2)
    }
    hidden [boolean]Optimize() {
        try {
            Optimize-VHD -Path $this.VHDXPath -Mode Full -verbose -ErrorAction SilentlyContinue
            return $true
        } catch {
            return $false
        }
    }
    hidden [string]GetVolumeLetter() {
        return (Split-Path -Path $this.MountFolder -Parent).substring(0,1)
    }


    hidden [boolean]ValidateBackupPath() {
        if (Test-Path -Path $this.BackupPath) {
            return $true
        } else {
            return $false
        }
    }
    [void]Backup([logFile]$log) {
        $log.Write("Starting backup")
        $this.BackupStragety.Backup()
        $log.Write("Injest Robocopy log")
        $templog = $this.BackupStragety.GetLog()
        foreach ($line in $templog) { $log.write($false,"Info","[Robocopy]"+$line) }
        $log.Write("End Robocopy Log")
    }
    [void]Cleanup([logfile]$log) {
        $log.write("Starting Cleanup")
        $this.CleanupStrategy.Cleanup()
        $log.Write("Inject Cleanup Log")
        $templog = $this.CleanupStrategy.GetLog()
        foreach ($line in $templog) { $log.write($false,"Info","[Cleanup]"+$line) }
        $log.write("End Cleanup Log")
    }
    [void]Main([logFile]$Log) {
        [double]$SizeBefore = 0
        [double]$SizeAfter = 0
        $jobStart = Get-Date #added
        ([job]$this).Main($Log)
        if ($this.ValidateBackupPath()) {
            #Test File Open
            if ($this.TestOpenFile()) {
                $log.write("Warn","File $($this.VHDXPath) is open by another system - skipping backup")
            } else {
                $log.write("Validated file $($this.VHDXPath) is not open by another system")
                $log.write("Clearing MountFolder at $($this.MountFolder)")        
                if ($this.CreateMountFolder()) {
                    $log.Write("Mounting the VHDX at $($this.VHDXPath)")
                    $this.MountWithAccessPath()
    
                    #Ready to Backup
                    Start-Sleep -Seconds 2
                    $this.Backup($log)

                    #Ready to start cleanup
                    start-sleep -Seconds 2
                    $this.Cleanup($log)

                    #Done with Backup
                  
                 
                    #Remove the access path
                    $log.Write("Removing the access path")
                    $this.RemoveAccessPath()

                    #Dismount the VHDX
                    $log.Write("Dismounting VHDX")
                    $this.Dismount()

                    #Critical test to ensure the disk is dismounted
                    if ($this.DestroyMountFolder()) {
                        $log.write("Cleaned up the mount folder")
                    } else {
                        $log.write("Error","Failed to cleanup mount folder, manually unmount vhdx, data could be at risk")
                        throw;
                    }
                    
                    #File System Consolidation requires a direct drive mount and not a mount point
                    #Optimize the file system
                    $driveletter = "O"
                    $log.write("Optimizing the file system")
                    $this.mountPoint = Mount-VHD $this.VHDXPath -Passthru -Verbose -NoDriveLetter
                    $this.mountPoint | Get-Disk | Get-Partition | Where-Object {$_.Type -eq "Basic"} | Add-PartitionAccessPath -AccessPath "$($driveletter):" -PassThru -Verbose | out-null
                    $WorkingVolume = $this.mountPoint | get-Disk | Get-Partition | Where-Object {$_.Type -eq "Basic"} | Get-Volume
                    $diskNumber = (get-volume | Where-Object {$_.FileSystemLabel -eq $WorkingVolume.FileSystemLabel} | Get-Partition | Where-Object {$_.Type -eq "Basic"} | Get-disk).Number
                    $partitionNumber = (get-volume | Where-Object {$_.FileSystemLabel -eq $WorkingVolume.FileSystemLabel} | Get-Partition| Where-Object {$_.Type -eq "Basic"} ).PartitionNumber
                    
                    #Defragment the volume
                    $DefragOutput = Optimize-Volume -DriveLetter $WorkingVolume.DriveLetter -Analyze -Defrag -verbose 4>&1
                    $DefragLog = $DefragOutput | ForEach-Object {$_.ToString()}
                    $DefragLog | ForEach-Object { $log.write("Info", $_) }

                    #Retrim the volume after defragmentation
                    $ReTrimOutput = Optimize-Volume -DriveLetter $WorkingVolume.DriveLetter -ReTrim -Analyze -SlabConsolidate -verbose 4>&1
                    $RetrimLog = $ReTrimOutput | ForEach-Object {$_.ToString()}
                    $RetrimLog | ForEach-Object { $log.write("Info", $_) }
                    

                    Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $partitionNumber -AccessPath "$($driveletter):"
                    Dismount-VHD -Path $this.VHDXPath -Passthru -Verbose | out-null

                    #Optimize the VHDX - only works if file system optimization ran and the disk is dismounted
                    $log.write("Optimizing VHDX")
                    $sizeBefore = $this.MeasureSize()
                    if ($this.Optimize()) {
                        $sizeAfter = $this.MeasureSize()
                        $Log.write("The VHDX was successfully shrunk Before Size - $sizeBefore | After Size - $sizeAfter")
                    } else {
                        $Log.write("Warn","There was an error optimizing VHDX - $($this.VHDXPath), this VHDX will not be shrunk")
                    }

    
                } else {
                    $log.Write("Error","Creating the mount folder failed")
                } #test mount folder
            } #test file open
        } else {
            $log.write("Error","Backup Storage Path $($this.BackupPath) is not Accessible")
        } #test backup storage location
        $jobEnd = Get-Date
        $duration = $jobEnd - $jobStart
        $log.write("Info","Job Duration: $($duration.totalSeconds) Seconds")
    }
    [void]Cancel([logFile]$Log) {
        ([job]$this).Cancel($Log)
    }

}

Class FSLogixProfileBackupJob : VHDXBackupJob {
    FSLogixProfileBackupJob([string]$Name,[string]$VHDXPath,[string]$BackupPath,[string]$MountFolder):base($Name,$VHDXPath,$BackupPath,$MountFolder) {
    }
    [void]Backup([Logfile]$log) {
        $this.BackupStragety = [iProfileBackup]::new($this.MountFolder,$this.BackupPath)
        ([VHDXBackupJob]$this).Backup($log)
    }
    [void]Cleanup([LogFile]$log) {
        $this.CleanupStrategy = [iProfileCleanup]::new($this.mountFolder)
        ([VHDXBackupJob]$this).Cleanup($log)
    }
}

class FSLogixODFCBackupJob : VHDXBackupJob {
    FSLogixODFCBackupJob([string]$Name,[string]$VHDXPath,[string]$BackupPath,[string]$MountFolder):base($Name,$VHDXPath,$BackupPath,$MountFolder) {
    }
    [void]Backup([Logfile]$log) {
        $this.BackupStragety = [iODFCBackup]::new($this.MountFolder,$this.BackupPath)
        ([VHDXBackupJob]$this).Backup($log)
    }
    [void]Cleanup([LogFile]$log) {
        $this.CleanupStrategy = [iODFCCleanup]::new($this.mountFolder)
        ([VHDXBackupJob]$this).Cleanup($log)
    }
}

#endregion

#region Preferences Class 

class Preferences {
    hidden [string] $StoragePath
    hidden [string] $MountLocation 
    hidden [timespan] $TimeLimit
    hidden [string] $LogFilePath 
    Preferences([string] $StoragePath, [string] $MountLocation,[timespan] $TimeLimit,[string] $LogFilePath){
        $this.StoragePath = $StoragePath
        $this.MountLocation = $MountLocation
        $this.TimeLimit = $TimeLimit
        $this.LogFilePath = $LogFilePath
    }
    [string]getStoragePath() { return $this.StoragePath }
    [string]getMountLocation() { return $this.MountLocation }
    [timespan]getTimeLimit() { return $this.TimeLimit }
    [string]getLogFilePath() { return $this.LogFilePath }
}


#endregion

#region ProfileSearch Class

class ProfileSearch {
    hidden[string]$BasePath
    hidden[FSLogixProfile[]]$ProfileList
    ProfileSearch ([string]$BasePath) {
        $this.BasePath = $BasePath
        $this.search()
    }
    [void]Search() {
        $folderList = @() 
        $folderList = Get-ChildItem -Path $this.BasePath -Recurse | Where-Object {$_.PSIsContainer -and $_.name -match "S-1-\d{1,2}-\d{2}-\d{8,10}-\d{8,10}-\d{8,10}-\d{1,5}" }
        $folderList.ForEach({$this.ProfileList += [FSLogixProfile]::new($_)})
    }
    [FSLogixProfile[]]getSearchResults() {
        return $this.ProfileList
    }
}

#endregion

#region Job Engine Class 

class JobEngine {
    [datetime]$StartTime
    [timespan]$JobWindow
    hidden [datetime]$TimeLimit
    hidden[logFile]$log
    hidden[job[]] $joblist 
    hidden[string]$logFilePath
    JobEngine([preferences]$Preferences) {
        $this.unpackPreferences($Preferences)
        $this.StartTime = get-date;
        $this.log = [logFile]::new( $this.logfilePath )
        $this.CalculateTimeLimit()
    }
    hidden [void]unpackPreferences([Preferences]$Preferences) {
        $this.JobWindow = $Preferences.getTimeLimit()
        $this.LogFilePath = $Preferences.getLogFilePath()
    }
    hidden [void]CalculateTimeLimit(){
        $this.TimeLimit = $this.StartTime.add($this.JobWindow)
    }
    hidden [boolean]InTimeWindow(){
        if ($this.TimeLimit -gt (get-date)) { return $true } else { return $false }
    }
    [void]AddJob([job]$Job) {
        $this.joblist += $Job
    }
    [void]Start(){
        $this.log.Write("Starting Job Engine for $($this.joblist.count) job(s)")
        foreach ($CurrentJob in $this.joblist) {
            if ($this.InTimeWindow()) { 
                $CurrentJob.Main($this.log)                                           
            } else {
                $CurrentJob.Cancel($this.log)
            }
        }
    }
}


#endregion

#region JobDispatcher Class 

class JobDispatcher {
    hidden [FSLogixProfile[]]$ProfileList
    hidden [string]$StoragePath
    hidden [string]$MountLocation
    JobDispatcher ([FSLogixProfile[]]$ProfileList,[Preferences]$Preferences) {
        $this.ProfileList = $ProfileList
        $this.UnpackPreferences($Preferences)
        if (-not(test-path $this.StoragePath) ) { new-item -ItemType Directory -Path $this.StoragePath }
    }
    hidden [void] UnpackPreferences([Preferences]$Preferences){
        $this.StoragePath = $Preferences.getStoragePath()
        $this.MountLocation = $Preferences.getMountLocation()
    }
    [void]Dispatch ([JobEngine]$Engine) {
        $this.ProfileList.Where({$_.hasProfileDisk()}).ForEach({
            $BackupTarget = [ProfileBackupTarget]::new($this.StoragePath,$_.getUserName())
            $BackupJob = [FSLogixProfileBackupJob]::new($_.GetUserName(),$_.GetProfileDiskPath(),$BackupTarget.getPath(),$this.MountLocation)
            $Engine.AddJob($BackupJob)
        }) 
        $this.ProfileList.Where({$_.hasODFCDisk()}).ForEach({
            $BackupTarget = [ODFCBackupTarget]::new($this.StoragePath,$_.getUserName())
            $BackupJob = [FSLogixODFCBackupJob]::new($_.GetUserName(),$_.GetODFCDiskPath(),$BackupTarget.getPath(),$this.MountLocation)
            $Engine.AddJob($BackupJob)
        })
    } 
}

#endregion



class BackupApplication {
    [Preferences]$Preferences
    [TimeSpan]$timeLimit
    [String]$LogFilePath
    [ProfileSearch]$ProfileSearch
    [JobEngine]$JobEngine
    [JobDispatcher]$Dispatcher
    BackupApplication($ProfilePath,$BackupPath,$MountFolder,$logPath) {
        $this.timeLimit = [TimeSpan]::new(5,0,0)
        $this.LogFilePath = $(join-path -path $LogPath -ChildPath $("ProfileBackup-{0:yyyyMMdd}.log" -f (get-date)))
        $this.Preferences = [Preferences]::new($BackupPath,$MountFolder,$this.timelimit,$this.logfilePath)
        $this.ProfileSearch = [ProfileSearch]::new($ProfilePath)
        $this.JobEngine =  [JobEngine]::new($this.preferences) 
        $this.Dispatcher = [JobDispatcher]::new($this.ProfileSearch.getSearchResults(),$this.Preferences)
    }
    [void] Start() {
        $this.Dispatcher.Dispatch($this.JobEngine)
        $this.JobEngine.Start()   
    }
}

$Application = [BackupApplication]::new($ProfilePath,$BackupPath,$MountFolder,$logPath)

#$Application = [BackupApplication]::new("\\fslogix\Profiles\","X:\Backups\","X:\Mount","X:\Log\")

$Application.start()

