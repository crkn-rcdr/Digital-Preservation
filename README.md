# CRKN Trustworthy Digital Repository

CRKN is certified as a Trustworthy Digital Repository (TDR), a reliable and integrated digital preservation system in which deposited content can be identified, collected, managed, and kept secure over time. The TDR provides a permanent capability to preserve the documentary heritage digitized through CRKN projects, as well as content already digitized or born-digital, and content received from members, partners, and stakeholders.

## System Overview

| Component              | Function                                      | Host                                 |
| ---------------------- | --------------------------------------------- | ------------------------------------ |
| **Sapindale**          | Web admin interface that manages and validates AIPs prior to ingest | Trepat         |
| **CIHM‑WIP**           | WIP packaging utilities that prepares and stages AIPs before ingest | Trepat         |
| **Swift**              | Canonical object storage for all AIPs         | Trepat                               |
| **ZFS Pool**           | Local disk‑based preservation storage         | Orchis / Romano                      |
| **CouchDB (`tdrepo`)** | System of record for all repositories         | Trepat / Orchis / Romano (clustered) |
| **reposync**           | Synchronizes metadata to wipmeta / dipstaging | Trepat                               |
| **replicationwork**    | Builds replication queues                     | Orchis / Romano                      |
| **swiftreplicate**     | Executes replication from swift to ZFS        | Orchis / Romano                      |
| **repomanage**         | Verifies TDR data                             | Trepat / Orchis / Romano             |
| **Logging**            | Replication and verification logs             | Trepat / Orchis / Romano             |

Notes:
* Swift serves as the **authoritative preservation copy** source of truth for the AIP file data.
* Replication ensures multiple, geographically distributed copies.
* Verification maintains fixity and integrity across systems.
* CouchDB metadata enables full auditability; the system treats **CouchDB metadata as authoritative**.
  
---

# How an AIP Moves from WIP → Swift → Orchis & Romano

The full lifecycle of an Archival Information Package (AIP) as it travels through CRKN's Trusted Digital Repository (TDR) system from ingest in the WIP (Work‑In‑Progress) environment, through preservation in Swift, replication to ZFS‑based nodes (Orchis and Romano), and verification, is as follows:

## 1) AIP Capture & Back‑Staging (WIP / Sapindale)

### A. WIP Work‑In‑Progress Environment

See: https://github.com/crkn-rcdr/CIHM-WIP

The WIP (Work‑In‑Progress) system is a networked staging environment used before an AIP enters the preservation repository. It provides a workspace for digitization staff to prepare and validate content.

Key functions:

* **Storage of raw digitized content** prior to preservation.
* **Metadata enrichment and validation** before packaging.
* **Interface with administrative tools** such as *Sapindale*.

The WIP environment allows human and automated processes to ensure that each AIP meets metadata, structure, and completeness requirements prior to ingest.

### B. Sapindale

See: https://github.com/crkn-rcdr/sapindale

Sapindale is a web‑based access and metadata administration tool built using Sapper/Svelte. It interacts directly with CouchDB instances and the WIP system, providing an interface for:

* Browsing and validating packages in WIP.
* Editing descriptive and administrative metadata.
* Initiating or confirming ingest into the preservation repository.

Once content is approved and metadata verified, Sapindale and WIP tools generate valid BagIt packages that represent the finalized AIPs.

---

## 2) Ingest into the Preservation Repository (Swift)

See: https://github.com/crkn-rcdr/CIHM-TDR

Once packaging and metadata validation are complete:

1. The AIP is packaged using the CIHM‑TDR ingest tooling (e.g., Archive::BagIt, CIHM‑TDR’s Perl utilities).
2. The package is uploaded to Swift, which is hosted on our Swift Cluster, and the repository is managed via tools on Trepat.
3. CouchDB (`tdrepo`) receives a new metadata record:

```json
{
  "_id": "aeu.00002|item_repository.swift",
  "type": "item_repository",
  "owner": "aeu.00002",
  "repository": "swift",
  "pool": "swift",
  "manifest md5": "93e2e185229ae497188bc77510dd312e",
  "manifest date": "2024-05-06T17:59:52Z",
  "add date": "2024-05-06T22:55:02Z",
  "verified": true,
  "verified date": "2024-05-06T22:55:02Z"
}
```

Swift is considered the **authoritative preservation copy** for all AIPs.

The system treats **CouchDB metadata** as **authoritative**.

