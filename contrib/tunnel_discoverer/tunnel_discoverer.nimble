# Package

version       = "20220927"
author        = "Emery Hemingway"
description   = "A utility for discovering Yggdrasil tunnel entrypoints using DNS"
license       = "LGPL-3.0-only"
srcDir        = "src"
bin           = @["tunnel_discoverer"]


# Dependencies

requires "nim >= 1.6.6", "getdns >= 20220927"
