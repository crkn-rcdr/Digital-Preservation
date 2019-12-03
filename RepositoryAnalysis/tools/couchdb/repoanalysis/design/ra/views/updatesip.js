module.exports.map = function(doc) {
    if ("metadatasummary" in doc &&
        ("changes" in doc["metadatasummary"])
       ) {
	doc["metadatasummary"]["changes"].forEach(function(logentry){
	    if (("operation" in logentry) && (logentry["operation"] === "updatesip")) {
		if ("reason" in logentry) {
                    emit(logentry["reason"]);
		};
		if ("changelog" in logentry) {
                    emit(logentry["changelog"]);
		};
            }
	});
    };
};
module.exports.reduce = "_count";