- File system state (ZFS pools, Swift containers) is *not* consulted.
- If CouchDB indicates an AIP is verified, the system assumes it exists even if storage is empty.

This design enables distributed operation but requires explicit metadata changes after data loss.

---

## 3) Replication to Preservation Nodes (Orchis / Romano)

### A. Replication Planning `tdr-replicationwork`

See: https://github.com/crkn-rcdr/CIHM-TDR/blob/main/bin/tdr-replicationwork

On preservation nodes (Orchis and Romano), the replication planning stage periodically runs:

```bash
tdr-replicationwork --conf /home/tdr/tdr.conf --since <date>
```

`tdr-replicationwork` is a planning and decision-making tool in the TDR (Trusted Digital Repository) replication pipeline.  
It does not copy data. Instead, it analyzes repository metadata in CouchDB to determine which AIPs require replication, from where, and to which target repositories.

The output of `tdr-replicationwork` is a populated queue of documents in CouchDB (the "replicate" view), which are later consumed by `tdr-swiftreplicate` to perform the actual file transfers.

#### Inputs Used by `tdr-replicationwork`

##### 1. `item_repository.*` Documents

For each AIP (e.g. `aeu.00002`), there may be multiple repository records:

- `item_repository.swift`
- `item_repository.orchis`
- `item_repository.romano`

These documents may include:

- `manifest md5`
- `manifest date`
- `verified`
- `verified date`
- `pool` (e.g. `cihmz2`)
- `add date`

These fields are used to determine repository completeness and freshness.

##### 2. The `--since` Parameter

Example:

```bash
tdr-replicationwork --since 2024-05-01
```

This limits processing to AIPs with repository metadata changes on or after the specified date.

Notes:
- `--since` filters on metadata timestamps, not file modification times.
- `--since all` scans the full historical dataset and may appear to hang due to volume.

#### High-Level Algorithm

For each AIP owner:

1. Gather all `item_repository.*` documents
2. Identify candidate source repositories
3. Select the most recent valid source based on:
   - Presence of `manifest md5`
   - Presence of `manifest date`
   - Newest `manifest date`
4. Compare all other repositories against the selected source
5. For each repository that is incomplete or outdated:
   - Set `replication` field in the document to a non-zero value

#### Source Selection Logic

A repository is considered a valid replication source if it has:

- A `manifest md5`
- A `manifest date`

Among valid sources, the repository with the newest `manifest date` is chosen.

In practice:
- Swift almost always wins
- Swift is treated as canonical ingest origin

#### Conditions That Trigger Replication

A repository is flagged for replication if any of the following are true:

| Condition | Outcome |
|--------|--------|
| Repository document missing | Replication required |
| `manifest md5` missing | Replication required |
| `verified` missing | Replication required |
| `manifest date` older than source | Replication required |
| Checksum mismatch | Replication required |

This behavior enables metadata-based recovery.

#### Output: Populated Documents Queue in CouchDB "replicate" view
 
When replication is needed, a document similar to the following is written:

```json
{
  "_id": "aeu.00002|item_repository.swift",
  "_rev": "15-693b78d85b78bb2e155fd9e6c2f8b001",
  "owner": "aeu.00002",
  "repository": "swift",
  "type": "item_repository",
  "document date": "2024-05-06T21:41:43Z",
  "verified date": "2025-12-07T22:58:06Z",
  "filesize": "19675032487",
  "manifest date": "2024-05-06T17:59:52Z",
  "add date": "2024-05-06T21:41:43Z",
  "manifest md5": "93e2e185229ae497188bc77510dd312e",
  "replicate": 5
}
```

`tdr-replicationwork` is a metadata-driven planner that ensures repository consistency by comparing verification state across repositories.  
It assumes CouchDB correctness by design and therefore requires deliberate metadata intervention after catastrophic storage failures.

After `tdr-replicationwork` is completed, the AIPs are filtered by the "replicate" CouchDB view, which acts as a queue for the `tdr-swiftreplicate` script:

```
function(doc) {
    if (doc.type && doc.type === "item_repository" && doc["replicate"]) {
      emit([doc.repository, doc.replicate, doc.owner], null);
    }
  }
```

### B. Replication Execution `tdr-swiftreplicate`

See: https://github.com/crkn-rcdr/CIHM-TDR/blob/main/bin/tdr-swiftreplicate

Each preservation node runs a replication loop for each item in the queue (see above) inside a Docker container:

```bash
while :; do
  tdr-swiftreplicate --fromswift --maxprocs=5 --timelimit=21600
  sleep 10m
done
```

