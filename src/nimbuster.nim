import std/[
  sequtils,
  strutils,
  threadpool,
  cpuinfo,
  strformat,
  httpclient
]

# Uses macro magic to turn procs into CLIs: github.com/c-blake/cligen
import cligen

# Exit gracefully on Ctrl-C, instead of writing a stack trace to the terminal.
setControlCHook(
  proc() {.noconv.} =
    quit "Aborted.", 1
)

proc bust(url: string, wl: seq[string]) {.thread.} =
  # This proc performs the actual busting. We put it in its own proc so that
  # we can call it in parallel.
  
  var client = newHttpClient()
  for w in wl:
    # In the original implementation, the status code was obtained with
    # `r.status.substr(0,2)`, which returns a string. Instead of doing this,
    # `std/httpclient` provides a `code()` proc which will get the status code
    # for you, and it will return it in the form of an HttpCode enum. It's
    # better to use an enum for this since there are a finite number of unique
    # HTTP status codes, whereas there are an infinite number of unique strings.
    # This is also good for when you're using a `case` block, as Nim will force
    # you to either cover every possible status code or explicitly ignore the
    # ones you aren't handling.

    # Since we made sure that the url ended with a forward slash, we can just
    # concatenate the two strings.
    if client.get(url & w).code() in [Http200, Http301, Http302]:
      echo url & w

proc main(url, wordlist: string, threads: Natural = countProcessors()) =
  # This is the entrypoint for the program.
  # 
  # `url` is the domain name to bust.
  # 
  # `wordlist` is the path to the text file containing the list of words
  # you want to search for.
  # 
  # `threads` is the number of threads you want to use. It defaults to the
  # maximum number of threads available on your machine.
  # 
  # Note that we use `Natural` for the type of the `threads` argument.
  # This is a special integer type that requires the argument to be in the
  # range of `0..high(int)`, so we don't have to worry about negative
  # numbers as input. We also have special checks for when `threads` is equal
  # to zero or when it is greater than the number of cores/threads available
  # on the CPU. The implementations of these checks are below.
  
  # `countProcessors()` returns the total number of cores/threads on the CPU.
  let max_threads = countProcessors()

  if threads == 0:
    # `countProcessors()` returns 0 if it couldn't detect the number of
    # cores/threads. Handle this just in case.
    quit "Could not automatically detect CPU cores. Please use the `--threads` flag.", -1
  elif threads > max_threads:
    # Prevent the `threads` argument from being greater than the number of
    # available threads on the machine.
    quit fmt"Your machine has a maximum of {max_threads} threads.", -1
  # At this point, thanks to these two checks as well as Nim's type system,
  # it's guaranteed that the value of `threads` will be somewhere in the range
  # of `1..countProcessors()` inclusive.

  # Split the contents of the `wordlist` file into equal-sized chunks, the
  # number of chunks being equal to the number of threads. We can also filter
  # out any lines that we don't want, such as empty lines or comments.
  let wl = lines(wordlist).toSeq().filterIt(
    not(it.startsWith("#")) and it != ""
  ).distribute(threads)

  # If `url` does not already end with a forward slash, add one.
  # `std/os` implements a `/` proc that does something similar, but it will
  # use a backslash on Windows as it's intended for directories, not URLs.
  # Therefore, we just do it ourselves instead.
  let u =
    if url.endsWith("/"): url
    else: url & "/"

  # Spawn the number of threads we want.
  for x in 1..<threads:
    spawn bust(u, wl[x])
  
  # Do work in the main thread too.
  bust(u, wl[0])

  # Wait for all of the threads to finish execution.
  sync()

# The `dispatch()` proc from cligen takes any proc as input and automagically
# turns it into a complete CLI. We also pass in some help text.
dispatch(main,
  help = {
    "url": "the URL to scan",
    "wordlist": "the list of directories to search for"
  }
)