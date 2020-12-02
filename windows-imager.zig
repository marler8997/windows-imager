const std = @import("std");
const mem = std.mem;
const os = std.os;
const win = os.windows;
const kernel32 = win.kernel32;

pub extern "kernel32" fn GetTickCount(
) callconv(win.WINAPI) u32;
pub extern "kernel32" fn FindFirstVolumeW(
    lpszVolumeName: [*]win.WCHAR,
    cchBufferLength: u32
) callconv(win.WINAPI) win.HANDLE;
pub extern "kernel32" fn FindVolumeClose(
    hFindVolume: win.HANDLE,
) callconv(win.WINAPI) win.BOOL;
pub extern "kernel32" fn FindNextVolumeW(
    hFindVolume: win.HANDLE,
    lpszVolumeName: [*]win.WCHAR,
    cchBufferLength: u32
) callconv(win.WINAPI) win.BOOL;

pub extern "kernel32" fn FindFirstVolumeMountPointW(
    lpszRootPathName: [*:0]const win.WCHAR,
    lpszVolumeMountPoint: [*]win.WCHAR,
    cchBufferLength: u32
) callconv(win.WINAPI) win.HANDLE;
pub extern "kernel32" fn FindVolumeMountPointClose(
    hFindVolumeMountPoint: win.HANDLE,
) callconv(win.WINAPI) win.BOOL;
pub extern "kernel32" fn FindNextVolumeMountPointW(
    hFindVolumeMountPoint: win.HANDLE,
    lpszVolumeMountPoint: [*]win.WCHAR,
    cchBufferLength: u32
) callconv(win.WINAPI) win.BOOL;

pub extern "kernel32" fn GetLogicalDriveStringsW(
    nBufferLength: win.DWORD,
    lpBuffer: ?[*]win.WCHAR,
) callconv(win.WINAPI) win.DWORD;

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
    Cylinders: win.LARGE_INTEGER,
    MediaType: MEDIA_TYPE,
    TracksPerCylinder: u32,
    SectorsPerTrack: u32,
    BytesPerSector: u32,
};

const PhysicalDriveString = struct {
    const PREFIX = "\\\\.\\PHYSICALDRIVE";
    str: [PREFIX.len + 1 :0]u16,
    pub fn init(drive_index: u8) PhysicalDriveString {
        var ascii_buf : [PREFIX.len + 1 :0]u8 = undefined;
        {
            const slice = std.fmt.bufPrint(&ascii_buf, PREFIX ++ "{}", .{drive_index}) catch unreachable;
            std.debug.assert(slice.len == ascii_buf.len);
        }
        ascii_buf[ascii_buf.len] = 0;
        var result : PhysicalDriveString = undefined;
        {
            const convert_result = std.unicode.utf8ToUtf16Le(&result.str, &ascii_buf) catch unreachable;
            std.debug.assert(convert_result == ascii_buf.len);
        }
        result.str[ascii_buf.len] = 0;
        return result;
    }
};

fn getDiskGeo(drive_handle: win.HANDLE) !DISK_GEOMETRY {
    var disk_geo : DISK_GEOMETRY = undefined;
    {
        var bytes_returned : u32 = undefined;
        const result = kernel32.DeviceIoControl(
            drive_handle,
            IOCTL_DISK_GET_DRIVE_GEOMETRY,
            null, 0,
            &disk_geo, @sizeOf(@TypeOf(disk_geo)),
            &bytes_returned,
            null);
        if (result == 0) {
            std.debug.warn("Error: DeviceIoControl IOCTL_DISK_GET_DRIVE_GEOMETRY failed with {}\n", .{
                kernel32.GetLastError()});
            return error.AlreadyReported;
        }
    }
    return disk_geo;
}
fn sumDiskSize(geo: DISK_GEOMETRY) u64 {
    return
        @intCast(u64, geo.Cylinders) *
        @intCast(u64, geo.TracksPerCylinder) *
        @intCast(u64, geo.SectorsPerTrack) *
        @intCast(u64, geo.BytesPerSector);
}