At a high level, the algorithm is:

> **Compare metadata → download to staging folders → verify → replace local copy → update metadata**

No filesystem scanning is performed. All decisions are based on CouchDB (`tdrepo`) state.

#### Inputs

- **AIP identifier**: `<contributor>.<identifier>` (e.g., `aeu.00002`)
- **Source repository**: Swift (via `--fromswift`)
- **Target repository**: Local node (Orchis / Romano)
- **CouchDB (`tdrepo`)**: authoritative metadata store
- **Local ZFS pools**: e.g. `cihmz2`

#### Algorithm Steps

##### Step 1. Parse AIP Identifier
- Split the AIP ID into:
  - `contributor`
  - `identifier`

##### Step 2. Determine Existing Local State
- Attempt to locate an existing local copy:
  - `find_aip_pool(contributor, identifier)`
- If found:
  - Load local manifest metadata via `get_manifestinfo`
- Initialize an update document (`updatedoc`) representing local repository state
- Set:
  ```json
  "replicate": "false"
  ```
  (marks replication attempt as handled)

##### Step 3. Determine the Newest Source Copy
- Query CouchDB:
  ```perl
  get_newestaip({ keys => [aip] })
  ```
- If the query fails:
  - Log warning
  - Abort replication
- If no source is returned:
  - If local manifest is missing:
    - Set `priority = "a"`
    - Log “Can’t find source”
  - Update CouchDB
  - Abort replication

##### Step 4. Validate Replication Topology
- Extract list of repositories that should contain the AIP
- Confirm the current repository (e.g., Orchis) is included
- If not included:
  - Update CouchDB
  - Abort replication

##### Step 5. Fetch Source AIP Metadata
- Retrieve authoritative AIP metadata from the source repository
- If unavailable:
  - Log error
  - Abort replication

##### Step 6. Short-Circuit if Already Up-to-Date
- If both source and local copies have `manifest md5`
- AND the checksums match:
  - Update CouchDB
  - Abort replication (no-op)

##### Step 7. Select or Create Incoming Staging Path
- Attempt to reuse an existing incoming path:
  - `find_incoming_pool(contributor, identifier)`
- Otherwise:
  - Select a pool with free space
  - Create:
    ```
    incoming_basepath(pool)/<aip>
    ```

This staging area isolates incomplete downloads from live repository paths.

##### Step 8. Download Bag from Swift (Retry Logic)
- Attempt download up to 3 times:
  ```perl
  bag_download(aip, incomingpath)
  ```
- If all attempts fail:
  - Update CouchDB
  - Abort replication

##### Step 9. Verify BagIt Package
- Instantiate BagIt verifier:
  ```perl
  Archive::BagIt::Fast(incomingpath)
  ```
- Run verification:
  ```perl
  verify_bag()
  ```
- If verification succeeds:
  - Record `filesize`
  - Set:
    ```json
    "verified": "now"
    ```
- If verification fails:
  - Set failure metadata
  - Update CouchDB
  - Abort replication

Important: 'now' is interpreted by the CouchDB update handler to set the date to the current timestamp.

##### Step 10. Persist Verification Metadata
- Write verification and size data to CouchDB before modifying the live repository copy
- This ensures fixity results are preserved even if later steps fail.

##### Step 11. Remove Existing Local AIP (If Present)
- If a previous local AIP revision exists:
  - Delete it using `aip_delete`
- If deletion fails:
  - Update CouchDB with failure state
  - Abort replication

##### Step 12. Promote New AIP into Repository
- Move the verified bag into the live repository using:
  ```perl
  aip_add(contributor, identifier, updatedoc)
  ```
- If this fails:
  - Update CouchDB with failure state
  - Abort replication

---

### Algorithm: `item_repository` CouchDB Update Function

The following is the basic algorithm implemented by the CouchDB update handler used for `item_repository` documents (the `itemrepo` function).

It is called throughout the above steps, updating the AIP document as progress continues on the replication work. It updates only a fixed set of metadata fields and encodes replication state transitions implicitly.

#### High-Level Purpose

The update function:
- Creates `item_repository` documents when missing
- Applies controlled metadata updates from `req.form`
- Manages replication queue flags
- Records verification and manifest state
- Ensures successful replication clears replication intent

#### Inputs

- `doc`: existing CouchDB document (or `null`)
- `req.id`: document ID (`<owner>|item_repository.<repo>`)
- `req.form`: key/value update payload

