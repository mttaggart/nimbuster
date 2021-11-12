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
# github.com/c-blake/cligen
import cligen

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
            # `get()` raises a `ValueError` if it can't find the response code.
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

proc main(
  url, wordlist: string,
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
        quit "Could not automatically detect CPU cores." &
          "Please use the `--threads` flag.", -1
        # This will raise an exception if whatever you're running this on only
        # has two threads, but I can't imagine you'd ever be doing that...
      # Thanks to our custom type, Cligen also won't allow you to use a number
      # less than two as a custom argument, so that isn't a problem.
      else:
        t
  ),
  # Let the user define their own list of valid HTTP response codes, limiting
  # the minimum and maximum values using another custom type.
  #
  # (Why not just use `HttpCode` for the type of the seq? See `HttpCodeRange`'s
  # comments in the 'types.nim' submodule for information.)
  #
  # We also have to type-cast the first default value to the `HttpCodeRange`
  # type, but just one is enough for the Nim compiler to figure out the rest.
  # Cligen will do the rest of the work for us, including restricting the range
  # and type casting the arguments into the correct type.
  codes: seq[HttpCodeRange] =
    @[HttpCodeRange(200), 301, 302]
) =
  # This is the entrypoint for the program.
  # 
  # `url` is the domain name to bust.
  # 
  # `wordlist` is the path to the text file containing the list of words
  # you want to search for.
  # 
  # `threads` is the number of threads you want to use. It defaults to half of
  # the maximum number of threads available on your machine. Here we use our
  # custom `ThreadCount` type implemented in the 'types.nim' submodule to
  # enforce a value of at least two.
  
  # `countProcessors()` returns the total number of cores/threads on the CPU.
  let max_threads = countProcessors()

  if threads > max_threads:
    # Prevent the `threads` argument from being greater than the number of
    # available threads on the machine.
    quit fmt"Your machine has a maximum of {max_threads} threads.", -1
  # At this point, thanks to these two checks as well as our custom type,
  # it's guaranteed that the value of `threads` will be somewhere in the range
  # of `2..countProcessors()` inclusive.

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

  # Let's shadow an argument one more time, this time turning our seq of
  # `HttpCodeRange`s into a seq of proper `HttpCode`s using `mapIt()`.
  # You've already seen `filterIt()`, and this is exactly the same idea. It will
  # return a new value for each item after performing the expression you pass in
  # on the original value, which in this case is a simple type conversion.
  let codes = codes.mapIt(HttpCode(it))

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
  var status = newSeq[bool](threads - 1)

  # Since we're using the terminal to display a progress bar, let's just write
  # all of our successful requests to a file instead. The `fmWrite` file mode
  # will clear the file every time Nimbuster is run, so be aware of that.
  #
  # In the future, I'd suggest building your own terminal UI using Illwill
  # (https://github.com/johnnovak/illwill) so that you can have both a progress
  # bar as well as realtime readouts of information while Nimbuster is running.
  var file = open("result.txt", fmWrite)

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
      # If every item in `status` is `true`, exit the `while` loop.
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

# The `dispatch()` proc from cligen takes any proc as input and automagically
# turns it into a complete CLI. We also pass in some help text to make things
# a little more user-friendly.
dispatch(main,
  help = {
    "url": "The URL to scan.",
    "wordlist": "The file containing the list of words to search for.",
    "threads": "The number of threads to use. (Range 2..MaxThreads)",
    "codes": "The HTTP response codes to check for. (Range 100..511)"
  }
)