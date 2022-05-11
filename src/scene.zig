const std = @import("std");
const StackAllocator = @import("mem.zig").StackAllocator;

pub fn Manager(comptime Context: type, comptime Scenes: []const type) type {
    comptime var scene_enum: std.builtin.Type.Enum = std.builtin.Type.Enum{
        .layout = .Auto,
        .tag_type = usize,
        .fields = &.{},
        .decls = &.{},
        .is_exhaustive = false,
    };
    inline for (Scenes) |t, i| {
        scene_enum.fields = scene_enum.fields ++ [_]std.builtin.Type.EnumField{.{.name = @typeName(t), .value = i}};
    }
    const SceneEnum = @Type(.{.Enum = scene_enum});
    return struct {
        sa: *StackAllocator,
        ctx: *Context,
        scenes: std.ArrayList(ScenePtr),

        pub const Scene = SceneEnum;
        pub const ScenePtr = struct {which: usize, ptr: *anyopaque};

        fn init(ctx: *Context, scene_allocator: *StackAllocator, alloc: std.mem.Allocator) @This() {
            return @This() {
                .sa = scene_allocator,
                .ctx = ctx,
                .scenes = std.ArrayList(ScenePtr).init(alloc),
            };
        }

        fn deinit(this: *@This()) void {
            this.scenes.deinit();
        }

        pub fn push(this: *@This(), comptime which: SceneEnum) !*Scenes[@enumToInt(which)] {
            const i = @enumToInt(which);
            const scene = try this.sa.allocator().create(Scenes[i]);
            scene.* = @field(Scenes[i], "init")(this.ctx);
            try this.scenes.append(.{.which = i, .ptr = scene});
            return scene;
        }

        pub fn pop(this: *@This()) void {
            const scene = this.scenes.popOrNull() orelse return;
            inline for (Scenes) |S, i| {
                if (i == scene.which) {
                    const ptr = @ptrCast(*S, @alignCast(@alignOf(S), scene.ptr));
                    @field(S,"deinit")(ptr);
                    this.sa.allocator().destroy(ptr);
                }
                break;
            }
        }

        pub fn tick(this: *@This()) void {
            if (this.scenes.items.len == 0) return;
            const scene = this.scenes.items[this.scenes.items.len - 1];
            inline for (Scenes) |S, i| {
                if (i == scene.which) {
                    const ptr = @ptrCast(*S, @alignCast(@alignOf(S), scene.ptr));
                    @field(S,"update")(ptr);
                }
                break;
            }
        }

        const NullScene = struct {
            fn init(_:*Context) @This() { return @This(){}; }
            fn update(_:*@This()) anyerror!void {}
        };
    };
}


test "Scene Manager" {
    const Ctx = struct { count: usize };
    const Example = struct {
        ctx: *Ctx,
        fn init(ctx: *Ctx)  @This() {
            return @This(){
                .ctx = ctx,
            };
        }
        fn deinit(_: *@This()) void {}
        fn update(this: *@This())  void {
            this.ctx.count += 1;
        }
    };
    const SceneManager = Manager(Ctx, &[_]type{Example});
    var ctx = Ctx{.count = 0};

    var heap: [128]u8 = undefined;
    var sa = StackAllocator.init(&heap);

    var sm = SceneManager.init(&ctx, &sa, std.testing.allocator);
    defer sm.deinit();

    const example_ptr = try sm.push(.Example);
    example_ptr.update();
    try std.testing.expectEqual(@as(usize, 1), ctx.count);

    sm.tick();
    try std.testing.expectEqual(@as(usize, 2), ctx.count);

    sm.pop();
}
