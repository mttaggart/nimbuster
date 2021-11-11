# Usage:
# nimbuster -u --url http://something -w --wordlist wordlist.txt
import std/parseopt, strformat, httpclient, asyncdispatch
import strutils


proc usage(): void =
    echo "Usage: "
    echo "nimbuster -u[--url]:URL -w[--wordlist]:WORDLIST -s[--status-codes]:200,301"

# Parse command line URL
# Parse command line wordlist
proc parse_args: (string, string, seq[string]) = 
    result = ("","", @["200","301","302","307","308","401","403","405"])
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
            if p.key == "s" or p.key == "status-codes":
                result[2] = p.val.split(",")
        of cmdArgument:
            continue

proc request(url: string, word: string, status_codes: seq[string]): Future[string] {.async.} = 
    let client: AsyncHttpClient = newAsyncHttpClient()
    var r = await client.get(&"{url}/{word}")
    let status_code = r.status.substr(0,2)
    result = status_code
    if status_code in status_codes:
        echo &"\n{status_code}: {word}"

proc main()  =
    let (url, wordlist, status_codes) = parse_args()
    if url == "" or wordlist == "":
        usage()
        return
    
    # Get the wordlist

    let f: File = open(wordlist, fmRead)
    let words: seq[string] = readAll(f).split("\n")
    for i in 0..words.len - 1:
        write(stdout, &"\r{i + 1}/{words.len}")
        let word: string = words[i]
        let res = waitFor request(url, word, status_codes)
        # echo res

when isMainModule:
    main()

# Options???

# Make HTTP Request

# If 200/301/302, list it
