# Package

version       = "0.1.0"
author        = "Michael Taggart"
description   = "Directory brute-forcer written in Nim. Because we needed another one."
license       = "MIT"
srcDir        = "src"
bin           = @["nimbuster"]


# Dependencies

requires "nim >= 1.6.0"
requires "cligen >= 1.5.19"