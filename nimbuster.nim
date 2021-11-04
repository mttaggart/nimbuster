# Usage:
# nimbuster -u --url http://something -w --wordlist wordlist.txt
import std/parseopt
import std/strformat
var p = initOptParser()

proc usage(): void =
    echo "Usage: nimbuster -u[--url]:URL -w[--wordlist]:WORDLIST"


# Parse command line URL
# Parse command line wordlist
proc parse_args: (string, string) = 
    result = ("","")
    while true:
        p.next()
        case p.kind 
        of cmdEnd: break
        of cmdShortOption, cmdLongOption:
            if p.key == "u" or p.key == "url":
                result[0] = p.val
            if p.key == "w" or p.key == "wordlist":
                result[1] = p.val
        of cmdArgument:
            continue

proc main(): void =
    let (url, wordlist) = parse_args()
    if url == "" or wordlist == "":
        usage()
        return
    echo &"URL: {url}, Wordlist: {wordlist}"

when isMainModule:
    main()

# Options???

# Make HTTP Request

# If 200/301/302, list it