#### Core Algorithm

##### Step 1: Initialize Timestamp

1. Generate current timestamp:
   - `nowdates = ISO timestamp (seconds precision)`

##### Step 2: Create Document If Missing

If `doc` does not exist:

1. Require `req.id`
2. Parse:
   - `owner` from ID prefix
   - `repository` from ID suffix
3. Create document with:
   - `_id`
   - `type = "item_repository"`
   - `owner`
   - `repository`
   - `document date = nowdates`
4. Mark document as updated

If `req.id` is missing or invalid → abort with error

##### Step 3: Process Update Payload (`req.form`)

If `req.form` exists, apply updates field-by-field.

##### Step 4: Verification Updates

If `verified date` is present in input:
- Set `doc["verified date"] = input value`

If `verified` is present in input:
- Set `doc["verified date"] = nowdates`

(No boolean verification state is stored.)

##### Step 5: Filesize Updates

If `filesize` present:
- Set `doc["filesize"]`

If `nofilesize` present:
- Delete `doc["filesize"]`

##### Step 6: Storage Location Update

If `pool` present:
- Set `doc["pool"]`

##### Step 7: Manifest Updates

###### Manifest Date

If `manifest date` present:
- Set `doc["manifest date"]`
- Set `doc["add date"] = nowdates`

###### Manifest Checksum

If `manifest md5` present:
- Set `doc["manifest md5"]`
- Set `doc["add date"] = nowdates`
- Delete:
  - `doc["replicate"]`
  - `doc["replicatepriority"]`
  - legacy `doc["priority"]`

This represents successful replication or ingest.

##### Step 8: Replication Queue Control

If `replicate` present in input:

###### Case A: `replicate == "false"`

- Delete:
  - `doc["replicate"]`
  - `doc["replicatepriority"]`

This marks replication work as completed or cancelled.

###### Case B: `replicate != "false"`

1. Set `doc["replicate"] = "true"`
2. Set `doc["replicatepriority"] = <value>:<timestamp>` only if:
   - `force` present in input, or
   - `replicatepriority` not already set

This prevents accidental priority downgrade.

##### Step 9: Legacy Priority Handling

If `priority` present:
- Set `doc["priority"]`

(This field is transitional and independent of replication flags.)

##### Step 10: Commit or No-Op

If any field changed:
- Return updated document (`update`)

Else:
- Return no-op (`no update`)
  
---

### Successful Completion

If all steps complete:

- AIP exists on local ZFS pool
- BagIt verification has passed
- `item_repository.<repo>` document reflects:
  - New manifest
  - Updated verification date
  - Correct filesize
- Replication is complete

Example Final Metadata

**item_repository.swift**

```json
{
  "_id": "aeu.00002|item_repository.swift",
  "_rev": "15-693b78d85b78bb2e155fd9e6c2f8b001",
  "owner": "aeu.00002",
  "repository": "swift",
  "type": "item_repository",
  "document date": "2024-05-06T21:41:43Z",
  "verified date": "2025-12-07T22:58:06Z",
  "filesize": "19675032487",
  "manifest date": "2024-05-06T17:59:52Z",
  "add date": "2024-05-06T21:41:43Z",
  "manifest md5": "93e2e185229ae497188bc77510dd312e"
}
```

**item_repository.orchis**

```json
{
  "_id": "aeu.00001|item_repository.orchis",
  "_rev": "46-eecd1a7d6b3ca352c75fc8dc7100e5cc",
  "owner": "aeu.00001",
  "repository": "orchis",
  "type": "item_repository",
  "document date": "2024-05-06T18:32:16Z",
  "verified date": "2025-07-20T06:33:21Z",
  "filesize": "15557589121",
  "pool": "cihmz3",
  "manifest date": "2024-05-06T17:51:58Z",
  "add date": "2024-05-06T19:26:26Z",
  "manifest md5": "a36757e98ef8f82254e4ca97a814bea7"
}
```

### Ingest and Replicate Summary

