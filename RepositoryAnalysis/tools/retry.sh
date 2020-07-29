#!/bin/bash

# Database to update
RAF='http://iris.tor.c7a.ca:5984/repoanalysisf'
RA='http://iris.tor.c7a.ca:5984/repoanalysis'

# Loop through all approved document AIPs
curl -s -X GET "$RAF/_design/ra/_view/stats?reduce=false&include_docs=false&startkey=\[\"Well-Formed%2C%20but%20not%20valid\",\"XML\"\]&endkey=\[\"Well-Formed%2C%20but%20not%20valid\",\"XML\",\{\}\]"  |

# Convert "curl" output into simple AIP list
  grep '^{"id' | sed -e 's/^.*"id":"\([^"\/]*\).*$/\1/' | sort -u |

#cat <<AIPLIST |
#oop.proc_CDC_1203_1
#AIPLIST



# cat
   xargs -n1 -iAIPID curl -d '{"jhovesummary": {} }' -X POST "$RA/_design/ra/_update/create_or_update/AIPID"

