# XML schemas and repository documentation

The **published/** subdirectory contains documentation for the custom XML schemas that Canadiana created, as well as text file documents describing the internal structure of the custom Canadiana OAIS AIP and a SIP.


* **published/schema** is currently available online at http://www.canadiana.ca/schema/
* **published/** is currently available online at http://www.canadiana.ca/standards/


The **unpublished/** subdirectory contains a cache of xsl and xsd files used by repository tools during processing.

## History

This subdirectory contains files previously managed in Canadiana's private subversion repository. The following command was used to clone the repository:

	$ git svn clone file:///data/svn/c7a --trunk=xml/trunk --tags=xml/tags --branches=xml/branches --branches=www/trunk/schema --authors-file=/home/git/authors.txt --no-metadata xml

Unfortunately this command did not maintain the history prior to when the **www/trunk/schema** directory was moved to **xml/trunk/published/schema** . 

Prior to that time the schema directory was maintained by William Wueppelmann as part of a subversion project for managing the website.  The project was started on 2012-05-07, and William made all the updates into late 2013.

Julienne Pascoe made an update on 2015-06-01 to update the contact and compression sections of csip.xml.  All the changes since the 2015-09-29 move to the xml project are contained in this project.
