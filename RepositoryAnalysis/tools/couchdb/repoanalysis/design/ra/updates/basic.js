module.exports =function(doc, req) {
    var data = {};
    var nowdate = new Date();
    // Javascript toISOString() includes parts of a second, which we strip.
    var nowdates = nowdate.toISOString().replace(/\..*Z/, "Z");
    var updated = false;

    // Note that form data won't work for the values which aren't simple strings
    if (req.form && Object.keys(req.form).length > 0) {
	data = req.form;
    } else {
	try {
	    data = JSON.parse(req.body);
	} catch (ignore) {
	    return [null, "could not parse body: " + req.body];
	}
    }

    if (!doc) {
	if ("id" in req && req.id) {
	    
	    doc = { _id: req.id, deposits: [] , created: nowdates };
	    updated = true;
	} else {
	    return [null, '{"error": "Missing ID"}\n'];
	}
    }
    if ("repos" in data) {

	// Equality is same membership, even if different order
	function hasSameMembers(repo1, repo2) {
            if (!repo1 || !repo2 || repo1.length != repo2.length) {
		return false;
            }
            // TODO: cheating for now - treat same if length same
            return true;
	}
	if (
            !("reposManifestDate" in doc) ||
		!hasSameMembers(doc["repos"], data["repos"])
	) {
            doc["repos"] = data["repos"];
            doc["reposManifestDate"] = data["manifestdate"];
            doc["reposDate"] = nowdates;
            updated = true;
	}
    }
    if ("METS" in data) {
	doc["METS"] = data["METS"];
	doc["METSManifestDate"] = data["manifestdate"];
	doc["METSDate"] = nowdates;
	updated = true;
    }
    var retval = {};
    if ("reposManifestDate" in doc) {
	retval["METSmatch"] =
	    "METSManifestDate" in doc &&
	    doc.reposManifestDate === doc.METSManifestDate;
    }
    if (updated) {
	doc["updated"] = nowdates;
	retval["return"] = "update";
	return [doc, JSON.stringify(retval) + "\n"];
    } else {
	retval["return"] = "no update";
	return [null, JSON.stringify(retval) + "\n"];
    }
};
