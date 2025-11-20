#!/bin/sh
if [ $# -ne 2 ]; then
    exit 1
fi

filesdir="$1"
searchstr="$2"

if [ ! -d "$filesdir" ]; then
    echo "Error: '$filesdir' is not a valid directory."
    exit 1
fi

filescount=$(find "$filesdir" -type f | wc -l)
matchcount=$(grep -r "$searchstr" "$filesdir" 2>/dev/null | wc -l)
echo "The number of files are $filescount and the number of matching lines are $matchcount"
exit 0