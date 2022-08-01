#!/usr/bin/env bash

zig build opt -Drelease-small
mkdir -p bundle/html
mkdir -p bundle/linux
mkdir -p bundle/windows
mkdir -p bundle/mac
mkdir -p bundle/cart
npx wasm4 bundle --html bundle/html/index.html --linux bundle/linux/wired --windows bundle/windows/wired.exe --mac bundle/mac/wired zig-out/lib/opt.wasm
cp zig-out/lib/opt.wasm bundle/cart/cart.wasm
