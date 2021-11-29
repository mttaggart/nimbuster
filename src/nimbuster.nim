import std/[
  sequtils, # Operations on seqs.
  strutils, # Operations on strings.
  threadpool, # Used to `spawn` multiple threads.
  cpuinfo, # Provides one proc used to get the number of CPU cores/threads.
  strformat, # Provides a macro for making strings work like Python F-Strings.
  httpclient, # Provides objects and procs for requesting data from servers.
]

# We've put some stuff in its own file, so let's import that. Please refer to
# that file for more information.
import nimbuster/[types]

# Uses macro magic to turn procs into complete, advanced CLIs.
# https://github.com/c-blake/cligen
# We also import the `cligen/argcvt` submodule because we'll need it later.
import cligen, cligen/argcvt

# A library that prints a handy little progress bar on the screen.
# https://github.com/euantorano/progress.nim
import progress

# Exit gracefully on Ctrl-C, instead of writing an ugly stack trace to the
# terminal any time we want to abort early.
setControlCHook(
  proc() {.noconv.} =
    quit "\nAborted.", 1
)

proc bust(url: string, wl: seq[string], channel: ptr Channel[ThreadResponse]) =
  # We don't actually need to use the `{.thread.}` pragma here, I was mistaken.
  # You only need to use that pragma when using `createThread()`, which we
  # aren't doing since we're using threadpool instead.

  # This proc performs the actual busting. We put it in its own proc so that
  # we can call it in parallel.
  #
  # `url` is the URL to the domain we're busting. It's guaranteed to end in a
  # forward slash, as we make sure of that in our main thread. However, we
  # currently do not perform any other validation on the input, so this can
  # cause an exception if `url` is not actually a valid URL.
  #
  # `wl` is the chunk of the wordlist dedicated to this particular thread.
  #
  # `channel` is a pointer to a `Channel[ThreadResponse]`. We create one channel
  # for each thread, and give each thread a pointer to one of the channels.
  # Where does `ThreadResponse` come from? I've implemented it in a submodule
  # located in './src/package/types.nim' and you can read all about it there.

  var client = newHttpClient()
  for i, w in wl:
    # The `[]` operator dereferences the pointer. The reason for the unusual
    # symbol is because Nim implicitly dereferences pointers when indexing into
    # them (`[x]`) or when accessing their fields (`x.field`). So, as a logical
    # consequence of this, `[]` with no index is the deferencing operator for
    # types that do not have indices or fields.
    channel[].send(
      (
        # In the original implementation, the status code was obtained with
        # `r.status.substr(0,2)`, which just returns a string. A slightly better
        # way of doing it would be to use `code()` from `std/httpclient` which
        # not only returns the response code in the form of the `HttpCode` type,
        # but also raises an exception if it's missing.
        #
        # This expression will make the HTTP GET request and return its response
        # code in the form of the `HttpCode` type.
        (
          try:
            # `code()` raises a `ValueError` if it can't find the response code.
            # Let's handle that exception just in case.
            client.get(url & w).code()
          except ValueError:
            # For now, I'm just ignoring the exception and continuing through
            # the list.
            continue
        ),
        # This is the word that we just made a request for.
        w,
        # This expression will return `true` when we're operating on the last
        # item in the wordlist, because immediately afterwards the thread will
        # end execution and we can mark it as being done.
        i == wl.len - 1
      )
    )

