# Usage:
# nimbuster -u --url http://something -w --wordlist wordlist.txt
import std/[
    strformat, 
    httpclient,
    threadpool,
    cpuinfo,
    strutils,
    sequtils,
]
import cligen, cligen/argcvt
import termstyle

# Define Types
type ThreadResponse = tuple[code: HttpCode, word: string, done: bool]

proc request(url: string, words: seq[string], channel: ptr Channel[ThreadResponse]) =
    let client: HttpClient = newHttpClient()
    
    for i, w in words:
        let status_code = client.get(&"{url}/{w}").code()
        let done = i == words.len - 1
        channel[].send((status_code, w, done))

proc main(
    url, wordlist: string, 
    threads: Natural = (
        block:
            let t = countProcessors() div 2
            if t == 0:
                quit "Couldn't detect CPU cores.\nPlease use the --threads flag.", -1
            else:
                t
    ),
    codes: seq[HttpCode] = @[Http200, Http301, Http302]
)  = 

    let max_threads = countProcessors()

    # Quit if threads not countable
    if threads > max_threads:
        quit fmt"Your machine has a max of {max_threads} threads.", -1
    
    # Assign actual number of threads
    var numThreads: int = threads - 1

    # Initialize wordCount value
    var wordCount: int

    # Get the wordlist
    # Divide it amongst the threads
    let words: seq[seq[string]] = block:
        let ws =
            # `lines()` is not a proc, it's an iterator. Learn more:
            #   https://nim-lang.org/docs/manual.html#iterators-and-the-for-statement
            # What this means for us right now is that it doesn't return a
            # `seq[string]` like we want. `toSeq()` is the solution.
            lines(wordlist)
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
            .toSeq()
            # Business as normal from here on out...
            .filterIt(
                not(it.startsWith("#")) and it != ""
            )
        wordCount = ws.len
        # Account for edge case where wordlist is smaller than threads
        if numThreads > wordCount:
            numThreads = wordCount
        ws.distribute(numThreads)
     
    var complete: int = 0

    # Build out some channels
    var channels = newSeq[Channel[ThreadResponse]](numThreads)

    # Open channels
    for i, _ in channels:
        open(channels[i])

    # Spawn threads w/ channels
    for t in 0..<numThreads:
        spawn request(url, words[t], channels[t].addr)

    # Track all the statuses (stati?)
    var status = newSeq[bool](numThreads)
    var completeStatus = 0
    # Startup info

    echo green("[+] Starting enumeration...")
    echo green(&"[+] URL: {url}")
    echo green(&"[+] Wordlist: {wordlist}")
    echo green(&"[+] Threads: {numThreads}")
    # Main Loop
    while true:
        for i in 0..<numThreads:
            let r = channels[i].tryRecv()

            # Write out results
            if r.dataAvailable:
                complete += 1

                # Check complete percentage
                let completePct = ((complete / wordCount) * 100).toInt
                
                # Check for previously unknown complete status
                if completeStatus != completePct:
                    # Update status
                    completeStatus = completePct
                    # Print out every 10%
                    if completePct mod 10 == 0 and completePct > 0:
                        echo yellow(&"[+] Status: {completePct}% complete")

                if r.msg.code in codes:
                    echo cyan(&"[!] {r.msg.code}: /{r.msg.word}")

            
                # Update status
                status[i] = r.msg.done
        
        # Check if we're all done...literally
        if status.allIt(it):
            break
    
    for i, _ in channels:
        close(channels[i])

    echo green "Bustin' Accomplished"


# Helper procs for cligen
proc argParse(
    dst: var seq[HttpCode],
    dfl: seq[HttpCode],
    a: var ArgcvtParams
): bool =

    # Split command line codes
    var codes = a.val.split(",").mapIt(
        toSeq(it).filterIt(
            it in '0'..'9'
        ).join()
    ).filterIt(
        it != ""
    ).deduplicate().mapIt(
        parseInt(it).HttpCode
    )

    if codes.len == 0:
        echo &"Bad value: \"{a.val}\" for option \"{a.key}\""
        return false

    for c in codes:
        if c.int notin 100..511:
            echo &"Bad value: \"{c}\" for option \"{a.key}; invalid HTTP Code\"" 
            return false
    dst = codes

    return true

proc argHelp(dfl: seq[HttpCode], a: var ArgcvtParams): seq[string] =
    @[
        a.argKeys,
        &"2..{countProcessors()}",
        $dfl
    ]

dispatch(
    main,
    help = {
        "url": "The URL to scan",
        "wordlist": "File containing words to test",
        "threads": "CPU threads (more is faster)",
        "codes": "A list of HTTP response codes to report on."
    }
)