//
//  RestoreViewController.m
//  SuccessionRestore
//
//  Created by Sam Gardner on 6/30/18.
//  Copyright © 2018 Sam Gardner. All rights reserved.
//

#import "RestoreViewController.h"
#include <spawn.h>
#include <sys/sysctl.h>
#import "libjb.h"
#import "unjail.h"
#import "NSTask.h"

int attach(const char *path, char buf[], size_t sz);

@interface RestoreViewController ()

@end

@implementation RestoreViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[UIApplication sharedApplication] setIdleTimerDisabled:TRUE];
    [[self outputLabel] setHidden:TRUE];
    [[self restoreProgressBar] setHidden:TRUE];
    _successionPrefs = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.samgisaninja.SuccessionRestore.plist"]];
    [self prepareAttachRestoreDisk];
}

- (void) viewDidAppear:(BOOL)animated{
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/MobileSoftwareUpdate/mnt1/sbin/launchd"]) {
        [[self fileListActivityIndicator] setHidden:TRUE];
        [[self startRestoreButton] setTitle:@"Erase iPhone" forState:UIControlStateNormal];
    }
    if ([[[[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/" error:nil] objectForKey:NSFileSystemFreeSize] unsignedLongLongValue] < 2147483648) {
        if (![[_successionPrefs objectForKey:@"delete-during"] isEqual:@(1)]) {
            UIAlertController *lowStorageAlert = [UIAlertController alertControllerWithTitle:@"Low storage space detected!" message:[NSString stringWithFormat:@"It is reccommended that you use low-storage mode to prevent the device from running out of storage while Succesion is running\nNote that if Succession exits while it is running, it is more likely to fail destructively, so... don't exit Succession, and you might want to run it from safe mode."] preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *useLowStorageModeAction = [UIAlertAction actionWithTitle:@"Use low storage mode" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self->_successionPrefs setObject:@(1) forKey:@"delete-during"];
                [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Library/Preferences/com.samgisaninja.SuccessionRestore.plist" error:nil];
                [self->_successionPrefs writeToFile:@"/var/mobile/Library/Preferences/com.samgisaninja.SuccessionRestore.plist" atomically:TRUE];
            }];
            UIAlertAction *useDefaultSettingsAction = [UIAlertAction actionWithTitle:@"Perform restore normally" style:UIAlertActionStyleCancel handler:nil];
            [lowStorageAlert addAction:useLowStorageModeAction];
            [lowStorageAlert addAction:useDefaultSettingsAction];
            [self presentViewController:lowStorageAlert animated:TRUE completion:nil];
        }
    }
}

- (IBAction)startRestoreButtonAction:(id)sender {
    if ([[_successionPrefs objectForKey:@"create_APFS_succession-prerestore"] isEqual:@(1)] || [[_successionPrefs objectForKey:@"create_APFS_orig-fs"] isEqual:@(1)]) {
        if (kCFCoreFoundationVersionNumber > 1349.56) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/snappy"]) {
                UIAlertController *needSnappy = [UIAlertController alertControllerWithTitle:@"Snappy required" message:@"Your current preferences indicate you would like to perform operations with APFS snapshots, but you do not have snappy installed. Please install snappy from https://repo.bingner.com" preferredStyle:UIAlertControllerStyleAlert];
                NSString *sources = [NSString stringWithContentsOfFile:@"/etc/apt/sources.list.d/cydia.list" encoding:NSUTF8StringEncoding error:nil];
                if (![sources containsString:@"bingner.com"]) {
                    UIAlertAction *addRepo = [UIAlertAction actionWithTitle:@"Add repository to cydia" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        NSDictionary *URLOptions = @{UIApplicationOpenURLOptionUniversalLinksOnly : @FALSE};
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://cydia.saurik.com/api/share#?source=https://repo.bingner.com/"] options:URLOptions completionHandler:nil];
                        
                    }];
                    [needSnappy addAction:addRepo];
                }
                UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil];
                [needSnappy addAction:dismissAction];
                [self presentViewController:needSnappy animated:TRUE completion:nil];
            } else {
                if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/MobileSoftwareUpdate/mnt1/sbin/launchd"]) {
                    UIAlertController *areYouSureAlert = [UIAlertController alertControllerWithTitle:@"Are you sure you would like to begin restoring" message:@"You will not be able to leave the app during the process" preferredStyle:UIAlertControllerStyleActionSheet];
                    UIAlertAction *beginRestore = [UIAlertAction actionWithTitle:@"Begin restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                        [[UIDevice currentDevice] setBatteryMonitoringEnabled:TRUE];
                        if ([[UIDevice currentDevice] batteryLevel] > 0.5) {
                            if ([[self->_successionPrefs objectForKey:@"create_APFS_succession-prerestore"] isEqual:@(1)]) {
                                NSTask *deletePreviousBackupSnapTask = [[NSTask alloc] init];
                                [deletePreviousBackupSnapTask setLaunchPath:@"/usr/bin/snappy"];
                                NSArray *deletePreviousBackupSnapTaskArgs = [[NSArray alloc] initWithObjects:@"-f", @"/", @"-d", @"succession-prerestore", nil];
                                [deletePreviousBackupSnapTask setArguments:deletePreviousBackupSnapTaskArgs];
                                [deletePreviousBackupSnapTask launch];
                                NSTask *createBackupSnapTask = [[NSTask alloc] init];
                                [createBackupSnapTask setLaunchPath:@"/usr/bin/snappy"];
                                NSArray *createBackupSnapTaskArgs = [[NSArray alloc] initWithObjects:@"-f", @"/", @"-c", @"succession-prerestore", nil];
                                [createBackupSnapTask setArguments:createBackupSnapTaskArgs];
                                [createBackupSnapTask launch];
                            }
                            [self successionRestore];
                        } else {
                            UIAlertController *lowBatteryWarning = [UIAlertController alertControllerWithTitle:@"Low Battery" message:@"It is recommended you have at least 50% battery charge before beginning restore" preferredStyle:UIAlertControllerStyleAlert];
                            UIAlertAction *cancelRestoreAction = [UIAlertAction actionWithTitle:@"Abort restore" style:UIAlertActionStyleDefault handler:nil];
                            UIAlertAction *startRestoreAction = [UIAlertAction actionWithTitle:@"Restore anyways" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                                if ([[self->_successionPrefs objectForKey:@"create_APFS_succession-prerestore"] isEqual:@(1)]) {
                                    NSTask *createBackupSnapTask = [[NSTask alloc] init];
                                    [createBackupSnapTask setLaunchPath:@"/usr/bin/snappy"];
                                    NSArray *createBackupSnapTaskArgs = [[NSArray alloc] initWithObjects:@"-f", @"/", @"-c", @"succession-prerestore", nil];
                                    [createBackupSnapTask setArguments:createBackupSnapTaskArgs];
                                    [createBackupSnapTask launch];
                                }
                                [self successionRestore];
                            }];
                            [lowBatteryWarning addAction:cancelRestoreAction];
                            [lowBatteryWarning addAction:startRestoreAction];
                            [self presentViewController:lowBatteryWarning animated:TRUE completion:nil];
                        }
                        [[UIDevice currentDevice] setBatteryMonitoringEnabled:FALSE];
                    }];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
                    [areYouSureAlert addAction:beginRestore];
                    [areYouSureAlert addAction:cancelAction];
                    [self presentViewController:areYouSureAlert animated:TRUE completion:nil];
                } else {
                    UIAlertController *attachingAlert = [UIAlertController alertControllerWithTitle:@"Mounting filesystem..." message:@"This step might fail, if it does, you may need to reboot to get this to work." preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [self mountRestoreDisk:[self->_theDiskString stringByAppendingString:@"s2s1"]];
                    }];
                    [attachingAlert addAction:okAction];
                    [self presentViewController:attachingAlert animated:TRUE completion:nil];
                }
            }
        } else {
            UIAlertController *snapshotsNotSupported = [UIAlertController alertControllerWithTitle:@"APFS operations not supported" message:@"You must be running iOS 10.3 or higher to use APFS features." preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismis" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self->_successionPrefs setObject:@(0) forKey:@"create_APFS_orig-fs"];
                [self->_successionPrefs setObject:@(0) forKey:@"create_APFS_succession-prerestore"];
                [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Library/Preferences/com.samgisaninja.SuccessionRestore.plist" error:nil];
                [self->_successionPrefs writeToFile:@"/var/mobile/Library/Preferences/com.samgisaninja.SuccessionRestore.plist" atomically:TRUE];
            }];
            [snapshotsNotSupported addAction:dismissAction];
            [self presentViewController:snapshotsNotSupported animated:TRUE completion:nil];
        }
    } else {
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/MobileSoftwareUpdate/mnt1/sbin/launchd"]) {
            UIAlertController *areYouSureAlert = [UIAlertController alertControllerWithTitle:@"Are you sure you would like to begin restoring" message:@"You will not be able to leave the app during the process" preferredStyle:UIAlertControllerStyleActionSheet];
            UIAlertAction *beginRestore = [UIAlertAction actionWithTitle:@"Begin restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [[UIDevice currentDevice] setBatteryMonitoringEnabled:TRUE];
                if ([[UIDevice currentDevice] batteryLevel] > 0.5) {
                    if ([[self->_successionPrefs objectForKey:@"create_APFS_succession-prerestore"] isEqual:@(1)]) {
                        NSTask *createBackupSnapTask = [[NSTask alloc] init];
                        [createBackupSnapTask setLaunchPath:@"/usr/bin/snappy"];
                        NSArray *createBackupSnapTaskArgs = [[NSArray alloc] initWithObjects:@"-f", @"/", @"-c", @"succession-prerestore", nil];
                        [createBackupSnapTask setArguments:createBackupSnapTaskArgs];
                        [createBackupSnapTask launch];
                    }
                    [self successionRestore];
                } else {
                    UIAlertController *lowBatteryWarning = [UIAlertController alertControllerWithTitle:@"Low Battery" message:@"It is recommended you have at least 50% battery charge before beginning restore" preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelRestoreAction = [UIAlertAction actionWithTitle:@"Abort restore" style:UIAlertActionStyleDefault handler:nil];
                    UIAlertAction *startRestoreAction = [UIAlertAction actionWithTitle:@"Restore anyways" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                        if ([[self->_successionPrefs objectForKey:@"create_APFS_succession-prerestore"] isEqual:@(1)]) {
                            NSTask *createBackupSnapTask = [[NSTask alloc] init];
                            [createBackupSnapTask setLaunchPath:@"/usr/bin/snappy"];
                            NSArray *createBackupSnapTaskArgs = [[NSArray alloc] initWithObjects:@"-f", @"/", @"-c", @"succession-prerestore", nil];
                            [createBackupSnapTask setArguments:createBackupSnapTaskArgs];
                            [createBackupSnapTask launch];
                        }
                        [self successionRestore];
                    }];
                    [lowBatteryWarning addAction:cancelRestoreAction];
                    [lowBatteryWarning addAction:startRestoreAction];
                    [self presentViewController:lowBatteryWarning animated:TRUE completion:nil];
                }
                [[UIDevice currentDevice] setBatteryMonitoringEnabled:FALSE];
            }];
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
            [areYouSureAlert addAction:beginRestore];
            [areYouSureAlert addAction:cancelAction];
            [self presentViewController:areYouSureAlert animated:TRUE completion:nil];
        } else {
            UIAlertController *attachingAlert = [UIAlertController alertControllerWithTitle:@"Mounting filesystem..." message:@"This step might fail, if it does, you may need to reboot to get this to work." preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self mountRestoreDisk:self->_theDiskString];
            }];
            [attachingAlert addAction:okAction];
            [self presentViewController:attachingAlert animated:TRUE completion:nil];
        }
    }
}

