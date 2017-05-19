<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:mets="http://www.loc.gov/METS/"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xmlns:marc="http://www.loc.gov/MARC21/slim"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:txt="http://canadiana.ca/schema/2012/xsd/txtmap"
  xmlns:issue="http://canadiana.ca/schema/2012/xsd/issueinfo"
  exclude-result-prefixes="mets xlink marc dc txt issue"
>
  
  <!--
    Validate a Canadiana METS document. Any errors will be output in <error>
    elements. A valid document will result in an empty <cmetsValidation> root element.
  -->

  <xsl:output method="xml" encoding="utf-8" indent="yes"/>

  <xsl:key name="dmd" match="mets:dmdSec" use="@ID"/>
  <xsl:key name="file" match="mets:file" use="@ID"/>

  <xsl:template match="/mets:mets">
    <cmetsValidation id="{@OBJID}">
      
      <!-- Test the validity of the OBJID attribute -->
      <xsl:if test="string-length(@OBJID) &lt; 5">
        <error>@OBJID does not meet the minimum length of 5 characters</error>
      </xsl:if>
      <xsl:if test="string-length(@OBJID) &gt; 127">
        <error>@OBJID exceeds the maximum length of 127 characters</error>
      </xsl:if>
      <xsl:if test="string-length(translate(@OBJID, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_', '')) != 0">
        <error>@OBJID contains characters other than A-Za-z0-9_</error>
      </xsl:if>

      <!-- Make sure we have only one structMap -->
      <xsl:if test="count(mets:structMap) = 0">
        <error>Document does not contain a structMap</error>
      </xsl:if>
      <xsl:if test="count(mets:structMap) &gt; 1">
        <error>Document contains multiple structMaps</error>
      </xsl:if>

      <xsl:apply-templates select="mets:structMap"/>

    </cmetsValidation>
  </xsl:template>

  <xsl:template match="mets:structMap">

    <!-- Verify that the value of the TYPE attribute is "physical" -->
    <xsl:if test="@TYPE != 'physical'">
      <error>structMap should have TYPE attribute with value of "physical"</error>
    </xsl:if>

    <!-- Validate the main div type -->
    <xsl:if test="not(mets:div/@TYPE = 'document' or mets:div/@TYPE = 'series' or mets:div/@TYPE = 'issue')">
      <error>structMap root div's TYPE must be one of: document, series, issue</error>
    </xsl:if>

    <xsl:apply-templates select="mets:div"/>

  </xsl:template>


  <xsl:template match="mets:div">

    <!-- Validate the type -->
    <xsl:if test="not(@TYPE = 'document' or @TYPE = 'series' or @TYPE = 'issue' or @TYPE = 'page')">
      <error>structMap div's TYPE must be one of: document, series, issue</error>
    </xsl:if>

    <!-- Make sure the label attributeattribute exists -->
    <xsl:if test="string-length(@LABEL) = 0">
      <error>Found structMap div (ID="<xsl:value-of select="@ID"/>") with empty or missing LABEL attribute</error>
    </xsl:if>

    <!-- Requirements specific to page records -->
    <xsl:if test="@TYPE='page'">
      <xsl:if test="mets:div">
        <error>Found page div containing further child div elements</error>
      </xsl:if>
    </xsl:if>


    <!-- Check for the dmdSec associated with the div -->
    <xsl:choose>
      <xsl:when test="@TYPE = 'document' or @TYPE='series'">
        <xsl:choose>
          <xsl:when test="key('dmd', @DMDID)/mets:mdWrap[@MDTYPE='MARC']/descendant::marc:record"/>
          <xsl:when test="key('dmd', @DMDID)/mets:mdWrap[@MDTYPE='DC']/mets:xmlData/simpledc"/>
          <xsl:otherwise>
            <error>Document or series record <xsl:value-of select="@ID"/> does not have a matching dmdSec with a Simple Dublin Core or MARCXML record</error>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:when>
      <xsl:when test="@TYPE = 'issue'">
        <xsl:if test="not(key('dmd', @DMDID)/descendant::issue:issueinfo)">
          <error>Issue <xsl:value-of select="@ID"/> does not have a matching dmdSec with issueinfo record</error>
        </xsl:if>
      </xsl:when>
      <xsl:when test="@TYPE = 'page' and @DMDID">
        <xsl:if test="not(key('dmd', @DMDID)/descendant::txt:txtmap)">
          <error>Page <xsl:value-of select="@ID"/> does not have a matching dmdSec with txtmap record</error>
        </xsl:if>
      </xsl:when>
    </xsl:choose>

    <xsl:apply-templates select="mets:fptr"/>
    
    <xsl:apply-templates select="mets:div"/>
  </xsl:template>


  <xsl:template match="mets:fptr">
    <!-- Verify the file pointer's reference -->
    <xsl:if test="not(key('file', @FILEID))">
      <error>Found fptr with FILEID="<xsl:value-of select="@FILEID"/>" without a valid file reference</error>
    </xsl:if>
    <xsl:apply-templates select="key('file', @FILEID)"/>
  </xsl:template>

  <xsl:template match="mets:file">
    <!-- Check that the declared MIME type is acceptable -->
    <xsl:choose>
      <xsl:when test="@USE = 'master' or ../@USE = 'master'">
          <xsl:if test="not(@MIMETYPE = 'image/tiff' or @MIMETYPE = 'image/jpeg' or @MIMETYPE = 'image/jp2' or @MIMETYPE = 'application/pdf')">
            <error>MIME type for file ID="<xsl:value-of select="@ID"/>" should be one of: image/tiff, image/jpeg , image/jp2, or application/pdf</error>
          </xsl:if>
          <xsl:if test="not(count(mets:FLocat[@LOCTYPE = 'URN']) = 1 and mets:FLocat[@LOCTYPE = 'URN']/@xlink:href != '')">
            <error>file element with ID="<xsl:value-of select="@ID"/>" does not have an FLocat child with LOCTYPE="URN" and a valid XLink href attribute</error>
        </xsl:if>
      </xsl:when>
      <xsl:when test="@USE = 'distribution' or ../@USE = 'distribution' or @USE = 'derivative' or ../@USE = 'derivative'">
        <xsl:if test="not(@MIMETYPE = 'image/tiff' or @MIMETYPE = 'image/jpeg' or @MIMETYPE = 'image/jp2' or @MIMETYPE = 'application/pdf' or @MIMETYPE = 'application/xml')">
          <error>MIME type for file ID="<xsl:value-of select="@ID"/>" should be one of: image/tiff, image/jpeg , image/jp2, application/pdf, or application/xml</error>
        </xsl:if>
        <xsl:if test="not(count(mets:FLocat[@LOCTYPE = 'URN']) = 1 and mets:FLocat[@LOCTYPE = 'URN']/@xlink:href != '')">
          <error>file element with ID="<xsl:value-of select="@ID"/>" does not have an FLocat child with LOCTYPE="URN" and a valid XLink href attribute</error>
        </xsl:if>
      </xsl:when>
      <xsl:when test="@USE = 'canonical' or ../@USE = 'canonical'">
        <!-- no specific rules yet ... -->
      </xsl:when>
      <xsl:otherwise>
        <error>file element in fileSec with unsupported USE attribute {../@USE} (must be one of:  derivative, distribution, canonical, master)</error>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

</xsl:stylesheet>

