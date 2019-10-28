module.exports.map = function(doc) {
    if ("summary" in doc &&
        ("manifestdate" in doc["summary"])
	) {
        emit(doc.summary.reposManifestDate,null);
    };
};
module.exports.reduce = "_count";