- (void) prepareAttachRestoreDisk{
    NSError *err;
    NSString *fstab = [NSString stringWithContentsOfFile:@"/etc/fstab" encoding:NSUTF8StringEncoding error:&err];
    if (!err) {
        if ([fstab containsString:@"hfs"]) {
            _filesystemType = @"hfs";
            [self attachRestoreDisk];
        } else if ([fstab containsString:@"apfs"]) {
            _filesystemType = @"apfs";
            [self attachRestoreDisk];
        } else {
            [self errorAlert:[NSString stringWithFormat:@"Unable to determine APFS or HFS\n%@", fstab]];
        }
    } else {
        [self errorAlert:[NSString stringWithFormat:@"Failed to read fstab: %@", [err localizedDescription]]];
    }
}

- (void) attachRestoreDisk {
    char theDisk[11];
    NSString *pathToDMG = @"/var/mobile/Media/Succession/rfs.dmg";
    attach([pathToDMG UTF8String], theDisk, sizeof(theDisk));
    _theDiskString = [NSString stringWithFormat:@"%s", theDisk];
}

-(void) mountRestoreDisk:(NSString *)attachedDMGDiskName{
    if ([self isMountPointPresent]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[self headerLabel] setHidden:TRUE];
            [[self infoLabel] setHidden:TRUE];
            [[self fileListActivityIndicator] setHidden:FALSE];
            [[self startRestoreButton] setTitle:@"Mounting, please wait..." forState:UIControlStateNormal];
            [[self startRestoreButton] setEnabled:FALSE];
        });
        NSArray *mountArgs = [NSArray arrayWithObjects:@"-t", _filesystemType, @"-o", @"ro", attachedDMGDiskName, @"/var/MobileSoftwareUpdate/mnt1", nil];
        NSTask *mountTask = [[NSTask alloc] init];
        mountTask.launchPath = @"/sbin/mount";
        mountTask.arguments = mountArgs;
        mountTask.terminationHandler = ^(NSTask *task){
            if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/MobileSoftwareUpdate/mnt1/launchd/"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[self headerLabel] setText:@"WARNING!"];
                    [[self infoLabel] setText:[NSString stringWithFormat:@"Running this tool will immediately delete all data from your device.\nPlease make a backup of any data that you want to keep. This will also return your device to the setup screen.\nA valid SIM card may be needed for activation on iPhones."]];
                    [[self headerLabel] setHidden:FALSE];
                    [[self infoLabel] setHidden:FALSE];
                    [[self startRestoreButton] setTitle:@"Erase iPhone" forState:UIControlStateNormal];
                    [[self startRestoreButton] setEnabled:TRUE];
                    [[self startRestoreButton] setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
                    [[self fileListActivityIndicator] setHidden:TRUE];
                    UIAlertController *mountSuccessful = [UIAlertController alertControllerWithTitle:@"Filesystem mounted successfully!" message:@"Tap 'Erase iPhone' to get this party started!" preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleDefault handler:nil];
                    [mountSuccessful addAction:dismissAction];
                    [self presentViewController:mountSuccessful animated:TRUE completion:nil];
                });
            } else {
                if ([attachedDMGDiskName hasSuffix:@"s2s1"]) {
                    [self mountRestoreDisk:[self->_theDiskString stringByAppendingString:@"s2"]];
                } else {
                    NSTask *umountTask;
                    [umountTask setLaunchPath:@"/sbin/umount"];
                    NSArray *umountArgs = [NSArray arrayWithObjects:@"-f", @"/var/MobileSoftwareUpdate/mnt1", nil];
                    [umountTask setArguments:umountArgs];
                    [umountTask launch];
                    [self errorAlert:@"Failed to mount DMG, please reboot and retry"];
                }
            }
        };
        [mountTask launch];
    }
}

