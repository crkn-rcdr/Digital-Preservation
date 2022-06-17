# CRKN's use of Archivematica

In 2018 CRKN, with the support of the Preservation and Access Committee, confirmed the decision that Canadiana had made earlier to transition from a custom OAIS packaging system to Archivematica.

In parallel with the packaging system work, CRKN will be moving away from custom software built on top of ZFS to using OpenStack Swift.

## Simplified steps

* Adopting new practises with existing tools to more closely match how we will work with Archivematica
* Learning, making policy decisions, and documenting how we will be using Archivematica
* Creating tools that allow data from Archivematica packages to be "Import into Access"
* Creating and running tools to migrate existing AIPs from the custom CIHM/Canadiana/CRKN format to Archivematica


We will be making use of GitHub's issue tracking system for discussion with the wider community, and using this source repository for documentation.


### Transforming Canadiana AIPs into structure used by Archivematica

There are several similarities between how Canadiana stores files within packages and how Archivematica does.

* Both use [BagIt](https://en.wikipedia.org/wiki/BagIt)
* Both use [METS](https://en.wikipedia.org/wiki/Metadata_Encoding_and_Transmission_Standard)
* The file formats which Canadiana preserves are a subset of what Archivematica can preserve

Some discussion, policy decisions, and planning will be required for differences.

* Policy question: Should the transformation be lossless, including maintaining structural and access data? (See: [Issue #10](https://github.com/crkn-rcdr/Digital-Preservation/issues/10))
* Canadiana AIPs can encapsulate the files of multiple SIPs (See: [Issue #3](https://github.com/crkn-rcdr/Digital-Preservation/issues/3))
* Canadiana stores full METS records whenever descriptive metadata is updated (See: [Issue #4](https://github.com/crkn-rcdr/Digital-Preservation/issues/4))
* Canadiana has made use of PrimeOCR and Abbyy Recognition Server to generate XML and PDF files (See: [Issue #5](https://github.com/crkn-rcdr/Digital-Preservation/issues/5))
* Canadiana uses 3 different formats for archival descriptive metadata, while Archivematica only uses Dublin Core (See: [Issue #6](https://github.com/crkn-rcdr/Digital-Preservation/issues/6))
* Older Canadiana processes caused the ingest of duplicate data, and we may want to deduplicate as part of the transformation (See: [Issue #7](https://github.com/crkn-rcdr/Digital-Preservation/issues/7))
