module.exports.map = function(doc) {
    if ("summary" in doc  &&
	doc["summary"]["unique"] > 0 &&
	(
	    !("md5summary" in doc) ||
		doc["reposManifestDate"] != doc["md5summary"]["manifestdate"]
	)
       ) {
        emit(doc["reposManifestDate"],null);
    };
};
module.exports.reduce = "_count";
