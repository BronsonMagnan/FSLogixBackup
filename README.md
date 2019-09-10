# FSLogixBackup
Backup Engine for FSLogix Profiles store on Scale Out File Servers

#Usage

```.\Backup-FSLogixProfile.ps1 -ProfilePath "\\sofs.corp.contoso.com\ProfileDisks" -BackupPath "E:\Profiles" -LogPath "E:\ProfileBackups"```

#Parameter description
The script takes 4 parameters, 1 is optional.
1. ProfilePath - this is the path to the SOFS share that contains either FSLogix Profiles or ODFC Containers
2. BackupPath - this is the path to the Backup Storage, the program will create subfolders per user, and subfolders under each user for "Profile" or "ODFC" backups
3. LogPath - this is the folder where the log should be written. The log will be generated with the date in it, once per day.
4. MountFolder - defaults to c:\Mount, this is where the VHDX files are mounted while the backup is being performed.
5. There is a hidden parameter in the code that controls the length of the backup window, currently set to five hours before stopping.

#Requirements
The service account running this script needs full access to the SOFS share, full access to the backup and logging repositories. The virtual machine executing this script needs to have hyper-v installed because it is running the VHD cmdlets. So that means that exposeVirtualizationExtensions must be set to true on the hyper-v VMProcessor.

#Code flow description:
1. The backup path, mount folder, time limit, and log file path are loaded into a Preference object.
2. the ProfileSearch class is instantiated with the path to the SOFS share. The class constructor will parse all folders containing a SID and convert them into objects of type FSLogixProfile and store them in an internal collection.
3. The JobEngine class is instantiated with the Prferences Object
4. The JobDispatcher class is instantied with the Preferences Object as well as the collection from ProfileSearch using the method getSearchResults().
5. The Dispatch method on JobDispatcher is called which will evaluate each FSLogixProfile object on whether is a Profile VHDX or an OFDC VHDX. An instance of the JobEngine class is passed in as an argument.
5.1. Depending on the type a temporary value BackupTarget is constructed from the ProfileBackupTarget or ODFCBackupTarget class, accepting the BackupStorage root folder from the Preferences object.
5.2. A temporary value BackupJob is constructed from the FSLogixProfileBackupJob class or the FSLogixOFDCBackup class, which uses the data from BackupTarget, as well as getUserName() from the JobDispatcher's FSLogixProfile collection, getPath() from the BackupTarget descendent, and the mount location which came from the Preferences object.
5.3. The dispatch method then calls the AddJob() method of the JobEngine class.
6. The main program tells the jobEngine class to execute the start() method, and the start time is recorded, and the logFile subclass is instantiated
6.1. The start method will iterate through the collection of internal jobs, depending on the state of the system clock compared to the value of the start time plus the time limit, each Job classes main() or cancel(), both of which are passed the logFile object.
6.2. The job object is either of class FSLogixODFCBackupJob or FSLogixProfileBackupJob, the difference is each one implements a different interface for their backup() method utilizing a child of class BackupInterface, either iODFCBackup or iProfileBackup respectively. Since this algorithm is chosen at runtime, is it using the Strategy design pattern.
6.3. The job object's main() method does as follows:
6.3.1. Validates the backup path
6.3.2. Validates the VHDX file is not open
6.3.3. Refreshes the mount point.
6.3.4. Mounts the VHDX
6.3.5. Executes the backup() method
6.3.5.1. The backupStrategy's backup() method is called
6.3.5.2. The backupStrategy's GetLog() method is called, which returns the Robocopy log header and footer
6.3.5.3. The returned log is injested into our program's log.
6.3.6. Removes the access path
6.3.7. Optimizes the VHDX
6.3.8. Dismounts the VHDX
6.3.9. Cleans up the mount point


#Class UML Diagram
![Class UML Diagram](https://github.com/BronsonMagnan/FSLogixBackup/blob/master/ClassUML.png)

#Logging samples
![Console Log](https://github.com/BronsonMagnan/FSLogixBackup/blob/master/ConsoleLog.png)
![Log File](https://github.com/BronsonMagnan/FSLogixBackup/blob/master/LogFile.png)
