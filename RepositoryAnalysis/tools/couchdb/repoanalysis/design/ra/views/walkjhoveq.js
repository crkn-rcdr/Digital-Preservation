module.exports.map = function(doc) {
    if (("summary" in doc) && ("manifestdate" in doc.summary) &&
	(doc.summary.manifestdate == doc.reposManifestDate) &&
	(!("jhovesummary" in doc) ||
	 (doc.summary.manifestdate != doc.jhovesummary.manifestdate)
	)
       ) {
        emit(doc.reposManifestDate,null);
    };
};
module.exports.reduce = "_count";