proc nimbuster(
  # The URL target and the path to the file we're using for our wordlist.
  url, wordlist: string,

  # The number of threads we want to use.
  threads: ThreadCount = (
    block:
      # This syntax is perhaps slightly confusing, so let's break down what's
      # going on here:
      #
      # `block` is a keyword that lets you write what can be thought of as a
      # sort of "multi-line expression." We can write whatever code we want
      # inside a block, and lone values are implicitly "returned." You can think
      # of the code I'm using as effectively the same thing as this:
      #[
        proc getThreads(): int =
          let t = countProcessors() div 2
          if t == 0:
            quit "Could not...", -1
          else:
            return t
        
        proc main(..., threads: ThreadCount = getThreads()) =
          ...
      ]#
      # The difference with `block` is that we don't have to define a proc just
      # to evaluate this one value. We can do it in the assignment itself.
      # Another syntactic difference is that you don't use the `return` keyword
      # inside of `block`s. Instead, when any value (literal, variable,
      # expression) is written but not discarded or used, the `block` will end
      # execution and result in whatever that value is. In this case, when `t`
      # is not zero, the entire `block` will evaluate to the value of `t`. It's
      # effectively the same thing as `return`, but without the actual keyword.

      # Using every thread is a little agressive... Let's just use half of them
      # by default. While `/` returns a float, `div` returns an int, so we use
      # `div` here. It would be weird to have half a thread.
      let t = countProcessors() div 2
      if t == 0:
        # `countProcessors()` returns 0 if it couldn't detect the number of
        # cores/threads. Handle this just in case.
        #
        # I use the string concatenation operator (`&`) here just to avoid going
        # over 80 characters per line. This is not enforced and I don't think
        # anyone will care if you go a little over, but I'm doing it here for
        # the sake of posterity.
        quit "Could not automatically detect CPU cores. " &
          "Please use the `--threads` flag.", -1
        # This will raise an exception if whatever you're running this on only
        # has two threads, but I can't imagine you'd ever be doing that...
      # Thanks to our custom type, Cligen also won't allow you to use a number
      # less than two as a custom argument, so that isn't a problem.
      else:
        t
  ),

  # Let the user define their own list of valid HTTP response codes. Cligen
  # by itself doesn't know what to do with the `seq[HttpCode]` type, so later
  # we'll write some code to help it out later.
  codes: seq[HttpCode] =
    @[Http200, Http301, Http302]
) =
  ## A directory brute-forcer written in Nim. Because we needed another one.
  # Cligen is clever and it will extract the above doc-comment (`##`) out of our
  # code and use it in the '--help' text.

  # This is the main entrypoint for the program.
  # 
  # `url` is the domain name to bust.
  # `wordlist` is the path to the text file containing the list of words
  # you want to search for.
  # `threads` is the number of threads you want to use. It defaults to half of
  # the maximum number of threads available on your machine. Here we use our
  # custom `ThreadCount` type implemented in the 'types.nim' submodule to
  # enforce a value of at least two.
  
  # `countProcessors()` returns the total number of cores/threads on the CPU.
  let max_threads = countProcessors()

  if threads > max_threads:
    # Prevent the `threads` argument from being greater than the number of
    # available threads on the machine. The message I use here is formatted to
    # be similar to the messages that Cligen creates on its own, so that things
    # seem somewhat consistent.
    #
    # Here we use the `&` macro from `std/strformat`. The reason why we use this
    # instead of `fmt` is because `fmt` will ignore escape sequences. (ex. '\"'
    # will evaluate to '\"', not '"'.) `&` does the same thing as `fmt` while
    # working with escape sequences.
    quit &"Bad value: \"{threads}\" for option \"threads\"" &
      "; out of range for 2.." & $max_threads, -1
  # At this point, thanks to these two checks as well as our custom type,
  # it's guaranteed that the value of `threads` will be somewhere in the range
  # of `2..countProcessors()` inclusive.

  # Let's tell the user what's going on. I'm formatting this in a very simple
  # way, so feel free to do something more elegant if you want.
  echo [
      "        URL: " & url,
      "   Wordlist: " & wordlist,
      "    Threads: " & $threads,
      " HTTP Codes: " & "[" & codes.mapIt($(it.int)).join(", ") & "]",
      "     Output: results.txt"
    ].join("\n")

  # Split the contents of the `wordlist` file into equal-sized chunks, the
  # number of chunks being equal to the number of threads minus one. (Remember,
  # we have to dedicate the main thread to displaying info in the terminal.)
  #
  # We can also filter out any lines that we don't want, such as empty lines or
  # comments, using the magical `filterIt()` template to pass in a simple
  # expression as our filter. Any items that cause the expression to return
  # `false` will not be included in the final result.
  #
  # `lines()` is an iterator that takes a filename (or a `File` object) as
  # input. Normally you would use it in a `for` loop, but in this case we just
  # want to turn it into a seq.
  #
  # The `toSeq()` template turns anything that can be iterated over into a seq.
  # (ex. `toSeq("ABC") == @['A', 'B', 'C']`)
  #
  # We also keep track of how long the wordlist is, as we'll need it later for
  # our progress bar.
  var wordcount: int
  # Nim lets us do something called 'shadowing'. We aren't allowed to write to
  # wordlist directly since it's an immutable argument, but we can create a new
  # variable with the same name. Every reference to `wordlist` after this point
  # will be referencing this new variable instead of the original argument.
  let wordlist = block:
    # We're using another `block` here, this time to get the length of the
    # wordlist while we're loading and assigning it. The alternative would be
    # creating a junk temporary variable to store the wordlist before we
    # `distribute()` it, but we don't need to do that since we can do this.
    #
    # `lines()` is not a proc, it's an iterator. Learn more:
    #   https://nim-lang.org/docs/manual.html#iterators-and-the-for-statement
    # What this means for us right now is that it doesn't return a
    # `seq[string]` like we want. `toSeq()` is the solution.
    #
    # `toSeq()` takes any expression that can be iterated over (any
    # data that is itself a collection of other data) and turns it into
    # a seq. It's a little hard to explain succinctly, but essentially:
    #[
      lines(wordlist).toSeq()
    ]#
    # becomes:
    #[
      var result = newSeq[string]()
      for x in lines(wordlist):
        result.add(x)
    ]#
    # wherein `result` is the return value of the expression. The end
    # result is that we have a `seq[string]` wherein each item is a line
    # from the file `wordlist`, and we don't have to worry about opening
    # or closing the file ourselves; it's handled for us.
    let r = lines(wordlist).toSeq().filterIt(
      not(it.startsWith("#")) and it != ""
    )
    # Get the length of the wordlist and assign it to `wordcount`.
    wordcount = r.len
    # Finally, distribute the wordlist and assign it to `wordlist`.
    r.distribute(threads - 1)

  # If `url` does not already end with a forward slash, add one.
  # `std/os` implements a `/` proc that does something similar, but it will
  # use a backslash on Windows as it's intended for directories, not URLs.
  # Therefore, we just do it ourselves instead. There are a million other ways
  # of doing effectively the same thing too, and it doesn't really matter which
  # method you use. We just need to be sure it ends in a foward slash.
  #
  # (There is https://nim-lang.org/docs/uri.html, but it's a little overkill for
  # something this simple.)
  #
  # We also shadow the argument again, just like we did with `wordlist`.
  let url =
    if url.endsWith("/"): url
    else: url & "/"

  # Let's create a seq of `Channel[ThreadResponse]` that's of length `threads`
  # minus one. Remember, we may have X threads, but we need our main thread
  # to do its own thing, so we have to subtract one.
  var channels = newSeq[Channel[ThreadResponse]](threads - 1)
  for i, _ in channels:
    # Let's open each of the channels as well.
    open(channels[i])

  # Spawn the number of threads we want using a `for` loop.
  # The normal `x..y` range constructor includes the upper value in the range.
  #
  # You can use `x..<y` to make it behave more like Python, where the upper
  # value is not included in the range. `0..<threads(-1)` and `0..(threads-2)`
  # are effectively the exact same thing, so you can use whichever you prefer.
  # Here I'm just demonstrating that the `..<` range contstructor exists.
  #
  # We also pass in a pointer to each channel in the `channels` seq. `x.addr`
  # returns a pointer to `x`.
  for i in 0..<(threads - 1):
    spawn bust(url, wordlist[i], channels[i].addr)

  # We'll use this seq to keep track of which threads are finished executing.
  #
  # This is not necessarily the best way of keeping track of threads, it's just
  # one way you can go about it that happens to work well here. (Take a look at
  # `std/threadpool` to get an idea of how else you might accomplish this,
  # namely `FlowVar[T]` and `isReady()`.) This method is simply how I chose to
  # do it, partially because it's fairly easy to grasp. I also suspect that,
  # with this particular workload and configuration, this method may have
  # slightly less overhead compared to using `FlowVar[T]` and `isReady()`, but
  # that's just a theory, so take that with a grain of salt. In any case, this
  # particular method works perfectly for our purposes.
  var status = newSeq[bool](threads - 1)

  # Since we're using the terminal to display a progress bar, let's just write
  # all of our successful requests to a file instead. The `fmWrite` file mode
  # will clear the file every time Nimbuster is run, so be aware of that.
  #
  # In the future, I'd suggest building your own terminal UI using Illwill
  # (https://github.com/johnnovak/illwill) so that you can have both a progress
  # bar as well as realtime readouts of information while Nimbuster is running.
  var file = open("results.txt", fmWrite)

  # Let's create our progress bar. We need to set the total to be equal to the
  # number of words in our wordlist, as that's how we actually know how far we
  # are through the list.
  var bar = newProgressBar(total = wordcount)
  # Go ahead and start the progress bar, too.
  bar.start()

  # Here's our main loop.
  while true:
    # Loop over each of our threads using a simple index.
    for i in 0..<(threads - 1):
      # `tryRecv()` will to and receive a message from a given channel. If there
      # wasn't one available, `x.dataAvailable` will be false. Keep in mind that
      # if there is a message available, it will be pulled off the stack, so
      # we'd better do something with it before it's lost forever.
      let r = channels[i].tryRecv()
      # Check if a message was received...
      if r.dataAvailable:
        # And if the response code was one of these options...
        if r.msg.code in codes:
          # Write it to the file we opened earlier.
          file.writeLine($r.msg.code, ": ", url & r.msg.word)
          # Let's also go ahead and flush the contents of the file, so that you
          # can see the contents of the file updated in realtime.
          flushFile(file)
        # Since we received a message, we know we're one index closer to
        # finishing the wordlist. So, let's increment the progress bar by one.
        bar.increment()
        # Let's also keep track of the thread's `done` state, so that we can
        # exit the loop if they're all done.
        status[i] = r.msg.done
    
    # If `filterIt()` and `mapIt()` weren't enough already, here's `allIt()`,
    # which returns `true` if any every item in `x` returns `true` when passed
    # into the expression. In this case, we just want to know if every item
    # in `status` is `true`.
    #
    # (There are a few other 'it'-style templates available, too.)
    if status.allIt(it):
      # If every item in `status` is `true` (meaning that every thread has
      # finished executing), exit the `while` loop.
      break

  # We don't need to worry about `sync()` or anything like that because we can
  # be sure that we've only exited the loop if every thread finished execution.
  
  # Now that we're out of the loop, we can close the file since we don't need it
  # any more after this.
  file.close()
  # We're done with the progress bar, too.
  bar.finish()

  for i, _ in channels:
    # Finally, let's close all the channels.
    close(channels[i])
  
  # Tell the user that we're done.
  echo "Finished."

