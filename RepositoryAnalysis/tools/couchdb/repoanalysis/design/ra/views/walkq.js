module.exports.map = function(doc) {
    if ("reposManifestDate" in doc &&
	(!("summary" in doc) ||
         !("manifestdate" in doc["summary"]) ||
         doc["reposManifestDate"] != doc["summary"]["manifestdate"]
	)
       ) {
        emit(doc["reposManifestDate"],null);
    };
};
module.exports.reduce = "_count";
