const std = @import("std");
const mem = std.mem;
const os = std.os;
const win = os.windows;
const kernel32 = win.kernel32;

pub extern "kernel32" fn GetTickCount(
) callconv(win.WINAPI) u32;

// My best guess is that windows expects all enums inside structs to be 32 bits?
const MEDIA_TYPE = extern enum {
  Unknown = 0,
  F5_1Pt2_512 = 1,
  F3_1Pt44_512 = 2,
  F3_2Pt88_512 = 3,
  F3_20Pt8_512 = 4,
  F3_720_512 = 5,
  F5_360_512 = 6,
  F5_320_512 = 7,
  F5_320_1024 = 8,
  F5_180_512 = 9,
  F5_160_512 = 10,
  RemovableMedia = 11,
  FixedMedia = 12,
  F3_120M_512 = 13,
  F3_640_512 = 14,
  F5_640_512 = 15,
  F5_720_512 = 16,
  F3_1Pt2_512 = 17,
  F3_1Pt23_1024 = 18,
  F5_1Pt23_1024 = 19,
  F3_128Mb_512 = 20,
  F3_230Mb_512 = 21,
  F8_256_128 = 22,
};

const FSCTL_LOCK_VOLUME             : u32 = 0x00090018;
const FSCTL_UNLOCK_VOLUME           : u32 = 0x0009001c;
const FSCTL_DISMOUNT_VOLUME         : u32 = 0x00090020;
const IOCTL_DISK_GET_DRIVE_GEOMETRY : u32 = 0x00070000;

const DISK_GEOMETRY = extern struct {
    cylinders: win.LARGE_INTEGER,
    mediaType: MEDIA_TYPE,
    tracksPerCylinder: u32,
    sectorsPerTrack: u32,
    bytesPerSector: u32,
};

const PhysicalDriveString = struct {
    const PREFIX = "\\\\.\\PHYSICALDRIVE";
    str: [PREFIX.len + 1 :0]u16,
    pub fn init(driveIndex: u8) PhysicalDriveString {
        var asciiBuf : [PREFIX.len + 1 :0]u8 = undefined;
        {
            const slice = std.fmt.bufPrint(&asciiBuf, PREFIX ++ "{}", .{driveIndex}) catch unreachable;
            std.debug.assert(slice.len == asciiBuf.len);
        }
        asciiBuf[asciiBuf.len] = 0;
        var result : PhysicalDriveString = undefined;
        {
            const convertResult = std.unicode.utf8ToUtf16Le(&result.str, &asciiBuf) catch unreachable;
            std.debug.assert(convertResult == asciiBuf.len);
        }
        result.str[asciiBuf.len] = 0;
        return result;
    }
};

fn getDiskGeo(driveHandle: win.HANDLE) !DISK_GEOMETRY {
    var diskGeo : DISK_GEOMETRY = undefined;
    {
        var bytesReturned : u32 = undefined;
        const result = kernel32.DeviceIoControl(
            driveHandle,
            IOCTL_DISK_GET_DRIVE_GEOMETRY,
            null, 0,
            &diskGeo, @sizeOf(@TypeOf(diskGeo)),
            &bytesReturned,
            null);
        if (result == 0) {
            std.debug.warn("Error: DeviceIoControl IOCTL_DISK_GET_DRIVE_GEOMETRY failed with {}\n", .{
                kernel32.GetLastError()});
            return error.AlreadyReported;
        }
    }
    return diskGeo;
}
fn sumDiskSize(geo: DISK_GEOMETRY) u64 {
    return
        @intCast(u64, geo.cylinders) *
        @intCast(u64, geo.tracksPerCylinder) *
        @intCast(u64, geo.sectorsPerTrack) *
        @intCast(u64, geo.bytesPerSector);
}
fn printUtf16Le(s: []const u16) void {
    for (s) |c| {
        std.debug.warn("{c}", .{@intCast(u8, c)});
    }
}
fn printDiskSeparator(name: []const u16) void {
    std.debug.warn("--------------------------------------------------------------------------------\n", .{});
    std.debug.warn("Drive \"", .{});
    printUtf16Le(name);
    std.debug.warn("\"\n", .{});
}
fn dumpDiskGeo(geo: DISK_GEOMETRY) !void {
    const diskSize = sumDiskSize(geo);
    var typedDiskSize : f32 = @intToFloat(f32, diskSize);
    var suffix : []const u8 = undefined;
    getNiceSize(&typedDiskSize, &suffix);
    std.debug.warn(
        \\{}
        \\{} cylinders *
        \\{} tracks/cylinder *
        \\{} sectors/track *
        \\{} bytes/sector
        \\= {} bytes
        \\= {d:.1} {}
        \\
    , .{geo.mediaType, geo.cylinders, geo.tracksPerCylinder,
        geo.sectorsPerTrack, geo.bytesPerSector, diskSize,
        typedDiskSize, suffix});
}

