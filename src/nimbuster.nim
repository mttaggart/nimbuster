import std/[
  sequtils,
  strutils,
  threadpool,
  cpuinfo,
  strformat,
  httpclient,
  segfaults
]

# Uses macro magic to turn procs into CLIs: github.com/c-blake/cligen
import cligen

# Exit gracefully on Ctrl-C.
setControlCHook(
  proc() {.noconv.} =
    quit "Aborted.", 1
)

proc bust(url: string, wl: seq[string]) {.thread.} =
  ## This proc performs the actual busting. We put it in its own proc so that
  ## we can call it in parallel.
  
  var client = newHttpClient()
  for w in wl:
    if client.get(url & w).code() in [Http200, Http301, Http302]:
      echo url & w

proc main(url, wordlist: string, threads = countProcessors()) =
  ## This is the entrypoint for the program.
  ## 
  ## ``url`` is the domain name to bust.
  ## 
  ## ``wordlist`` is the path to the text file containing the list of words
  ## you want to search for.
  ## 
  ## ``threads`` is the number of threads you want to use. It defaults to the
  ## maximum number of threads available on your machine.
  
  # `countProcessors()` returns the total number of cores/threads on the CPU.
  let max_threads = countProcessors()

  if threads > max_threads:
    # Prevent the `threads` argument from being greater than the number of
    # available threads on the machine.
    quit fmt"Your machine has a maximum of {max_threads} threads.", -1

  # Split `wordlist` into equal-sized slices, the number of slices being
  # equal to the number of threads. Filter out lines that we don't want, too.
  let wl = lines(wordlist).toSeq().filterIt(
    not(it.startsWith("#")) and it != ""
  ).distribute(threads)

  # If `url` does not already end with a forward slash, add one.
  let u =
    if url.endsWith("/"): url
    else: url & "/"

  # Spawn the number of threads we want.
  for x in 1..threads:
    spawn bust(u, wl[x-1])
  
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