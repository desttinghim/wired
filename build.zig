const std = @import("std");
const LDtkImport = @import("tools/LDtkImport.zig");

pub fn build(b: *std.build.Builder) !void {
    const assets = std.build.Pkg{
        .name = "assets",
        .source = .{ .path = "assets/assets.zig" },
    };

    const ldtk = LDtkImport.create(b, .{
        .source_path = .{ .path = "assets/maps/wired.ldtk" },
        .output_name = "mapldtk",
    });

    const data_step = b.addOptions();
    data_step.addOptionFileSource("path", .{.generated = &ldtk.world_data });

    const mode = b.standardReleaseOptions();
    const lib = b.addSharedLibrary("cart", "src/main.zig", .unversioned);
    lib.step.dependOn(&data_step.step);
    lib.addPackage(data_step.getPackage("world_data"));
    lib.addPackage(assets);
    lib.setBuildMode(mode);
    lib.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    lib.import_memory = true;
    lib.initial_memory = 65536;
    lib.max_memory = 65536;
    lib.stack_size = 24752;

    // Workaround https://github.com/ziglang/zig/issues/2910, preventing
    // functions from compiler_rt getting incorrectly marked as exported, which
    // prevents them from being removed even if unused.
    lib.export_symbol_names = &[_][]const u8{ "start", "update" };
    lib.install();

    const prefix = b.getInstallPath(.lib, "");
    const opt = b.addSystemCommand(&[_][]const u8{
        "wasm-opt",
        "-Oz",
        "--strip-debug",
        "--strip-producers",
        "--zero-filled-memory",
    });

    opt.addArtifactArg(lib);
    const optout = try std.fs.path.join(b.allocator, &.{ prefix, "opt.wasm" });
    defer b.allocator.free(optout);
    opt.addArgs(&.{ "--output", optout });

    const opt_step = b.step("opt", "Run wasm-opt on cart.wasm, producing opt.wasm");
    opt_step.dependOn(&lib.step);
    opt_step.dependOn(&opt.step);
}
