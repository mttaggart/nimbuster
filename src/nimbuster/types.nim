# It's convention to place a package's submodules in `./src/<package name>`.
# This folder will be automatically created for you when creating a library with
# Nimble, but it's not done for executables for some reason.

# The only thing we need to import is just `HttpCode`, so let's import only
# that from `std/httpcore`.
from std/httpcore import HttpCode

# Since we're using the main thread to display a progress bar and to write to a
# file, we now need at least two threads to do work. Let's define our own
# integer type with a minimum value of 2 and a maximum value of the system's
# integer limit. We can't set the maximum to be the number of threads because
# the `countProcessors()` proc calls C code to do work. The FFI is not available
# to Nim's virtual machine, thus that proc cannot be executed at compile-time.
# (Nim evaluates this custom type at compile-time, but the bounds checking is
# performed at runtime.)
#
# Cligen will automatically detect the bounds for this type and enforce them.
#
# And I'm sure you've already noticed, but an asterisk after an indentifier
# exports the identifier for other modules to import.
type ThreadCount* = 2..high(int)

# While we're at it, let's also define a custom tuple type. We'll use this when
# passing messages from the spawned threads to the main thread. This tuple will
# contain The HTTP response code returned by a particular request, and the word
# used for that particular request. In our main thread, we'll count how many
# messages we've received so that we can keep track of our progress. However, we
# will only write the result to a file if the HTTP code is within a list.
#
# The first element in the tuple is the `HttpCode` type. I erroneously called
# this an enum originally, but in reality it's actually just a distinct integer
# type with a restricted range. A "distinct" type is a type that doesn't inherit
# anything from its parent type. For example, you cannot do arithmetic using
# `HttpCode`s, even though internally they're just integers.
#
# The second element is the word used for a given request, so the main thread
# can log it to a file.
#
# The final elemnt is a boolean that will be `true` if the thread has finished
# execution. Otherwise, it will be false. We can just keep track of each
# thread's most recent return value to know if they've all finished, as we can't
# just use `sync()` anymore since we need the main thread to be doing work while
# the other threads are running.
type ThreadResponse* = tuple[code: HttpCode, word: string, done: bool]