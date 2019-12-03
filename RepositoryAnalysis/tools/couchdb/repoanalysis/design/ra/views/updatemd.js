module.exports.map = function(doc) {
    if ("metadatasummary" in doc &&
        ("changes" in doc["metadatasummary"])
       ) {
	doc["metadatasummary"]["changes"].forEach(function(logentry){
	    if (("operation" in logentry) && (logentry["operation"] === "mdupdate")) {
		if ("reason" in logentry) {
                    emit(logentry["reason"]);
		} else if ("changelog" in logentry) {
                    emit(logentry["changelog"]);
		} else {
		    emit("Empty Log");
		};
            }
	});
    };
};
module.exports.reduce = "_count";
