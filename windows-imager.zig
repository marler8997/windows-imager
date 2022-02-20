const std = @import("std");
const mem = std.mem;

const win32 = struct {
    const win = std.os.windows;
    const WINAPI = win.WINAPI;

    pub const INVALID_HANDLE_VALUE = win.INVALID_HANDLE_VALUE;
    pub const GENERIC_READ = win.GENERIC_READ;
    pub const GENERIC_WRITE = win.GENERIC_WRITE;
    pub const CREATE_ALWAYS = win.CREATE_ALWAYS;
    pub const MAX_PATH = win.MAX_PATH;
    pub const FILE_SHARE_READ = win.FILE_SHARE_READ;
    pub const FILE_SHARE_WRITE = win.FILE_SHARE_WRITE;
    pub const FILE_ATTRIBUTE_NORMAL = win.FILE_ATTRIBUTE_NORMAL;
    pub const OPEN_EXISTING = win.OPEN_EXISTING;
    pub const FILE_FLAG_NO_BUFFERING = win.FILE_FLAG_NO_BUFFERING;
    pub const FILE_FLAG_RANDOM_ACCESS = win.FILE_FLAG_RANDOM_ACCESS;

    pub const BOOL = win.BOOL;
    pub const HANDLE = win.HANDLE;
    pub const OVERLAPPED = win.OVERLAPPED;

    pub const GetFileSizeEx = win.GetFileSizeEx;

    pub const GetLastError = win.kernel32.GetLastError;
    pub const CreateFileW = win.kernel32.CreateFileW;
    pub const WriteFile = win.kernel32.WriteFile;
    pub const ReadFile = win.kernel32.ReadFile;
    pub const DeviceIoControl = win.kernel32.DeviceIoControl;

    pub extern "kernel32" fn GetTickCount(
    ) callconv(WINAPI) u32;
    pub extern "kernel32" fn FindFirstVolumeW(
        lpszVolumeName: [*]win.WCHAR,
        cchBufferLength: u32
    ) callconv(WINAPI) win.HANDLE;
    pub extern "kernel32" fn FindVolumeClose(
        hFindVolume: win.HANDLE,
    ) callconv(WINAPI) win.BOOL;
    pub extern "kernel32" fn FindNextVolumeW(
        hFindVolume: win.HANDLE,
        lpszVolumeName: [*]win.WCHAR,
        cchBufferLength: u32
    ) callconv(WINAPI) win.BOOL;

    pub extern "kernel32" fn FindFirstVolumeMountPointW(
        lpszRootPathName: [*:0]const win.WCHAR,
        lpszVolumeMountPoint: [*]win.WCHAR,
        cchBufferLength: u32
    ) callconv(WINAPI) win.HANDLE;
    pub extern "kernel32" fn FindVolumeMountPointClose(
        hFindVolumeMountPoint: win.HANDLE,
    ) callconv(WINAPI) win.BOOL;
    pub extern "kernel32" fn FindNextVolumeMountPointW(
        hFindVolumeMountPoint: win.HANDLE,
        lpszVolumeMountPoint: [*]win.WCHAR,
        cchBufferLength: u32
    ) callconv(WINAPI) win.BOOL;

    pub extern "kernel32" fn GetLogicalDriveStringsW(
        nBufferLength: win.DWORD,
        lpBuffer: ?[*]win.WCHAR,
    ) callconv(WINAPI) win.DWORD;

    pub extern "kernel32" fn GetVolumeNameForVolumeMountPointW(
        lpszVolumeMountPoint: [*:0]const win.WCHAR,
        lpszVolumeName: [*]win.WCHAR,
        cchBufferLength: win.DWORD
    ) callconv(WINAPI) win.BOOL;


    // My best guess is that windows expects all enums inside structs to be 32 bits?
    const MEDIA_TYPE = enum(i32) {
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

fn getDiskGeo(drive_handle: win32.HANDLE) !win32.DISK_GEOMETRY {
    var disk_geo : win32.DISK_GEOMETRY = undefined;
    {
        var bytes_returned : u32 = undefined;
        const result = win32.DeviceIoControl(
            drive_handle,
            win32.IOCTL_DISK_GET_DRIVE_GEOMETRY,
            null, 0,
            &disk_geo, @sizeOf(@TypeOf(disk_geo)),
            &bytes_returned,
            null);
        if (result == 0) {
            std.debug.print("Error: DeviceIoControl IOCTL_DISK_GET_DRIVE_GEOMETRY failed with {}\n", .{
                win32.GetLastError()});
            return error.AlreadyReported;
        }
    }
    return disk_geo;
}
fn sumDiskSize(geo: win32.DISK_GEOMETRY) u64 {
    return
        @intCast(u64, geo.Cylinders) *
        @intCast(u64, geo.TracksPerCylinder) *
        @intCast(u64, geo.SectorsPerTrack) *
        @intCast(u64, geo.BytesPerSector);
}

//fn dumpDiskGeo(geo: DISK_GEOMETRY) !void {
//    const disk_size = sumDiskSize(geo);
//    var typed_disk_size : f32 = @intToFloat(f32, disk_size);
//    var size_unit : []const u8 = undefined;
//    getNiceSize(&typed_disk_size, &size_unit);
//    std.debug.print(
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

fn printDiskSummary(writer: anytype, optional_drive_index: ?u8, drive: []const u16, geo: win32.DISK_GEOMETRY) !void {
    const disk_size = sumDiskSize(geo);
    var typed_disk_size : f32 = @intToFloat(f32, disk_size);
    var size_unit : []const u8 = undefined;
    getNiceSize(&typed_disk_size, &size_unit);
    if (optional_drive_index) |drive_index| {
        std.debug.print("{}: ", .{drive_index});
    }
    try writer.print("\"{}\" {d:.1} {s} {}\n", .{
        std.unicode.fmtUtf16le(drive),
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
fn dismountDisk(disk_handle: win32.HANDLE) !void {
    var unused : u32 = undefined;
    const result = win32.DeviceIoControl(
        disk_handle,
        win32.FSCTL_DISMOUNT_VOLUME,
        null, 0,
        null, 0,
        &unused,
        null);
    if (result == 0) {
        std.debug.print("Error: DeviceIoControl FSCTL_DISMOUNT_VOLUME failed with {}\n", .{
            win32.GetLastError()});
        return error.AlreadyReported;
    }
}
fn lockDisk(disk_handle: win32.HANDLE) !void {
    var unused : u32 = undefined;
    const result = win32.DeviceIoControl(
        disk_handle,
        win32.FSCTL_LOCK_VOLUME,
        null, 0,
        null, 0,
        &unused,
        null);
    if (result == 0) {
        std.debug.print("Error: DeviceIoControl FSCTL_LOCK_VOLUME failed with {}\n", .{
            win32.GetLastError()});
        return error.AlreadyReported;
    }
}

fn openDisk(disk_name: [:0]const u16, access: u32) !win32.HANDLE {
    const disk_handle = win32.CreateFileW(
        disk_name,
        access,
        win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
        null,
        win32.OPEN_EXISTING,
        //win32.FILE_ATTRIBUTE_NORMAL,
        win32.FILE_FLAG_NO_BUFFERING | win32.FILE_FLAG_RANDOM_ACCESS,
        null
    );
    if (disk_handle == win32.INVALID_HANDLE_VALUE) {
        switch (win32.GetLastError()) {
            .SHARING_VIOLATION => return error.SharingViolation,
            .ALREADY_EXISTS => return error.PathAlreadyExists,
            .FILE_EXISTS => return error.PathAlreadyExists,
            .FILE_NOT_FOUND => return error.FileNotFound,
            .PATH_NOT_FOUND => return error.FileNotFound,
            .ACCESS_DENIED => return error.AccessDenied,
            .PIPE_BUSY => return error.PipeBusy,
            .FILENAME_EXCED_RANGE => return error.NameTooLong,
            else => |err| return std.os.windows.unexpectedError(err),
        }
    }
    return disk_handle;
}

fn enforceArgCount(args: []const[]const u8, count: usize) !void {
    if (args.len != count) {
        std.debug.print("this command should have {} argument(s) but got {}\n", .{count, args.len});
        return error.AlreadyReported;
    }
}

fn promptYesNo(allocator: mem.Allocator, prompt: []const u8) !bool {
    var answer = std.ArrayList(u8).init(allocator);
    defer answer.deinit();
    while (true) {
        std.debug.print("{s}[y/n]? ", .{prompt});
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
    const allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator).allocator();
    var args = (try std.process.argsAlloc(allocator))[1..];
    if (args.len == 0) {
        std.debug.print(
            \\Usage: windows-imager COMMAND ARGS...
            \\  list              list physical disks (use 'listjson' to print details in JSON format)
            \\  image DRIVE FILE  image the given drive with the given file (use '-' as FILE for stdin)
            \\  read DRIVE FILE   read the given drive to the given file (use '-' as FILE for stdout)
            \\  listvolumes       list volume paths (i.e. \\?\Volume{{6abe...}}\)
            \\  listlogicaldrives list logical drives (i.e. C:\)
            , .{});
        return 1;
    }

    const cmd = args[0];
    args = args[1..];

    const list_json = mem.eql(u8, cmd, "listjson");
    if (list_json or mem.eql(u8, cmd, "list")) {
        try enforceArgCount(args, 0);
        const stdout = std.io.getStdOut().writer();
        if (list_json) {
            try stdout.writeAll("[\n");
        }
        {var i: u8 = 0; while (true) : (i += 1) {
            const disk_name = PhysicalDriveString.init(i);
            const disk_handle = openDisk(&disk_name.str, 0) catch |e| switch (e) {
                error.FileNotFound => break,
                else => return e,
            };
            const disk_geo = try getDiskGeo(disk_handle);
            if (list_json) {
                const name_utf8 = try std.unicode.utf16leToUtf8Alloc(allocator, &disk_name.str);
                defer allocator.free(name_utf8);
                const prefix: []const u8 = if (i == 0) "" else ",";
                try stdout.print("    {s}{{\n", .{prefix});
                try stdout.writeAll("        \"name\": ");
                try std.json.stringify(name_utf8, .{}, stdout);
                try stdout.writeAll(",\n");
                try stdout.print("        \"size\": {}\n", .{sumDiskSize(disk_geo)});
                try stdout.writeAll("    }\n");
            } else {
                try printDiskSummary(stdout, i, &disk_name.str, disk_geo);
            }
        }}
        if (list_json) {
            try stdout.writeAll("]");
        }
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

    if (mem.eql(u8, cmd, "read")) {
        try enforceArgCount(args, 2);
        const drive = try std.unicode.utf8ToUtf16LeWithNull(allocator, args[0]);
        const optional_file = if (mem.eql(u8, args[1], "-")) null else try std.unicode.utf8ToUtf16LeWithNull(allocator, args[1]);

        const disk_handle = openDisk(drive, win32.GENERIC_READ) catch |e| {
            std.debug.print("Error: Failed to open drive \"{}\" {}\n", .{std.unicode.fmtUtf16le(drive), e});
            return error.AlreadyReported;
        };
        const disk_geo = try getDiskGeo(disk_handle);
        try printDiskSummary(std.io.getStdErr().writer(), null, drive, disk_geo);

        const disk_size = sumDiskSize(disk_geo);
        {
            var typedDiskSize : f32 = @intToFloat(f32, disk_size);
            var suffix : []const u8 = undefined;
            getNiceSize(&typedDiskSize, &suffix);
            std.debug.print("disk size is {} ({d:.2} {s})\n", .{disk_size, typedDiskSize, suffix});
        }

        if (!try promptYesNo(allocator, "Are you sure you would like to read this drive? ")) {
            return 1;
        }

        // Do the prompt before overwriting the output file.
        const file_handle = blk: {
            if (optional_file) |file| {
                const handle = win32.CreateFileW(
                    file,
                    win32.GENERIC_WRITE,
                    win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
                    null,
                    win32.CREATE_ALWAYS,
                    win32.FILE_ATTRIBUTE_NORMAL,
                    null,
                );
                if (handle == win32.INVALID_HANDLE_VALUE) {
                    std.debug.print("Error: failed to open '{s}', error={s}\n", .{std.unicode.fmtUtf16le(file), @tagName(win32.GetLastError())});
                    return error.AlreadyReported;
                }
                break :blk handle;
            }
            break :blk std.io.getStdOut().handle;
        };

        // TODO: what is a good transfer size? Do some perf testing
        // TODO: also, make this a command-lin option
        //const transfer_size = disk_geo.BytesPerSector;
        const transfer_size = 1024 * 1024;
        {
            // TODO: should this allocation be aligned?  Do some perf testing to see if it helps
            const buf = try allocator.alloc(u8, transfer_size);
            defer allocator.free(buf);
            try readDisk(disk_handle, file_handle, disk_size, buf);
        }
        std.debug.print("Successfully read drive\n", .{});
        return 0;
    }

    if (mem.eql(u8, cmd, "image")) {
        try enforceArgCount(args, 2);
        const drive = try std.unicode.utf8ToUtf16LeWithNull(allocator, args[0]);
        //const fileSlice = args[1];
        //const file = try allocator.allocSentinel(u8, fileSlice.len, 0);
        //mem.copy(u8, file, fileSlice);
        const optional_file = if (mem.eql(u8, args[1], "-")) null else try std.unicode.utf8ToUtf16LeWithNull(allocator, args[1]);

        const disk_handle = openDisk(drive, win32.GENERIC_READ | win32.GENERIC_WRITE) catch |e| {
            std.debug.print("Error: Failed to open drive \"{}\" {}\n", .{std.unicode.fmtUtf16le(drive), e});
            return error.AlreadyReported;
        };
        const disk_geo = try getDiskGeo(disk_handle);
        try printDiskSummary(std.io.getStdErr().writer(), null, drive, disk_geo);

        const file_handle = blk: {
            if (optional_file) |file| {
                const handle = win32.CreateFileW(
                    file,
                    win32.GENERIC_READ,
                    win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
                    null,
                    win32.OPEN_EXISTING,
                    win32.FILE_ATTRIBUTE_NORMAL,
                    null,
                );
                if (handle == win32.INVALID_HANDLE_VALUE) {
                    std.debug.print("Error: failed to open '{s}', error={s}\n", .{std.unicode.fmtUtf16le(file), @tagName(win32.GetLastError())});
                    return error.AlreadyReported;
                }
                break :blk handle;
            }
            break :blk std.io.getStdIn().handle;
        };

        const disk_size = sumDiskSize(disk_geo);
        const max_size: u64 = blk: {
            if (optional_file) |_| {
                const file_size = try win32.GetFileSizeEx(file_handle);
                {
                    var typedFileSize : f32 = @intToFloat(f32, file_size);
                    var suffix : []const u8 = undefined;
                    getNiceSize(&typedFileSize, &suffix);
                    std.debug.print("file size is {} ({d:.2} {s})\n", .{file_size, typedFileSize, suffix});
                }
                if (file_size > disk_size) {
                    std.debug.print("Error: file is too big\n", .{});
                    return error.AlreadyReported;
                }
                // we only prompt if reading from a file, otherwise we can't use stdin to prompt the user
                if (!try promptYesNo(allocator, "Are you sure you would like to re-image this drive? ")) {
                    return 1;
                }
                break :blk file_size;
            }
            break :blk disk_size;
        };

        // TODO: what is a good transfer size? Do some perf testing
        //const transfer_size = disk_geo.BytesPerSector;
        const transfer_size = 1024 * 1024;
        {
            // TODO: should this allocation be aligned?  Do some perf testing to see if it helps
            const buf = try allocator.alloc(u8, transfer_size);
            defer allocator.free(buf);
            try imageDisk(disk_handle, file_handle, max_size, buf, if (optional_file) |_| false else true);
        }
        std.debug.print("Successfully imaged drive\n", .{});
        return 0;
    }

    std.debug.print("Error: unknown command '{s}'\n", .{cmd});
    return 1;
}

// max_size the disk size for streams, and the file size for non-streams
fn imageDisk(disk_handle: win32.HANDLE, file_handle: win32.HANDLE, max_size: u64, buf: []u8, is_stream: bool) !void {
    std.debug.print("dismounting disk...\n", .{});
    try dismountDisk(disk_handle);
    std.debug.print("locking disk...\n", .{});
    try lockDisk(disk_handle);
    std.debug.print("disk ready to write\n", .{});

    // do I need to do this?
    //try win32.SetFilePointerEx_BEGIN(disk_handle, 0);

    var total_processed : u64 = 0;
    var last_report_ticks = win32.GetTickCount();
    const report_frequency = 1000; // report every 1000 ms

    while (total_processed < max_size) {
        const max_read = max_size - total_processed;
        const size = try readFile(file_handle, buf[0..std.math.min(buf.len, max_read)]);
        //std.debug.print("[DEBUG] read {} bytes\n", .{size});
        if (is_stream) {
            if (size == 0) break;
        } else {
            std.debug.assert(size > 0);
        }

        //try win32.SetFilePointerEx_BEGIN(disk_handle, total_processed);

        // TODO: if this is the last read, need to pad with zeros
        try writeFileAll(disk_handle, buf.ptr, size);

        total_processed += size;
        //std.debug.print("[DEBUG] write {} bytes (total={})\n", .{size, total_processed});
        const now = win32.GetTickCount();
        // TODO: allow rollover
        if ((now - last_report_ticks) > report_frequency) {
            if (is_stream) {
                std.debug.print("{} bytes\n", .{total_processed});
            } else {
                const progress = @intToFloat(f32, total_processed) / @intToFloat(f32, max_size) * 100;
                std.debug.print("{d:.0}% ({} bytes)\n", .{progress, total_processed});
            }
            last_report_ticks = now;
        }
    }
}


fn readDisk(disk_handle: win32.HANDLE, file_handle: win32.HANDLE, disk_size: u64, buf: []u8) !void {
    var total_processed : u64 = 0;
    var last_report_ticks = win32.GetTickCount();
    const report_frequency = 1000; // report every 1000 ms

    while (total_processed < disk_size) {
        const size = try readFile(disk_handle, buf);
        std.debug.assert(size > 0);
        //std.debug.print("[DEBUG] read {} bytes\n", .{size});

        try writeFileAll(file_handle, buf.ptr, size);

        total_processed += size;
        //std.debug.print("[DEBUG] write {} bytes (total={})\n", .{size, total_processed});
        const now = win32.GetTickCount();
        // TODO: allow rollover
        if ((now - last_report_ticks) > report_frequency) {
            const progress = @intToFloat(f32, total_processed) / @intToFloat(f32, disk_size) * 100;
            std.debug.print("{d:.0}% ({} bytes)\n", .{progress, total_processed});
            last_report_ticks = now;
        }
    }
}


fn readFile(handle: win32.HANDLE, buffer: []u8) !u32 {
    const buffer_len = std.math.cast(u32, buffer.len) catch std.math.maxInt(u32);
    while (true) {
        var bytes_read: u32 = undefined;
        if (0 != win32.ReadFile(handle, buffer.ptr, buffer_len, &bytes_read, null))
            return bytes_read;
        switch (win32.GetLastError()) {
            .OPERATION_ABORTED => continue,
            .BROKEN_PIPE => return 0,
            .HANDLE_EOF => return 0,
            else => |err| return std.os.windows.unexpectedError(err),
        }
    }
}

fn writeFileAll(handle: win32.HANDLE, ptr: [*]const u8, len: u32) error{AlreadyReported}!void {
    var total_written: u32 = 0;
    while (total_written < len) {
        const next_size = len - total_written;
        var written : u32 = undefined;
        if (0 == win32.WriteFile(handle, ptr + total_written, next_size, &written, null)) {
            std.debug.print("Error: WriteFile (size={}, total_written={}) failed, error={s}\n",.{
                next_size, total_written, @tagName(win32.GetLastError())});
            return error.AlreadyReported;
        }
        std.debug.assert(written <= next_size);
        total_written += written;
    }
}

fn listVolumes() !void {
    var buf : [200]u16 = undefined;
    const fh = win32.FindFirstVolumeW(&buf, buf.len);
    if (fh == win32.INVALID_HANDLE_VALUE) {
        const err = win32.GetLastError();
        if (err == .NO_MORE_FILES)
            return;
        std.debug.print("Error: FindFirstVolumeW failed with {}\n", .{err});
        return error.AlreadyReported;
    }
    defer {
        if (0 == win32.FindVolumeClose(fh))
            std.debug.panic("FindVolumeClose failed with {}", .{win32.GetLastError()});
    }
    while (true) {
        const s : []u16 = &buf;
        const s_ptr = std.meta.assumeSentinel(s.ptr, 0);
        std.debug.print("{}\n", .{std.unicode.fmtUtf16le(std.mem.span(s_ptr))});
        try printDriveLetterName(s_ptr);
        try listVolumeMounts(s_ptr);
        if (0 == win32.FindNextVolumeW(fh, &buf, buf.len)) {
            const err = win32.GetLastError();
            if (err == .NO_MORE_FILES)
                break;
            std.debug.print("Error: FindNextVolumeW failed with {}\n", .{err});
            return error.AlreadyReported;
        }
    }
}

fn listVolumeMounts(volume: [*:0]const u16) !void {
    var buf : [200]u16 = undefined;
    const fh = win32.FindFirstVolumeMountPointW(volume, &buf, buf.len);
    if (fh == win32.INVALID_HANDLE_VALUE) {
        switch (win32.GetLastError()) {
            .NO_MORE_FILES => {
                std.debug.print("    no mount points\n", .{});
                return;
            },
            .ACCESS_DENIED,
            .PATH_NOT_FOUND,
            .UNRECOGNIZED_VOLUME,
            => |e| {
                std.debug.print("    error: failed to get mount points ({s})\n", .{@tagName(e)});
                return;
            },
            else => |e| {
                std.debug.print("    error: FindFirstVolumeMountPointW failed with {s}\n", .{@tagName(e)});
                return error.AlreadyReported;
            },
        }
    }
    defer {
        if (0 == win32.FindVolumeMountPointClose (fh))
            std.debug.panic("FindVolumeMountPointClose  failed with {}", .{win32.GetLastError()});
    }
    while (true) {
        const s : []u16 = &buf;
        std.debug.print("{}\n", .{std.unicode.fmtUtf16le(std.mem.span(std.meta.assumeSentinel(s.ptr, 0)))});
        if (0 == win32.FindNextVolumeMountPointW(fh, &buf, buf.len)) {
            const err = win32.GetLastError();
            if (err == .NO_MORE_FILES)
                break;
            std.debug.print("Error: FindNextVolumeMountPointW failed with {}\n", .{err});
            return error.AlreadyReported;
        }
    }
}

fn printDriveLetterName(volume: [*:0]const u16) !void {
    _ = volume;
    // TODO: implement
}

fn getLogicalDriveStrings(allocator: *const mem.Allocator) ![:0]u16 {
    const len = win32.GetLogicalDriveStringsW(0, null);
    if (len == 0) {
        std.debug.print("Error: GetLogicalDriveStrings failed with {}\n", .{win32.GetLastError()});
        return error.AlreadyReported;
    }
    const buf = try allocator.alloc(u16, len);
    errdefer allocator.free(buf);

    const result = win32.GetLogicalDriveStringsW(len, buf.ptr);
    std.debug.assert(len == result + 1);
    std.debug.assert(buf[len-1] == 0);

    return std.meta.assumeSentinel(buf, 0);
}

fn listLogicalDrives() !void {
    const drives = try getLogicalDriveStrings(&std.heap.page_allocator);
    defer std.heap.page_allocator.free(drives);
    var next_drive_ptr = drives.ptr;
    while (true)
    {
        const next_drive = mem.span(next_drive_ptr);
        if (next_drive.len == 0)
            break;
        var volume_name_buf : [win32.MAX_PATH]u16 = undefined;

        if (0 == win32.GetVolumeNameForVolumeMountPointW(next_drive, &volume_name_buf, volume_name_buf.len)) {
            std.debug.print("{} (failed to get volume {})\n", .{std.unicode.fmtUtf16le(next_drive), win32.GetLastError()});
        } else {
            const volume_name = mem.span(std.meta.assumeSentinel(@as([]u16, &volume_name_buf).ptr, 0));
            std.debug.print("{} {}\n", .{std.unicode.fmtUtf16le(next_drive), std.unicode.fmtUtf16le(volume_name)});
        }

        next_drive_ptr += next_drive.len + 1;
    }
}
