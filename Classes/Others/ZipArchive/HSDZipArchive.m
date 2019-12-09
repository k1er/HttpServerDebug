//
//  HSDZipArchive.m
//  HSDZipArchive
//
//  Created by Sam Soffes on 7/21/10.
//  Copyright (c) Sam Soffes 2010-2015. All rights reserved.
//

#import "HSDZipArchive.h"
#include "HSDzip.h"
//#include "HSDminishared.h"
#include <sys/stat.h>

#define CHUNK 16384

int _hsdZipOpenEntry(zipFile entry, NSString *name, const zip_fileinfo *zipfi, int level, NSString *password, BOOL aes);
uint32_t tm_to_dosdate(const struct tm *ptm);
int invalid_date(const struct tm *ptm);

@interface HSDZipArchive ()

- (instancetype)init NS_DESIGNATED_INITIALIZER;

@end

@implementation HSDZipArchive {
    /// path for zip file
    NSString *_path;
    zipFile _zip;
}

#pragma mark - Zipping

+ (BOOL)createZipFileAtPath:(NSString *)path withFilesAtPaths:(NSArray<NSString *> *)paths {
    HSDZipArchive *zipArchive = [[HSDZipArchive alloc] initWithPath:path];
    BOOL success = [zipArchive open];
    if (success) {
        for (NSString *filePath in paths) {
            success &= [zipArchive writeFile:filePath];
        }
        success &= [zipArchive close];
    }
    return success;
}

+ (BOOL)createZipFileAtPath:(NSString *)path withContentsOfDirectory:(NSString *)directoryPath {
    return [HSDZipArchive createZipFileAtPath:path withContentsOfDirectory:directoryPath keepParentDirectory:NO];
}

+ (BOOL)createZipFileAtPath:(NSString *)path withContentsOfDirectory:(NSString *)directoryPath keepParentDirectory:(BOOL)keepParentDirectory {
    return [HSDZipArchive createZipFileAtPath:path withContentsOfDirectory:directoryPath keepParentDirectory:keepParentDirectory andProgressHandler:nil];
}

+ (BOOL)createZipFileAtPath:(NSString *)path withContentsOfDirectory:(NSString *)directoryPath keepParentDirectory:(BOOL)keepParentDirectory andProgressHandler:(void(^ _Nullable)(NSUInteger entryNumber, NSUInteger total))progressHandler {
    return [self createZipFileAtPath:path withContentsOfDirectory:directoryPath keepParentDirectory:keepParentDirectory compressionLevel:Z_DEFAULT_COMPRESSION progressHandler:progressHandler];
}

+ (BOOL)createZipFileAtPath:(NSString *)path withContentsOfDirectory:(NSString *)directoryPath keepParentDirectory:(BOOL)keepParentDirectory compressionLevel:(int)compressionLevel progressHandler:(void(^ _Nullable)(NSUInteger entryNumber, NSUInteger total))progressHandler {
    HSDZipArchive *zipArchive = [[HSDZipArchive alloc] initWithPath:path];
    BOOL success = [zipArchive open];
    if (success) {
        // use a local fileManager (queue/thread compatibility)
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        NSDirectoryEnumerator *dirEnumerator = [fileManager enumeratorAtPath:directoryPath];
        NSArray<NSString *> *allObjects = dirEnumerator.allObjects;
        if (keepParentDirectory) {
            success &= [zipArchive writeFolderAtPath:directoryPath withFolderName:directoryPath.lastPathComponent];
        }
        NSUInteger total = allObjects.count, complete = 0;
        NSString *fileName;
        for (fileName in allObjects) {
            BOOL isDir;
            NSString *fullFilePath = [directoryPath stringByAppendingPathComponent:fileName];
            [fileManager fileExistsAtPath:fullFilePath isDirectory:&isDir];

            if (keepParentDirectory) {
                fileName = [directoryPath.lastPathComponent stringByAppendingPathComponent:fileName];
            }

            if (!isDir) {
                // file
                success &= [zipArchive writeFileAtPath:fullFilePath withFileName:fileName compressionLevel:compressionLevel];
            } else {
                // directory
                if ([fileManager contentsOfDirectoryAtPath:fullFilePath error:nil].count == 0) {
                    // empty directory
                    success &= [zipArchive writeFolderAtPath:fullFilePath withFolderName:fileName];
                }
            }
            complete++;
            if (progressHandler) {
                progressHandler(complete, total);
            }
        } // for loop
        success &= [zipArchive close];
    }
    return success;
}

