# Package

version       = "0.2.0"
author        = "Michael Taggart and Reilly Moore"
description   = "Directory brute-forcer written in Nim. Because we needed another one."
license       = "MIT"
srcDir        = "src"
bin           = @["nimbuster"]


# Dependencies

requires "nim >= 1.4.8"
requires "termstyle >= 0.1.0"
requires "cligen >= 1.5.19"