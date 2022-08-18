# Wired

A puzzle platformer with wires.

## Controls

- Left/Right: Move left and right
- Up/Down: Look at items above and below
- X: Jump
- Z: Select

## Dependencies

- `zig` to compile the code
- `wasm-opt` to optimize the generated wasm file for release. It is a part of `binaryen`
- `wasm4` to run the generated cart

## Building

``` shellsession
git clone --recursive
zig build   # makes a debug build
w4 run zig-out/lib/cart.wasm
zig build opt -Drelease-small   # optimize cart size for release
```