# Cligen by itself doesn't know what to do with the `seq[HttpCode]` type, so
# let's teach it! We don't have to pass this proc into `dispatch()`; Cligen will
# automatically pick it up so long as they're both defined in the same scope.
#
# This `argParse()` proc is what Cligen will use to turn the user's input (as a
# string) and turn it into a proper `seq[HttpCode]`.
#
# `dst` is what we'll assign to in order to pass our parsed input into our
# program's entrypoint.
# `dfl` is the default value of the argument as we defined in our proc's
# signature. This is provided so that, for example, you can append to the
# default argument instead of replacing it outright. I'm not doing this here,
# though; I just want to replace it.
# `a` is an `ArgcvtParams` object that contains everything you could possibly
# want to know about the argument being passed in. For our purpose, the only
# thing we need is `a.val`, which is the string representation of what the user
# has passed in.
# We also return a boolean value to tell Cligen whether if our parsing was
# successful or not. If we return `false`, Cligen will abort for us.
proc argParse(
  dst: var seq[HttpCode],
  dfl: seq[HttpCode],
  a: var ArgcvtParams
): bool =
  # This expression basically splits the input by commas, removes any characters
  # that aren't numbers, discards any empty leftover strings, then parses each
  # string into an integer before type casting it into an `HttpCode`. The reason
  # I decided to do it this way is so that the input is extremely flexible, the
  # only real requirements being that the input contains numbers and that each
  # value is separated by a comma.
  var codes = a.val.split(",").mapIt(
    toSeq(it).filterIt(
      it in '0'..'9'
    ).join()
  ).filterIt(
    it != ""
  ).deduplicate().mapIt(
    parseInt(it).HttpCode
  )
  # We do need to make sure that the input contains something usable, so an easy
  # way of doing that is simply to check if the length of the seq is zero.
  # Because of how we parsed the input, it will always be empty if there weren't
  # any numbers. Echo an error message if it's empty, and return false to tell
  # Cligen that something went wrong. The message is styled after the messages
  # that Cligen generates on its own.
  if codes.len == 0:
    echo &"Bad value: \"{a.val}\" for option \"{a.key}\"; invalid input"
    return false
  # Finally, we just need to validate that all of the inputs are valid HTTP
  # codes. We can just loop over each of them and check if it's within a certain
  # range, and if one is not, we echo an error message and tell Cligen. Once
  # again, we try to imitate Cligen's message style.
  for x in codes:
    if x.int notin 100..511:
      echo &"Bad value: \"{x}\" for option \"{a.key}\"; out of range for 100..511"
      return false
  # By this point, we're gauranteed to have a `seq[HttpCode]` that contains at
  # least one usable value. Let's send it to our entrypoint and tell Cligen that
  # everything is okay.
  dst = codes
  return true

