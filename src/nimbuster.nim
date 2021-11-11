# Usage:
# nimbuster -u --url http://something -w --wordlist wordlist.txt
import std/[
    parseopt, 
    strformat, 
    httpclient,
    threadpool,
    cpuinfo,
    strutils,
    sequtils 
]

proc usage(): void =
    echo "Usage: "
    echo "nimbuster -u[--url]:URL -w[--wordlist]:WORDLIST -s[--status-codes]:200,301"

# Parse command line URL
# Parse command line wordlist
proc parse_args: (string, string, int) = 
    # url, wordlist, threads
    result = ("","",1)
    var p = initOptParser()
    while true:
        p.next()
        case p.kind 
        of cmdEnd: break
        of cmdShortOption, cmdLongOption:
            if p.key == "u" or p.key == "url":
                result[0] = p.val
            if p.key == "w" or p.key == "wordlist":
                result[1] = p.val
            if p.key == "t" or p.key == "threads":
                result[2] = parseInt(p.val)
        of cmdArgument:
            continue

proc request(url: string, words: seq[string]) {.thread.} =
    let status_codes: seq[HttpCode] = @[Http200,Http301,Http302,Http307,Http308,Http401,Http403,Http405]
    let client: HttpClient = newHttpClient()
    
    for w in words:
        echo &"\r{w}"
        let status_code = client.get(&"{url}/{w}").code()
        if status_code in status_codes:
            echo &"\n{status_code}: {w}"

proc main()  =
    let args = parse_args()
    let
        url: string = args[0]
        wordlist: string = args[1]
        threads: int = args[2]

    # Exit if url or wordlist not set
    if url == "" or wordlist == "":
        usage()
        return

    let max_threads = countProcessors()

    # Quit if threads not countable
    if max_threads == 0 and threads <= 0:
        quit "Could not automatically detect CPU Cores; use --threads", -1
    elif threads > max_threads:
        quit fmt"Your machine has a max of {max_threads} threads.", -1

    
    
    # Get the wordlist
    # Divide it amongst the threads
    let f: File = open(wordlist)
    let words: seq[seq[string]] = readAll(f)
        .splitLines()
        .filterIt(
            not(it.startsWith("#")) and it != ""
        ).distribute(threads)
    f.close()
    
    for t in 1..threads - 1:
        spawn request(url, words[t])

    request(url, words[0])

    sync()

when isMainModule:
    main()

# Options???

# Make HTTP Request

# If 200/301/302, list it