fn getNiceSize(size: *f32, suffix: *[]const u8) void {
    if (size.* <= 1024) {
        suffix.* = "B";
        return;
    }
    size.* = size.* / 1024;
    if (size.* <= 1024) {
        suffix.* = "KB";
        return;
    }
    size.* = size.* / 1024;
    if (size.* <= 1024) {
        suffix.* = "MB";
        return;
    }
    size.* = size.* / 1024;
    if (size.* <= 1024) {
        suffix.* = "GB";
        return;
    }
    size.* = size.* / 1024;
    suffix.* = "TB";
    return;
}
fn dismountDisk(driveHandle: win.HANDLE) !void {
    var unused : u32 = undefined;
    const result = kernel32.DeviceIoControl(
        driveHandle,
        FSCTL_DISMOUNT_VOLUME,
        null, 0,
        null, 0,
        &unused,
        null);
    if (result == 0) {
        std.debug.warn("Error: DeviceIoControl FSCTL_DISMOUNT_VOLUME failed with {}\n", .{
            kernel32.GetLastError()});
        return error.AlreadyReported;
    }
}
fn lockDisk(driveHandle: win.HANDLE) !void {
    var unused : u32 = undefined;
    const result = kernel32.DeviceIoControl(
        driveHandle,
        FSCTL_LOCK_VOLUME,
        null, 0,
        null, 0,
        &unused,
        null);
    if (result == 0) {
        std.debug.warn("Error: DeviceIoControl FSCTL_LOCK_VOLUME failed with {}\n", .{
            kernel32.GetLastError()});
        return error.AlreadyReported;
    }
}

fn openDrive(driveName: [:0]const u16, access: u32) !win.HANDLE {
    const driveHandle = kernel32.CreateFileW(
        driveName,
        access,
        win.FILE_SHARE_READ | win.FILE_SHARE_WRITE,
        null,
        win.OPEN_EXISTING,
        //win.FILE_ATTRIBUTE_NORMAL,
        win.FILE_FLAG_NO_BUFFERING | win.FILE_FLAG_RANDOM_ACCESS,
        null
    );
    if (driveHandle == win.INVALID_HANDLE_VALUE) {
        switch (kernel32.GetLastError()) {
            .SHARING_VIOLATION => return error.SharingViolation,
            .ALREADY_EXISTS => return error.PathAlreadyExists,
            .FILE_EXISTS => return error.PathAlreadyExists,
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            .ACCESS_DENIED => return error.AccessDenied,
            .PIPE_BUSY => return error.PipeBusy,
            .FILENAME_EXCED_RANGE => return error.NameTooLong,
            else => |err| return win.unexpectedError(err),
        }
    }
    return driveHandle;
}

fn enforceArgCount(args: []const[]const u8, count: usize) !void {
    if (args.len != count) {
        std.debug.warn("this command should have {} argument(s) but got {}\n", .{count, args.len});
        return error.AlreadyReported;
    }
}