-(BOOL)isMountPointPresent{
    NSError *err;
    BOOL isDir;
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/MobileSoftwareUpdate/mnt1" isDirectory:&isDir]) {
        if (isDir) {
            return TRUE;
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:@"/var/MobileSoftwareUpdate/mnt1" error:&err];
            [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/MobileSoftwareUpdate/mnt1" withIntermediateDirectories:TRUE attributes:nil error:&err];
            if (!err) {
                return TRUE;
            } else {
                [self errorAlert:@"Failed to delete /var/MobileSoftwareUpdate/mnt1 to create a directory"];
            }
            return FALSE;
        }
    } else {
        [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/MobileSoftwareUpdate/mnt1" withIntermediateDirectories:TRUE attributes:nil error:&err];
        if (!err) {
            return TRUE;
        } else {
            [self errorAlert:@"Failed to delete /var/MobileSoftwareUpdate/mnt1 to create a directory"];
        }
        return FALSE;
    }
}
-(void)successionRestore{
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/MobileSoftwareUpdate/mnt1/sbin/launchd"]) {
        NSMutableArray *rsyncMutableArgs = [NSMutableArray arrayWithObjects:@"-vaxcH",
                                            @"--delete-delay",
                                            @"--progress",
                                            @"--ignore-errors",
                                            @"--force",
                                            @"--exclude=/Developer",
                                            @"--exclude=/System/Library/Caches/com.apple.kernelcaches/kernelcache",
                                            @"--exclude=/System/Library/Caches/apticket.der",
                                            @"--exclude=System/Library/Caches/com.apple.factorydata/",
                                            @"--exclude=/usr/standalone/firmware/sep-firmware.img4",
                                            @"--exclude=/usr/local/standalone/firmware/Baseband",
                                            @"--exclude=/private/var/MobileSoftwareUpdate/mnt1/",
                                            @"--exclude=/var/MobileSoftwareUpdate/mnt1",
                                            @"--exclude=/private/etc/fstab",
                                            @"--exclude=/etc/fstab",
                                            @"--exclude=/usr/standalone/firmware/FUD/",
                                            @"--exclude=/usr/standalone/firmware/Savage/",
                                            @"--exclude=/System/Library/Pearl",
                                            @"--exclude=/usr/standalone/firmware/Yonkers/",
                                            @"/var/MobileSoftwareUpdate/mnt1/.",
                                            @"/", nil];
        if (![_filesystemType isEqualToString:@"apfs"]) {
            [rsyncMutableArgs addObject:@"--exclude=/System/Library/Caches/com.apple.dyld/"];
        }
        if ([[_successionPrefs objectForKey:@"dry-run"] isEqual:@(1)]) {
            [rsyncMutableArgs addObject:@"--dry-run"];
        }
        if ([[_successionPrefs objectForKey:@"update-install"] isEqual:@(1)]) {
            [rsyncMutableArgs addObject:@"--exclude=/var"];
            [rsyncMutableArgs addObject:@"--exclude=/private/var/"];
            [rsyncMutableArgs addObject:@"--exclude=/usr/bin/uicache"];
        }
        if ([[_successionPrefs objectForKey:@"log-file"] isEqual:@(1)]) {
            [[NSFileManager defaultManager] removeItemAtPath:@"/private/var/mobile/succession.log" error:nil];
            NSString *cmdString = [NSString stringWithFormat:@"rsync %@\n", [rsyncMutableArgs componentsJoinedByString:@" "]];
            [cmdString writeToFile:@"/private/var/mobile/succession.log" atomically:TRUE encoding:NSUTF8StringEncoding error:nil];
        }
        if ([[_successionPrefs objectForKey:@"delete-during"] isEqual:@(1)]) {
            [rsyncMutableArgs removeObject:@"--delete-after"];
            [rsyncMutableArgs addObject:@"--delete"];
        }
        if ([[_successionPrefs objectForKey:@"create_APFS_orig-fs"] isEqual:@(1)]) {
            [rsyncMutableArgs addObject:@"--exclude=/usr/bin/snappy"];
        }
        NSArray *rsyncArgs = [NSArray arrayWithArray:rsyncMutableArgs];
        NSTask *rsyncTask = [[NSTask alloc] init];
        if ([[NSFileManager defaultManager] fileExistsAtPath:[_successionPrefs objectForKey:@"custom_rsync_path"]]) {
            [rsyncTask setLaunchPath:[_successionPrefs objectForKey:@"custom_rsync_path"]];
        } else {
            if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/rsync"]) {
                UIAlertController *rsyncNotFound = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Unable to find rsync at custom path %@", [_successionPrefs objectForKey:@"custom_rsync_path"]]  message:@"/usr/bin/rsync will be used" preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *useDefualtPathAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleDefault handler:nil];
                [rsyncNotFound addAction:useDefualtPathAction];
                [self presentViewController:rsyncNotFound animated:TRUE completion:nil];
                [rsyncTask setLaunchPath:@"/usr/bin/rsync"];
            } else {
                [self errorAlert:[NSString stringWithFormat:@"Unable to find rsync at custom path %@\nPlease check your custom path in Succession's settings or install rsync from Cydia", [_successionPrefs objectForKey:@"custom_rsync_path"]]];
            }
        }
        [rsyncTask setArguments:rsyncArgs];
        NSPipe *outputPipe = [NSPipe pipe];
        [rsyncTask setStandardOutput:outputPipe];
        NSFileHandle *stdoutHandle = [outputPipe fileHandleForReading];
        [stdoutHandle waitForDataInBackgroundAndNotify];
        id observer;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSFileHandleDataAvailableNotification
                                                                        object:stdoutHandle queue:nil
                                                                    usingBlock:^(NSNotification *note)
        {

            NSData *dataRead = [stdoutHandle availableData];
            NSString *stringRead = [[NSString alloc] initWithData:dataRead encoding:NSUTF8StringEncoding];
            if ([[self->_successionPrefs objectForKey:@"log-file"] isEqual:@(1)]) {
                if (![[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/mobile/succession.log"]) {
                    [[NSFileManager defaultManager] createFileAtPath:@"/private/var/mobile/succession.log" contents:nil attributes:nil];
                }
                NSFileHandle *logFileHandle = [NSFileHandle fileHandleForWritingAtPath:@"/private/var/mobile/succession.log"];
                [logFileHandle seekToEndOfFile];
                [logFileHandle writeData:[stringRead dataUsingEncoding:NSUTF8StringEncoding]];
                [logFileHandle closeFile];
            }
            [[self infoLabel] setText:@"Restoring, please wait..."];
            [[self headerLabel] setText:@"Progress bar may freeze for long periods of time, it's still working, leave it alone until your device reboots."];
            [[self headerLabel] setHighlighted:FALSE];
            if ([stringRead containsString:@"00 files..."]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[self outputLabel] setHidden:FALSE];
                    [[self outputLabel] setText:stringRead];
                    [[self fileListActivityIndicator] setHidden:FALSE];
                    [[self restoreProgressBar] setHidden:TRUE];
                });
            }
            if ([stringRead hasPrefix:@"Applications/"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[self outputLabel] setHidden:FALSE];
                    [[self outputLabel] setText:[NSString stringWithFormat:@"%@\nRebuliding Applications...", stringRead]];
                    [[self fileListActivityIndicator] setHidden:TRUE];
                    [[self restoreProgressBar] setHidden:FALSE];
                    [[self restoreProgressBar] setProgress:0];
                });
            }
            if ([stringRead hasPrefix:@"Library/"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[self outputLabel] setHidden:FALSE];
                    [[self outputLabel] setText:[NSString stringWithFormat:@"%@\nRebuliding Library...", stringRead]];
                    [[self fileListActivityIndicator] setHidden:TRUE];
                    [[self restoreProgressBar] setHidden:FALSE];
                    [[self restoreProgressBar] setProgress:0.33];
                });
            }
            if ([stringRead hasPrefix:@"System/"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[self outputLabel] setHidden:FALSE];
                    [[self outputLabel] setText:[NSString stringWithFormat:@"%@\nRebuliding System...", stringRead]];
                    [[self fileListActivityIndicator] setHidden:TRUE];
                    [[self restoreProgressBar] setHidden:FALSE];
                    [[self restoreProgressBar] setProgress:0.67];
                });
            }
            if ([stringRead hasPrefix:@"usr/"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[self outputLabel] setHidden:FALSE];
                    [[self outputLabel] setText:[NSString stringWithFormat:@"%@\nRebuliding usr...", stringRead]];
                    [[self fileListActivityIndicator] setHidden:TRUE];
                    [[self restoreProgressBar] setHidden:FALSE];
                    [[self restoreProgressBar] setProgress:0.9];
                });
            }
            if ([stringRead containsString:@"speedup is"] && [stringRead containsString:@"bytes"] && [stringRead containsString:@"sent"] && [stringRead containsString:@"received"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[self outputLabel] setHidden:TRUE];
                    [[self headerLabel] setText:@"Restore complete"];
                    [[self fileListActivityIndicator] setHidden:TRUE];
                    [[self restoreProgressBar] setHidden:FALSE];
                    [[self restoreProgressBar] setProgress:1.0];
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    if ([[self->_successionPrefs objectForKey:@"dry-run"] isEqual:@(1)]) {
                        UIAlertController *restoreCompleteController = [UIAlertController alertControllerWithTitle:@"Dry run complete!" message:@"YAY!" preferredStyle:UIAlertControllerStyleAlert];
                        UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"Exit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                        exit(0);
                        }];
                        [restoreCompleteController addAction:exitAction];
                        [self presentViewController:restoreCompleteController animated:TRUE completion:nil];
                    } else {
                        if ([[self->_successionPrefs objectForKey:@"create_APFS_orig-fs"] isEqual:@(1)]) {
                            NSTask *deleteOrigFS = [[NSTask alloc] init];
                            [deleteOrigFS setLaunchPath:@"/usr/bin/snappy"];
                            NSArray *deleteOrigFSArgs = [[NSArray alloc] initWithObjects:@"-f", @"/", @"-d", @"orig-fs", nil];
                            [deleteOrigFS setArguments:deleteOrigFSArgs];
                            [deleteOrigFS launch];
                            NSTask *createNewOrigFS = [[NSTask alloc] init];
                            [createNewOrigFS setLaunchPath:@"/usr/bin/snappy"];
                            NSArray *createNewOrigFSArgs = [[NSArray alloc] initWithObjects:@"-f", @"/", @"-c", @"orig-fs", nil];
                            [createNewOrigFS setArguments:createNewOrigFSArgs];
                            createNewOrigFS.terminationHandler = ^{
                                NSTask *renameOrigFS = [[NSTask alloc] init];
                                [renameOrigFS setLaunchPath:@"/usr/bin/snappy"];
                                NSArray *renameOrigFSArgs = [[NSArray alloc] initWithObjects:@"-f", @"/", @"-r", @"orig-fs", @"-x", nil];
                                [renameOrigFS setArguments:renameOrigFSArgs];
                                [renameOrigFS launch];
                                [[NSFileManager defaultManager] removeItemAtPath:@"/usr/bin/snappy" error:nil];
                            };
                            [createNewOrigFS launch];
                        }
                        UIAlertController *restoreCompleteController = [UIAlertController alertControllerWithTitle:@"Restore Succeeded!" message:@"Rebuilding icon cache, please wait..." preferredStyle:UIAlertControllerStyleAlert];
                        [self presentViewController:restoreCompleteController animated:TRUE completion:^{
                            if ([[self->_successionPrefs objectForKey:@"update-install"] isEqual:@(1)]) {
                                if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/uicache"]) {
                                    NSTask *uicacheTask = [[NSTask alloc] init];
                                    NSArray *uicacheElectraArgs = [NSArray arrayWithObjects:@"--all", nil];
                                    [uicacheTask setLaunchPath:@"/usr/bin/uicache"];
                                    [uicacheTask setArguments:uicacheElectraArgs];
                                    [uicacheTask launch];
                                    uicacheTask.terminationHandler = ^(NSTask *task){
                                        [[NSFileManager defaultManager] removeItemAtPath:@"/usr/bin/uicache" error:nil];
                                        reboot(0x400);
                                    };
                                } else {
                                    reboot(0x400);
                                }
                            } else if ([[self->_successionPrefs objectForKey:@"dry-run"] isEqual:@(1)]){}
                            else {
                                extern int SBDataReset(mach_port_t, int);
                                extern mach_port_t SBSSpringBoardServerPort(void);
                                SBDataReset(SBSSpringBoardServerPort(), 5);
                            }
                        
                    }];
                }
            });
            }
            [stdoutHandle waitForDataInBackgroundAndNotify];
        }];
        [[self infoLabel] setText:@"Working, do not leave the app..."];
        [[self headerLabel] setText:@""];
        [[self startRestoreButton] setTitle:@"Restore in progress..." forState:UIControlStateNormal];
        [[self startRestoreButton] setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
        [[self startRestoreButton] setEnabled:FALSE];
        [[self fileListActivityIndicator] setHidden:FALSE];
        if ([rsyncTask launchPath]) {
            if ([[_successionPrefs objectForKey:@"create_APFS_orig-fs"] isEqual:@(1)] && [[_successionPrefs objectForKey:@"create_APFS_succession-prerestore"] isEqual:@(1)]) {
                UIAlertController *tooMuchAPFSAlert = [UIAlertController alertControllerWithTitle:@"Conflicting options enabled" message:@"You cannot have 'create backup snapshot' and 'create new orig-fs' enabled simultaneously, please go to Succession's settings page and disable one of the two." preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [[self navigationController] popToRootViewControllerAnimated:TRUE];
                }];
                [tooMuchAPFSAlert addAction:dismissAction];
                [self presentViewController:tooMuchAPFSAlert animated:TRUE completion:nil];
            } else {
                [rsyncTask launch];
            }
        }
    } else {
        [self errorAlert:@"Mountpoint does not contain rootfilesystem, please restart the app and try again."];
    }

}


-(void)errorAlert:(NSString *)message{
    UIAlertController *errorAlertController = [UIAlertController alertControllerWithTitle:@"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"Exit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        exit(0);
    }];
    [errorAlertController addAction:exitAction];
    [self presentViewController:errorAlertController animated:TRUE completion:nil];
}

@end
