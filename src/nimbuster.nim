# Usage:
# nimbuster -u --url http://something -w --wordlist wordlist.txt
import std/[
    parseopt, 
    strformat, 
    httpclient,
    threadpool,
    cpuinfo,
    strutils,
    sequtils,
]
import cligen

proc request(url: string, words: seq[string]) {.thread.} =
    let status_codes: seq[HttpCode] = @[Http200,Http301,Http302,Http307,Http308,Http401,Http403,Http405]
    let client: HttpClient = newHttpClient()
    
    for w in words:
        let status_code = client.get(&"{url}/{w}").code()
        if status_code in status_codes:
            echo &"\n{status_code}: {w}"

proc main(url, wordlist: string, threads: Natural = countProcessors())  =

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

dispatch(
    main,
    help = {
        "url": "The URL to scan",
        "wordlist": "File containing words to test",
        "threads": "CPU threads (more is faster)"
    }
)