| Step | Action                              | Node            | Component            |
| ---- | ----------------------------------- | --------------- | -------------------- |
| 1    | AIP created in WIP & Sapindale      | WIP / Sapindale          | Packaging tools      |
| 2    | BagIt packaging and upload to Swift | Trepat                   | Packaging tools      |
| 3    | `item_repository.swift` created     | Trepat                   | Packaging tools - CouchDB (`tdrepo`)   |
| 4    | `tdr-replicationwork` queues AIP    | Orchis / Romano          | Replicationwork - CouchDB (`tdrepo`) replicate view |
| 5    | `tdr-swiftreplicate` copies AIP     | Orchis / Romano          | SwiftReplicateWorker |
| 6    | Bag verified on ZFS                 | Orchis / Romano          | SwiftReplicateWorker - ZFS (`/cihmz2`)      |
| 7    | Metadata updated                    | Orchis / Romano          | SwiftReplicateWorker - CouchDB (`tdrepo`)   |
| 8    | Queue cleared                       | Orchis / Romano          | SwiftReplicateWorker - CouchDB (`tdrepo`) replicate view |

---

## 4) Verification & Fixity

See: https://github.com/crkn-rcdr/cihm-repomanage

### A. Verification Process

Each replication includes automatic verification (see replication proccess obive for more info:)

* Ensures the bag is valid per BagIt specification.
* Confirms the MD5/SHA checksum matches the Swift manifest.
* If valid, updates `verified date`.

### B. Periodic Re‑Verification

Verification ensures long‑term fixity by re‑computing hashes on stored content.

#### Verifying Swift 

See: https://github.com/crkn-rcdr/CIHM-TDR/blob/main/bin/tdr-swiftvalidate

Runs on Trepat every 16 hours to verify the content on Swift. 

The Swift validation algorithm runs against Swift object storage using `CIHM::TDR::Swift->new($config)->validate(\%options)`.  Swift validation verifies an AIP by comparing the contents of Swift to the AIP’s manifest files stored in Swift, and then updates CouchDB (tdrepo) for item_repository.swift when the AIP is valid.

##### Algorithm Steps 

###### Step 1: Get list of AIPs to validate
1. Record `start_time`
2. Query CouchDB view `_design/tdr/_view/repopoolverified` with:
   - `reduce=false`
   - `startkey=["swift"]`
   - `endkey=["swift",{}]`
   - optionally `limit` and `skip`
3. Extract `value` from each row as an AIP id and build `@aiplist`
4. For each AIP in `@aiplist`:
   - stop if `timelimit` exceeded
   - call `validateaip(aip)` on each AIP; running the following steps...

###### Step 2: validateaip - Initialize 
1. Build an allowlist (`passlist`) for known tag files:
   - `bag-info.txt`, `bagit.txt`
   - `manifest-md5.txt`, `tagmanifest-md5.txt`
   - `validate = 1`
   - `filesize = 0`

###### Step 3: validateaip - List Swift objects under the AIP prefix
1. Call `container_get(container, { prefix => "<aip>/" })`
2. Repeat in a loop because Swift listings are capped (10,000):
   - If results returned:
     - set `marker` to the last object name to fetch the next page
     - for each object:
       - compute relative filename (strip `<aip>/`)
       - store object metadata in `%aipdata[file] = object`
3. If `container_get` fails (HTTP != 200):
   - warn and return `{}` (hard failure)

###### Step 4: validateaip - Fetch and parse `manifest-md5.txt`
1. `object_get(container, "<aip>/manifest-md5.txt")`
2. If missing/failed (HTTP != 200):
   - warn and return `{}`
3. Record manifest metadata into return structure:
   - `manifest date = File-Modified header`
   - `manifest md5 = ETag`
4. For each line in manifest (format: `<md5> <file>`):
   - If file exists in `%aipdata`:
     - add object bytes to `filesize`
     - compare `aipdata[file].hash` vs manifest md5
       - mismatch → `validate = 0` (and verbose dump)
     - mark `aipdata[file].checked = 1`
   - Else:
     - file missing → `validate = 0` (verbose print)

###### Step 5: validateaip - Fetch and parse `tagmanifest-md5.txt` (optional)
1. `object_get(container, "<aip>/tagmanifest-md5.txt")`
2. If HTTP 200:
   - record:
     - `tagmanifest date = File-Modified`
     - `tagmanifest md5 = ETag`
   - parse lines and perform same checks as manifest:
     - existence
     - md5 vs Swift object hash
     - add bytes to `filesize`
     - mark `checked`
3. If HTTP 404:
   - treat as acceptable for older bags (no error)
4. If other HTTP error:
   - warn and return `{}`

###### Step 6: validateaip - Detect “extra” Swift objects
For every object in `%aipdata`:
- if it was not `checked` by manifest/tagmanifest
- and it is not in the allowlist (`passlist`)
→ mark `validate = 0` and (optionally) print “extra file”

