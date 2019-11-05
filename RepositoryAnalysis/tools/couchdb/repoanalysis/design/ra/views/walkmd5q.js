module.exports.map = function(doc) {
    if (("summary" in doc) && ("manifestdate" in doc.summary) &&
	(doc.summary.manifestdate == doc.reposManifestDate) &&
	(!("md5summary" in doc) ||
	 (doc.summary.manifestdate != doc.md5summary.manifestdate)
	)
       ) {
        emit(doc.reposManifestDate,null);
    };
};
module.exports.reduce = "_count";
