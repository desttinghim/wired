#!/usr/bin/env bash

butler push bundle/windows/ desttinghim/wired:windows   --userversion $1
butler push bundle/linux/ desttinghim/wired:linux       --userversion $1
butler push bundle/mac/ desttinghim/wired:mac           --userversion $1
butler push bundle/html/ desttinghim/wired:html         --userversion $1
butler push bundle/cart/ desttinghim/wired:cart         --userversion $1
