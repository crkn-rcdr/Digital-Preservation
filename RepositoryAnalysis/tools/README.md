# Some notes on how these tools work.


* clearsum

Clears md5summary, summary, and/or metadatasummary fields, to force other tools to re-process those AIPs.

* dupmd5

Detect duplicate MD5's and determine if they have different file sizes.  Does not update database, and is used to determine how unique the MD5's are within our repository.

* revisionswalk

Walks through AIPs and tries to determine how many revision files are globally unique.

* walkjhove

```
$ docker-compose build ; docker-compose run ratools walkjhove
```

This will generate JHOVE reports, and put summary informtion in the per-AIP document in <i>repoanalysis</i> and per-file information in <i>repoanalysisf</i>.  This should be run regularly whenever new SIPs have been added to the repository.

* walkmd5

Walk AIPs and sets 'md5summary' field.

* walkmetadata

Processes changelog.txt file to set 'metadatasummary' field.