fn promptYesNo(allocator: *mem.Allocator, prompt: []const u8) !bool {
    var answer = std.ArrayList(u8).init(allocator);
    defer answer.deinit();
    while (true) {
        std.debug.warn("{}[y/n]? ", .{prompt});
        //const answer = try std.io.readLine(&buffer);
        answer.resize(0) catch @panic("codebug");
        std.io.getStdIn().inStream().readUntilDelimiterArrayList(&answer, '\n', 20) catch |e| switch (e) {
            error.StreamTooLong => continue,
            else => return e
        };
        const s = std.mem.trimRight(u8, answer.items, "\r");
        if (std.mem.eql(u8, s, "y")) return true;
        if (std.mem.eql(u8, s, "n")) return false;
    }
}
pub fn main() anyerror!u8 {
    return main2() catch |e| switch (e) {
        error.AlreadyReported => return 1,
        else => return e,
    };
}
pub fn main2() anyerror!u8 {
    const allocator = &std.heap.ArenaAllocator.init(std.heap.page_allocator).allocator;
    var args = (try std.process.argsAlloc(allocator))[1..];
    if (args.len == 0) {
        std.debug.warn(
            \\Usage: windows-imager COMMNAD ARGS...
            \\  list              list physical disks
            \\  image DRIVE FILE  image the given drive with the given file
            , .{});
        return 1;
    }

    const cmd = args[0];
    args = args[1..];

    if (mem.eql(u8, cmd, "list")) {
        try enforceArgCount(args, 0);
        {var i: u8 = 0; while (true) : (i += 1) {
            const driveName = PhysicalDriveString.init(i);
            const driveHandle = openDrive(&driveName.str, 0) catch |e| switch (e) {
                error.FileNotFound => break,
                else => return e,
            };
            const diskGeo = try getDiskGeo(driveHandle);
            printDiskSeparator(&driveName.str);
            try dumpDiskGeo(diskGeo);
        }}
        return 0;
    }

    if (mem.eql(u8, cmd, "image")) {
        try enforceArgCount(args, 2);
        const drive = try std.unicode.utf8ToUtf16LeWithNull(allocator, args[0]);
        //const fileSlice = args[1];
        //const file = try allocator.allocSentinel(u8, fileSlice.len, 0);
        //mem.copy(u8, file, fileSlice);
        const file = try std.unicode.utf8ToUtf16LeWithNull(allocator, args[1]);

        const driveHandle = openDrive(drive, win.GENERIC_READ | win.GENERIC_WRITE) catch |e| {
            std.debug.warn("Error: Failed to open drive '", .{});
            printUtf16Le(drive);
            std.debug.warn("': {}\n", .{e});
            return error.AlreadyReported;
        };
        const diskGeo = try getDiskGeo(driveHandle);
        printDiskSeparator(drive);
        try dumpDiskGeo(diskGeo);

        const fileHandle = kernel32.CreateFileW(
            file,
            win.GENERIC_READ,
            win.FILE_SHARE_READ | win.FILE_SHARE_WRITE,
            null,
            win.OPEN_EXISTING,
            win.FILE_ATTRIBUTE_NORMAL,
            null
        );
        if (fileHandle == win.INVALID_HANDLE_VALUE) {
           std.debug.warn("Error: failed to open '{}', error={}\n", .{file, kernel32.GetLastError()});
           return error.AlreadyReported;
        }
        const diskSize = sumDiskSize(diskGeo);
        const fileSize = try win.GetFileSizeEx(fileHandle);
        {
            var typedFileSize : f32 = @intToFloat(f32, fileSize);
            var suffix : []const u8 = undefined;
            getNiceSize(&typedFileSize, &suffix);
            std.debug.warn("file size is {} ({d:.2} {})\n", .{fileSize, typedFileSize, suffix});
        }

        if (fileSize > diskSize) {
            std.debug.warn("Error: file is too big\n", .{});
            return error.AlreadyReported;
        }
        if (!try promptYesNo(allocator, "Are you sure you would like to re-image this drive? ")) {
            return 1;
        }
        try imageDisk(allocator, driveHandle, diskSize, diskGeo.bytesPerSector, fileHandle, fileSize);
        std.debug.warn("Successfully imaged drive\n", .{});
        return 0;
    }

    std.debug.warn("Error: unknown command '{}'\n", .{cmd});
    return 1;
}

fn imageDisk(allocator: *mem.Allocator,
    driveHandle: win.HANDLE, diskSize: u64, sectorSize: u32,
    fileHandle: win.HANDLE, fileSize: u64
) !void {
    std.debug.warn("dismounting disk...\n", .{});
    try dismountDisk(driveHandle);
    std.debug.warn("locking disk...\n", .{});
    try lockDisk(driveHandle);
    std.debug.warn("disk ready to write\n", .{});

    // do I need to do this?
    //try win.SetFilePointerEx_BEGIN(driveHandle, 0);

    // TODO: should this be aligned?
    const buf = try allocator.alloc(u8, sectorSize);
    //const buf = try allocator.alloc(u8, std.math.max(sectorSize, 1024 * 64)); // 64K buffer?
    defer allocator.free(buf);

    var totalProcessed : u64 = 0;
    var lastReportTicks = GetTickCount();
    const reportFrequency = 1000; // report every 1000 ms

    while (totalProcessed < fileSize) {
        const size = try win.ReadFile(fileHandle, buf, null, .blocking);
        std.debug.assert(size > 0);
        //std.debug.warn("[DEBUG] read {} bytes\n", .{size});

        //try win.SetFilePointerEx_BEGIN(driveHandle, totalProcessed);

        // TODO: if this is the last read, need to pad with zeros
        //const written = try win.WriteFile(driveHandle, buf[0..size], null, .blocking);
        //std.debug.assert(written == size);
        {
            var written : u32 = undefined;
            if (0 == kernel32.WriteFile(driveHandle, buf.ptr, @intCast(u32, size), &written, null)) {
                std.debug.warn("Error: WriteFile to drive (size={}, total_written={}) failed, error={}\n",.{
                    size, totalProcessed, kernel32.GetLastError()});
                return error.AlreadyReported;
            }
            std.debug.assert(written == size);
        }

        totalProcessed += size;
        //std.debug.warn("[DEBUG] write {} bytes (total={})\n", .{size, totalProcessed});
        const now = GetTickCount();
        // TODO: allow rollover
        if ((now - lastReportTicks) > reportFrequency) {
            const progress = @intToFloat(f32, totalProcessed) / @intToFloat(f32, fileSize) * 100;
            std.debug.warn("{d:.0}% ({} bytes)\n", .{progress, totalProcessed});
            lastReportTicks = now;
        }
    }
}