const FormatU16 = struct {
    s: []const u16,
    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) std.os.WriteError!void {
        for (self.s) |c| {
            try writer.print("{c}", .{@intCast(u8, c)});
        }
    }
};
fn formatU16(s: anytype) FormatU16 {
    switch (@typeInfo(@TypeOf(s))) {
        .Pointer => |info| switch (info.size) {
            .Slice => return FormatU16 { .s = s },
            .Many => return FormatU16 { .s = mem.span(s) },
            else => {},
        },
        else => {},
    }
    @compileError("formatU16 doesn't support type " ++ @typeName(@TypeOf(s)));
}

//fn dumpDiskGeo(geo: DISK_GEOMETRY) !void {
//    const disk_size = sumDiskSize(geo);
//    var typed_disk_size : f32 = @intToFloat(f32, disk_size);
//    var size_unit : []const u8 = undefined;
//    getNiceSize(&typed_disk_size, &size_unit);
//    std.debug.warn(
//        \\{}
//        \\{} cylinders *
//        \\{} tracks/cylinder *
//        \\{} sectors/track *
//        \\{} bytes/sector
//        \\= {} bytes
//        \\= {d:.1} {}
//        \\
//    , .{geo.MediaType, geo.Cylinders, geo.TracksPerCylinder,
//        geo.SectorsPerTrack, geo.BytesPerSector, disk_size,
//        typed_disk_size, size_unit});
//}