# This proc is used by Cligen to display relevant information in the '--help'
# message. The first return value is just the flags that this command uses
# ('-c, --codes'). The second return value is the type of the input, which of
# course is going to be a `seq[HttpCode]`, shortened to 'HttpCodes'. The final
# return value is a a string representing the default value of this argument.
# Here I've written it as an expression that turns the default argument into a
# list of comma-separated numbers in brackets. The `$` (string conversion)
# operator for the `HttpCode` type will include the code's meaning at the end
# (ex. "200 OK"), but I want to display only the number, so I use this
# expression to display it the way that I want.
proc argHelp(dfl: seq[HttpCode], a: var ArgcvtParams): seq[string]=
  @[
    a.argKeys,
    "100..511",
    "[" & dfl.mapIt($(it.int)).join(", ") & "]"
  ]

# While we're at it, I dislike how Cligen displays our `ThreadRange` type by
# default... Let's override it so it can look a little nicer.
proc argHelp(dfl: ThreadCount, a: var ArgcvtParams): seq[string]=
  @[
    a.argKeys,
    # In './src/nimbuster/types.nim', I mention that `countProcessors()` is only
    # available at runtime due to relying on the FFI. Lucky for us, this code
    # is executed at runtime, so we can use `countProcessors()` here for our
    # help text.
    "2.." & $countProcessors(),
    $dfl
  ]

# The `dispatch()` proc from cligen takes any proc as input and automagically
# turns it into a complete CLI. We also pass in some help text to make things
# a little more user-friendly.
dispatch(nimbuster,
  help = {
    "url": "The URL to scan.",
    "wordlist": "The file containing the list of words to search for.",
    "threads": "The number of threads to use.",
    "codes": "A list of HTTP response codes to check for."
  }
)

# I'm sure Cligen has some more fancy tricks that I could be taking advantage
# of, but I'm happy enough with it to leave it as-is. More fun for you :)