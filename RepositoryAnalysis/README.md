# CRKN Repository Analysis

As of July 2, 2019, the CRKN repository has 320,762 AIPs, with the most recent SIPs representing  73,349,571 files (JPEG, JPEG 2000, TIFF, PDF).

As we move forward with developing the repository platform we will want to have a better idea of what traits each AIP has so that:

* We have good examples to use to test software
* We can analyse classes in determining policy when converting the existing repository to being managed using Archivematica
* We have a better idea of the structure of our repository for other reporting purposes


## Traits to determine

* Files and structure
   * Single SIP, or multiple SIP (excluding metadata updates)
   * Duplicate SIP?
   * Duplicate files across SIP revisions?
   * Files in SIP revisions that exist within other AIPs (current or previous revisions)
   * Only one type of file (image, PDF)
* Metadata
   * Metadata updates, and what was different (dmdSec, structMap order, labels, ?other?)
   * Image files which have OCR, and which format used (txtmap or Alto)

## Questions to help answer

1. Examples of AIPs with each descriptive metadata format, with and without &lt;div&gt; labels.
1. Examples of AIPs with a small number of images (0 for series records) and a large number of images (Heritage reels)
1. List of AIPs with born digital PDFs
1. Examples of AIPs with different image types
1. When a SIP revision or metadata update was made, what was the reason?
    * Duplicate SIP due to error
    * Addition of missing file, removing of incorrect file
    * Re-ordering of images
    * Changing identifier (all files exist in AIP with different identifier)
    * Change of labels
    * Change of descriptive metadata
1. If we exclude label or descriptive metadata changes (which would have been done in the access platform), and exclude duplicates (same or different AIP identifier - See [issue #7](https://github.com/crkn-rcdr/Digital-Preservation/issues/7)  ), what files remain?