fn printDiskSummary(optional_drive_index: ?u8, drive: []const u16, geo: DISK_GEOMETRY) void {
    const disk_size = sumDiskSize(geo);
    var typed_disk_size : f32 = @intToFloat(f32, disk_size);
    var size_unit : []const u8 = undefined;
    getNiceSize(&typed_disk_size, &size_unit);
    if (optional_drive_index) |drive_index| {
        std.debug.warn("{}: ", .{drive_index});
    }
    std.debug.warn("\"{}\" {d:.1} {} {}\n", .{
        formatU16(drive),
        typed_disk_size, size_unit,
        geo.MediaType,
    });
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
fn dismountDisk(disk_handle: win.HANDLE) !void {
    var unused : u32 = undefined;
    const result = kernel32.DeviceIoControl(
        disk_handle,
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
fn lockDisk(disk_handle: win.HANDLE) !void {
    var unused : u32 = undefined;
    const result = kernel32.DeviceIoControl(
        disk_handle,
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

fn openDisk(disk_name: [:0]const u16, access: u32) !win.HANDLE {
    const disk_handle = kernel32.CreateFileW(
        disk_name,
        access,
        win.FILE_SHARE_READ | win.FILE_SHARE_WRITE,
        null,
        win.OPEN_EXISTING,
        //win.FILE_ATTRIBUTE_NORMAL,
        win.FILE_FLAG_NO_BUFFERING | win.FILE_FLAG_RANDOM_ACCESS,
        null
    );
    if (disk_handle == win.INVALID_HANDLE_VALUE) {
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
    return disk_handle;
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
        std.io.getStdIn().reader().readUntilDelimiterArrayList(&answer, '\n', 20) catch |e| switch (e) {
            error.StreamTooLong => continue,
            else => return e
        };
        const s = mem.trimRight(u8, answer.items, "\r");
        if (mem.eql(u8, s, "y")) return true;
        if (mem.eql(u8, s, "n")) return false;
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
            \\  listvolumes       list volume paths (i.e. \\?\Volume{{6abe...}}\)
            \\  listlogicaldrives list logical drives (i.e. C:\)
            , .{});
        return 1;
    }

    const cmd = args[0];
    args = args[1..];

    if (mem.eql(u8, cmd, "list")) {
        try enforceArgCount(args, 0);
        {var i: u8 = 0; while (true) : (i += 1) {
            const disk_name = PhysicalDriveString.init(i);
            const disk_handle = openDisk(&disk_name.str, 0) catch |e| switch (e) {
                error.FileNotFound => break,
                else => return e,
            };
            const disk_geo = try getDiskGeo(disk_handle);
            printDiskSummary(i, &disk_name.str, disk_geo);
        }}
        return 0;
    }

    if (mem.eql(u8, cmd, "listvolumes")) {
        try listVolumes();
        return 0;
    }

    if (mem.eql(u8, cmd, "listlogicaldrives")) {
        try listLogicalDrives();
        return 0;
    }

    if (mem.eql(u8, cmd, "image")) {
        try enforceArgCount(args, 2);
        const drive = try std.unicode.utf8ToUtf16LeWithNull(allocator, args[0]);
        //const fileSlice = args[1];
        //const file = try allocator.allocSentinel(u8, fileSlice.len, 0);
        //mem.copy(u8, file, fileSlice);
        const file = try std.unicode.utf8ToUtf16LeWithNull(allocator, args[1]);

        const disk_handle = openDisk(drive, win.GENERIC_READ | win.GENERIC_WRITE) catch |e| {
            std.debug.warn("Error: Failed to open drive \"{}\" {}\n", .{formatU16(drive), e});
            return error.AlreadyReported;
        };
        const disk_geo = try getDiskGeo(disk_handle);
        printDiskSummary(null, drive, disk_geo);

        const file_handle = kernel32.CreateFileW(
            file,
            win.GENERIC_READ,
            win.FILE_SHARE_READ | win.FILE_SHARE_WRITE,
            null,
            win.OPEN_EXISTING,
            win.FILE_ATTRIBUTE_NORMAL,
            null
        );
        if (file_handle == win.INVALID_HANDLE_VALUE) {
           std.debug.warn("Error: failed to open '{}', error={}\n", .{file, kernel32.GetLastError()});
           return error.AlreadyReported;
        }
        const disk_size = sumDiskSize(disk_geo);
        const file_size = try win.GetFileSizeEx(file_handle);
        {
            var typedFileSize : f32 = @intToFloat(f32, file_size);
            var suffix : []const u8 = undefined;
            getNiceSize(&typedFileSize, &suffix);
            std.debug.warn("file size is {} ({d:.2} {})\n", .{file_size, typedFileSize, suffix});
        }

        if (file_size > disk_size) {
            std.debug.warn("Error: file is too big\n", .{});
            return error.AlreadyReported;
        }
        if (!try promptYesNo(allocator, "Are you sure you would like to re-image this drive? ")) {
            return 1;
        }
        // TODO: what is a good transfer size? Do some perf testing
        //const transfer_size = disk_geo.BytesPerSector;
        const transfer_size = 1024 * 1024;
        {
            // TODO: should this allocation be aligned?  Do some perf testing to see if it helps
            const buf = try allocator.alloc(u8, transfer_size);
            defer allocator.free(buf);
            try imageDisk(disk_handle, file_handle, file_size, buf);
        }
        std.debug.warn("Successfully imaged drive\n", .{});
        return 0;
    }

    std.debug.warn("Error: unknown command '{}'\n", .{cmd});
    return 1;
}

fn imageDisk(disk_handle: win.HANDLE, file_handle: win.HANDLE, file_size: u64, buf: []u8) !void {
    std.debug.warn("dismounting disk...\n", .{});
    try dismountDisk(disk_handle);
    std.debug.warn("locking disk...\n", .{});
    try lockDisk(disk_handle);
    std.debug.warn("disk ready to write\n", .{});

    // do I need to do this?
    //try win.SetFilePointerEx_BEGIN(disk_handle, 0);

    var total_processed : u64 = 0;
    var last_report_ticks = GetTickCount();
    const report_frequency = 1000; // report every 1000 ms

    while (total_processed < file_size) {
        const size = try win.ReadFile(file_handle, buf, null, .blocking);
        std.debug.assert(size > 0);
        //std.debug.warn("[DEBUG] read {} bytes\n", .{size});

        //try win.SetFilePointerEx_BEGIN(disk_handle, total_processed);

        // TODO: if this is the last read, need to pad with zeros
        //const written = try win.WriteFile(disk_handle, buf[0..size], null, .blocking);
        //std.debug.assert(written == size);
        {
            var written : u32 = undefined;
            if (0 == kernel32.WriteFile(disk_handle, buf.ptr, @intCast(u32, size), &written, null)) {
                std.debug.warn("Error: WriteFile to drive (size={}, total_written={}) failed, error={}\n",.{
                    size, total_processed, kernel32.GetLastError()});
                return error.AlreadyReported;
            }
            std.debug.assert(written == size);
        }

        total_processed += size;
        //std.debug.warn("[DEBUG] write {} bytes (total={})\n", .{size, total_processed});
        const now = GetTickCount();
        // TODO: allow rollover
        if ((now - last_report_ticks) > report_frequency) {
            const progress = @intToFloat(f32, total_processed) / @intToFloat(f32, file_size) * 100;
            std.debug.warn("{d:.0}% ({} bytes)\n", .{progress, total_processed});
            last_report_ticks = now;
        }
    }
}

fn listVolumes() !void {
    var buf : [200]u16 = undefined;
    const fh = FindFirstVolumeW(&buf, buf.len);
    if (fh == win.INVALID_HANDLE_VALUE) {
        const err = kernel32.GetLastError();
        if (err == .NO_MORE_FILES)
            return;
        std.debug.warn("Error: FindFirstVolumeW failed with {}\n", .{err});
        return error.AlreadyReported;
    }
    defer {
        if (0 == FindVolumeClose(fh))
            std.debug.panic("FindVolumeClose failed with {}", .{kernel32.GetLastError()});
    }
    while (true) {
        const s : []u16 = &buf;
        const s_ptr = std.meta.assumeSentinel(s.ptr, 0);
        std.debug.warn("{}\n", .{formatU16(s_ptr)});
        try printDriveLetterName(s_ptr);
        try listVolumeMounts(s_ptr);
        if (0 == FindNextVolumeW(fh, &buf, buf.len)) {
            const err = kernel32.GetLastError();
            if (err == .NO_MORE_FILES)
                break;
            std.debug.warn("Error: FindNextVolumeW failed with {}\n", .{err});
            return error.AlreadyReported;
        }
    }
}

fn listVolumeMounts(volume: [*:0]const u16) !void {
    var buf : [200]u16 = undefined;
    const fh = FindFirstVolumeMountPointW(volume, &buf, buf.len);
    if (fh == win.INVALID_HANDLE_VALUE) {
        const err = kernel32.GetLastError();
        if (err == .NO_MORE_FILES)
            return;
        if (err == .PATH_NOT_FOUND)
            return;
        if (err == .UNRECOGNIZED_VOLUME)
            return;
        std.debug.warn("Error: FindFirstVolumeMountPointW failed with {}\n", .{err});
        return error.AlreadyReported;
    }
    defer {
        if (0 == FindVolumeMountPointClose (fh))
            std.debug.panic("FindVolumeMountPointClose  failed with {}", .{kernel32.GetLastError()});
    }
    while (true) {
        const s : []u16 = &buf;
        std.debug.warn("{}\n", .{formatU16(std.meta.assumeSentinel(s.ptr, 0))});
        if (0 == FindNextVolumeMountPointW(fh, &buf, buf.len)) {
            const err = kernel32.GetLastError();
            if (err == .NO_MORE_FILES)
                break;
            std.debug.warn("Error: FindNextVolumeMountPointW failed with {}\n", .{err});
            return error.AlreadyReported;
        }
    }
}

fn printDriveLetterName(volume: [*:0]const u16) !void {
    // TODO: implement
}

fn getLogicalDriveStrings(allocator: *mem.Allocator) ![]u16 {
    const len = GetLogicalDriveStringsW(0, null);
    if (len == 0) {
        std.debug.warn("Error: GetLogicalDriveStrings failed with {}\n", .{kernel32.GetLastError()});
        return error.AlreadyReported;
    }
    const buf = try allocator.alloc(u16, len);
    errdefer allocator.free(buf);

    const result = GetLogicalDriveStringsW(len, buf.ptr);
    std.debug.assert(len == result + 1);
    std.debug.assert(buf[len-1] == 0);

    return buf;
}

fn listLogicalDrives() !void {
    const drives = try getLogicalDriveStrings(std.heap.page_allocator);
    defer std.heap.page_allocator.free(drives);
    var next_drive_ptr = std.meta.assumeSentinel(drives.ptr, 0);
    while (true)
    {
        const next_drive = mem.span(next_drive_ptr);
        if (next_drive.len == 0)
            break;
        std.debug.warn("{}\n", .{formatU16(next_drive)});
        next_drive_ptr += next_drive.len + 1;
    }
}
