#!/usr/bin/env bash

w4 png2src --template assets/assets-template --zig assets/tiles.png -o assets/tiles.zig
zig run map2src.zig -- assets/maps/map.zig assets/maps/map.json
