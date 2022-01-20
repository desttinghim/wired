const std = @import("std");
const ArgsTuple = std.meta.Tuple;
const Tuple = std.meta.Tuple;

pub fn World(comptime ComponentBase: type) type {
    // Build a component type at comptime based off of ComponentBase. It makes all the fields
    // nullable so they are easy to pull out of the store.
    const ComponentCon = componentConstructor: {
        var fields = std.meta.fields(ComponentBase);
        var newFields: [fields.len]std.builtin.TypeInfo.StructField = undefined;
        inline for (fields) |field, i| {
            const T = field.field_type;
            const default: ?T = null;
            newFields[i] = std.builtin.TypeInfo.StructField{
                .name = field.name,
                .field_type = ?T,
                .default_value = default,
                .is_comptime = false,
                .alignment = if (@sizeOf(T) > 0) @alignOf(T) else 0,
            };
        }
        break :componentConstructor @Type(.{ .Struct = .{
            .layout = .Auto,
            .fields = &newFields,
            .decls = &[_]std.builtin.TypeInfo.Declaration{},
            .is_tuple = false,
        } });
    };
    return struct {
        components: ComponentPool,
        alloc: std.mem.Allocator,
        pub const Query = ComponentQuery;
        pub const Component = ComponentCon;

        const ComponentPool = std.MultiArrayList(Component);
        const ComponentEnum = std.meta.FieldEnum(Component);
        const ComponentSet = std.EnumSet(ComponentEnum);
        const ComponentQuery = struct {
            required: ComponentSet = ComponentSet.init(.{}),
            excluded: ComponentSet = ComponentSet.init(.{}),

            pub fn init() @This() {
                return @This(){};
            }

            pub fn query(require_set: []const ComponentEnum, exclude_set: []const ComponentEnum) @This() {
                var this = @This(){};
                for (require_set) |f| {
                    this.required.insert(f);
                }
                for (exclude_set) |f| {
                    this.excluded.insert(f);
                }
                return this;
            }

            pub fn require(require_set: []const ComponentEnum) @This() {
                var this = @This(){};
                for (require_set) |f| {
                    this.required.insert(f);
                }
                return this;
            }

            pub fn exclude(exclude_set: []const ComponentEnum) @This() {
                var this = @This(){};
                for (exclude_set) |f| {
                    this.excluded.insert(f);
                }
                return this;
            }
        };

        const fields = std.meta.fields(Component);

        pub fn init(alloc: std.mem.Allocator) @This() {
            return @This(){
                .components = ComponentPool{},
                .alloc = alloc,
            };
        }

        pub fn create(this: *@This(), component: Component) !usize {
            const len = this.components.len;
            try this.components.append(this.alloc, component);
            return len;
        }

        pub fn destroy(this: *@This(), entity: usize) void {
            // TODO
            _ = this;
            _ = entity;
            @compileError("unimplemented");
        }

        /// Returns a copy of the components on an entity
        pub fn get(this: *@This(), entity: usize) Component {
            return this.components.get(entity);
        }

        pub fn set(this: *@This(), entity: usize, component: Component) void {
            this.components.set(entity, component);
        }

        fn enum2type(comptime enumList: []const ComponentEnum) []type {
            var t: [enumList.len]type = undefined;
            inline for (enumList) |e, i| {
                const field_type = @typeInfo(fields[@enumToInt(e)].field_type);
                t[i] = *field_type.Optional.child;
            }
            return &t;
        }

        pub fn process(this: *@This(), dt: f32, comptime comp: []const ComponentEnum, func: anytype) void {
            const Args = Tuple([_]type{f32} ++ enum2type(comp));
            var i = this.iter(Query.require(comp));
            while (i.next()) |eID| {
                var e = this.get(eID);
                var args: Args = undefined;
                args[0] = dt;
                inline for (comp) |f, j| {
                    args[j + 1] = &(@field(e, @tagName(f)).?);
                }
                @call(.{}, func, args);
                this.set(eID, e);
            }
        }

        pub fn processWithID(this: *@This(), dt: f32, comptime comp: []const ComponentEnum, func: anytype) void {
            const Args = Tuple([_]type{ f32, usize } ++ enum2type(comp));
            var i = this.iter(Query.require(comp));
            while (i.next()) |eID| {
                var e = this.get(eID);
                var args: Args = undefined;
                args[0] = dt;
                args[1] = eID;
                inline for (comp) |f, j| {
                    args[j + 2] = &(@field(e, @tagName(f)).?);
                }
                @call(.{}, func, args);
                this.set(eID, e);
            }
        }

        pub fn iterAll(this: *@This()) Iterator {
            return Iterator.init(this, ComponentQuery{});
        }

        pub fn iter(this: *@This(), query: ComponentQuery) Iterator {
            return Iterator.init(this, query);
        }

        const Self = @This();
        const Iterator = struct {
            world: *Self,
            index: usize,
            query: ComponentQuery,

            pub fn init(w: *Self, q: ComponentQuery) @This() {
                return @This(){
                    .world = w,
                    .index = 0,
                    .query = q,
                };
            }

            pub fn next(this: *@This()) ?usize {
                if (this.index == this.world.components.len) return null;
                var match = false;
                while (!match) {
                    if (this.index == this.world.components.len) return null;
                    const e = this.world.components.get(this.index);
                    match = true;
                    inline for (fields) |f| {
                        const fenum = std.meta.stringToEnum(ComponentEnum, f.name) orelse unreachable;
                        const required = this.query.required.contains(fenum);
                        const excluded = this.query.excluded.contains(fenum);
                        const has = @field(e, f.name) != null;
                        if ((required and !has) or (excluded and has)) {
                            match = false;
                            break;
                        }
                    }
                    this.index += 1;
                    if (match) return this.index - 1;
                }
                return null;
            }
        };
    };
}
