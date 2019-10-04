module.exports.map = function(doc) {
    if (!("md5summary" in doc) ||
	doc["reposManifestDate"] != doc["md5summary"]["manifestdate"]
       ) {
        emit(doc["reposManifestDate"],null);
    };
};
module.exports.reduce = "_count";