###### Step 7: validateaip - On success: update CouchDB
If `validate == 1`:
- call `tdrepo->update_item_repository(aip, { verified => 'now', filesize => total_bytes })`

The CouchDB update handler will convert `verified` into setting `verified date = now`.

###### Step 8: validateaip - Return results
Return a structure like:
- `validate` (1/0)
- `filesize`
- `manifest date`, `manifest md5`
- optionally `tagmanifest date`, `tagmanifest md5`

###### Step 9. Shutdown and summarize
- increment `valid` or `invalid` counters based on return value
- Print and log totals and runtime

#### Verifying ZFS 

See: https://github.com/crkn-rcdr/CIHM-TDR/blob/main/lib/CIHM/TDR/App/Verify.pm

Verification runs on Orchis and Romano ZFS nodes every 8 hours. 

The verification algorithm used by the TDR ZFS verification command implemented in `CIHM::TDR::App::Verify` verifies BagIt AIPs stored on local ZFS pools (e.g., Orchis/Romano) and updates CouchDB (`tdrepo`) with verification timestamps and filesizes.

For a given pool, verification candidates are pulled from a CouchDB view:
- Design doc: `_design/tdr`
- View: `repopoolverified`
- Key range:
  - `startkey=[repository,pool]`
  - `endkey=[repository,pool,{}]`
- `reduce=false`
- `limit=<limit>`

The view returns rows with `value = <uid>`.

The view is structured so that results are ordered by “least recently verified” for that repository and pool which ensures the verifier re-checks the oldest-checked bags first.

##### Algorithm Steps

###### Step 1. Initialize repository + counters
1. Load TDR configuration and create a `CIHM::TDR::Repository` instance.
2. Verify `tdrepo` is configured; abort if missing.
3. Initialize counters:
   - `verified.count`
   - `error.count`
4. Record `start_time`.


###### Step 2. Create a parallel worker pool
1. Create an `AnyEvent::Fork::Pool` executing:
   - `CIHM::TDR::VerifyWorker::bag_verify`
2. Configure:
   - `max = maxprocs`
   - `load = workqueue`
3. Create a semaphore sized to:
   - `maxprocs * workqueue`
   (limits the number of in-flight jobs)

###### Step 3. Select next AIP to verify (round-robin by pool)
Loop:
1. Call `next_uid()` to get an AIP UID (e.g., `aeu.00002`)
2. Stop if:
   - No UID returned, or
   - `timelimit` exceeded

Selection logic in `next_uid()`:
- Discover all local pools once (`t_repo->pools()`).
- For each pool, fetch a queue of candidate UIDs using `get_pool_queue(pool, limit)`.
- Iterate pools in round-robin:
  - pop one UID from that pool queue
  - mark UID as `tried` so it won’t repeat in the same run
  - push that pool to the end of the pool list
- If a pool queue empties, refresh it from CouchDB view and continue.

###### Step 4. Resolve UID → filesystem path
For each UID:
1. Split into `(contributor, identifier)`
2. Find the AIP path on disk:
   - `find_aip_pool(contributor, identifier)`
3. If no path is found:
   - log error and continue (skips verification)

###### Step 5. Verify bag in a worker process
For each AIP path:
1. Submit to worker pool:
   - `bag_verify(aippath)`
2. The worker returns:
   - `ver_res` (expected `"ok"` on success)
   - `ver_path`
   - serialized `bag_stats` (thawed via `Storable::thaw`)

###### Step 6. On success: update CouchDB with verification + size
If `ver_res == "ok"`:
1. Thaw `bag_stats`
2. Update CouchDB via repository helper:
   ```perl
   update_item_repository($uid, { verified => 'now', filesize => $bag_stats->{size} })
   ```
3. Increment `verified.count`
4. Log timing and stats

Important: `verified => 'now'` is interpreted by the CouchDB update handler to set `verified date` to the current timestamp.

###### Step 7. On failure: record invalid bag
If `ver_res != "ok"`:
1. Increment `error.count`
2. Log warning including failure reason and path
3. Continue to next UID

###### Step 8. Shutdown and summarize
1. Destroy pool and wait for workers to finish (`$cv_finish->recv`)
2. Print totals:
   - valid bags verified
   - invalid bags found
   - total runtime
3. Log summary of totals

## Logging

Replication and verification logs are written to:

```
/var/log/tdr/root.log
```

Each event is also logged in CouchDB for audit and traceability.