// disabling `init` because designated initializer is `initWithPath:`
- (instancetype)init { @throw nil; }

// designated initializer
- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _path = [path copy];
    }
    return self;
}

- (BOOL)open {
    NSAssert((_zip == NULL), @"Attempting to open an archive which is already open");
    _zip = hsd_zipOpen(_path.fileSystemRepresentation, APPEND_STATUS_CREATE);
    return (NULL != _zip);
}

- (BOOL)writeFolderAtPath:(NSString *)path withFolderName:(NSString *)folderName {
    NSAssert((_zip != NULL), @"Attempting to write to an archive which was never opened");
    
    zip_fileinfo zipInfo = {};
    
    [HSDZipArchive zipInfo:&zipInfo setAttributesOfItemAtPath:path];
    
    int error = _hsdZipOpenEntry(_zip, [folderName stringByAppendingString:@"/"], &zipInfo, Z_NO_COMPRESSION, nil, 0);
    const void *buffer = NULL;
    hsd_zipWriteInFileInZip(_zip, buffer, 0);
    hsd_zipCloseFileInZip(_zip);
    return error == ZIP_OK;
}

- (BOOL)writeFile:(NSString *)path {
    return [self writeFileAtPath:path withFileName:nil];
}

- (BOOL)writeFileAtPath:(NSString *)path withFileName:(nullable NSString *)fileName {
    return [self writeFileAtPath:path withFileName:fileName compressionLevel:Z_DEFAULT_COMPRESSION];
}

// supports writing files with logical folder/directory structure
// *path* is the absolute path of the file that will be compressed
// *fileName* is the relative name of the file how it is stored within the zip e.g. /folder/subfolder/text1.txt
- (BOOL)writeFileAtPath:(NSString *)path withFileName:(nullable NSString *)fileName compressionLevel:(int)compressionLevel {
    NSAssert((_zip != NULL), @"Attempting to write to an archive which was never opened");
    
    FILE *input = fopen(path.fileSystemRepresentation, "r");
    if (NULL == input) {
        return NO;
    }
    
    if (!fileName) {
        fileName = path.lastPathComponent;
    }
    
    zip_fileinfo zipInfo = {};
    
    [HSDZipArchive zipInfo:&zipInfo setAttributesOfItemAtPath:path];
    
    void *buffer = malloc(CHUNK);
    if (buffer == NULL)
    {
        fclose(input);
        return NO;
    }
    
    int error = _hsdZipOpenEntry(_zip, fileName, &zipInfo, compressionLevel, nil, YES);
    
    while (!feof(input) && !ferror(input))
    {
        unsigned int len = (unsigned int) fread(buffer, 1, CHUNK, input);
        hsd_zipWriteInFileInZip(_zip, buffer, len);
    }
    
    hsd_zipCloseFileInZip(_zip);
    free(buffer);
    fclose(input);
    return error == ZIP_OK;
}

- (BOOL)close {
    NSAssert((_zip != NULL), @"[HSDZipArchive] Attempting to close an archive which was never opened");
    int error = hsd_zipClose(_zip, NULL);
    _zip = nil;
    return error == ZIP_OK;
}

#pragma mark - Private

+ (void)zipInfo:(zip_fileinfo *)zipInfo setAttributesOfItemAtPath:(NSString *)path {
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error: nil];
    if (attr) {
        NSDate *fileDate = (NSDate *)[attr objectForKey:NSFileModificationDate];
        if (fileDate) {
            [self zipInfo:zipInfo setDate:fileDate];
        }
        
        // Write permissions into the external attributes, for details on this see here: http://unix.stackexchange.com/a/14727
        // Get the permissions value from the files attributes
        NSNumber *permissionsValue = (NSNumber *)[attr objectForKey:NSFilePosixPermissions];
        if (permissionsValue != nil) {
            // Get the short value for the permissions
            short permissionsShort = permissionsValue.shortValue;
            
            // Convert this into an octal by adding 010000, 010000 being the flag for a regular file
            NSInteger permissionsOctal = 0100000 + permissionsShort;
            
            // Convert this into a long value
            uLong permissionsLong = @(permissionsOctal).unsignedLongValue;
            
            // Store this into the external file attributes once it has been shifted 16 places left to form part of the second from last byte
            
            // Casted back to an unsigned int to match type of external_fa in minizip
            zipInfo->external_fa = (unsigned int)(permissionsLong << 16L);
        }
    }
}

+ (void)zipInfo:(zip_fileinfo *)zipInfo setDate:(NSDate *)date
{
    NSCalendar *currentCalendar = HSDZipArchive._gregorian;
    NSCalendarUnit flags = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    NSDateComponents *components = [currentCalendar components:flags fromDate:date];
    struct tm tmz_date;
    tmz_date.tm_sec = (unsigned int)components.second;
    tmz_date.tm_min = (unsigned int)components.minute;
    tmz_date.tm_hour = (unsigned int)components.hour;
    tmz_date.tm_mday = (unsigned int)components.day;
    // ISO/IEC 9899 struct tm is 0-indexed for January but NSDateComponents for gregorianCalendar is 1-indexed for January
    tmz_date.tm_mon = (unsigned int)components.month - 1;
    // ISO/IEC 9899 struct tm is 0-indexed for AD 1900 but NSDateComponents for gregorianCalendar is 1-indexed for AD 1
    tmz_date.tm_year = (unsigned int)components.year - 1900;
    zipInfo->dos_date = tm_to_dosdate(&tmz_date);
}

+ (NSCalendar *)_gregorian {
    static NSCalendar *gregorian;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    });
    
    return gregorian;
}

@end

int _hsdZipOpenEntry(zipFile entry, NSString *name, const zip_fileinfo *zipfi, int level, NSString *password, BOOL aes)
{
    return hsd_zipOpenNewFileInZip5(entry, name.fileSystemRepresentation, zipfi, NULL, 0, NULL, 0, NULL, 0, 0, Z_DEFLATED, level, 0, -MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY, password.UTF8String, aes, 0);
}

uint32_t tm_to_dosdate(const struct tm *ptm)
{
    struct tm fixed_tm;

    /* Years supported:
     * [00, 79]      (assumed to be between 2000 and 2079)
     * [80, 207]     (assumed to be between 1980 and 2107, typical output of old
     software that does 'year-1900' to get a double digit year)
     * [1980, 2107]  (due to the date format limitations, only years between 1980 and 2107 can be stored.)
     */

    memcpy(&fixed_tm, ptm, sizeof(struct tm));
    if (fixed_tm.tm_year >= 1980) /* range [1980, 2107] */
        fixed_tm.tm_year -= 1980;
    else if (fixed_tm.tm_year >= 80) /* range [80, 99] */
        fixed_tm.tm_year -= 80;
    else /* range [00, 79] */
        fixed_tm.tm_year += 20;

    if (invalid_date(ptm))
        return 0;

    return (uint32_t)(((fixed_tm.tm_mday) + (32 * (fixed_tm.tm_mon + 1)) + (512 * fixed_tm.tm_year)) << 16) |
    ((fixed_tm.tm_sec / 2) + (32 * fixed_tm.tm_min) + (2048 * (uint32_t)fixed_tm.tm_hour));
}

int invalid_date(const struct tm *ptm)
{
#define datevalue_in_range(min, max, value) ((min) <= (value) && (value) <= (max))
    return (!datevalue_in_range(0, 207, ptm->tm_year) ||
            !datevalue_in_range(0, 11, ptm->tm_mon) ||
            !datevalue_in_range(1, 31, ptm->tm_mday) ||
            !datevalue_in_range(0, 23, ptm->tm_hour) ||
            !datevalue_in_range(0, 59, ptm->tm_min) ||
            !datevalue_in_range(0, 59, ptm->tm_sec));
#undef datevalue_in_range
}
