module.exports.map = function(doc) {
    if ("metadatasummary" in doc &&
        ("changes" in doc["metadatasummary"])
       ) {
	doc["metadatasummary"]["changes"].forEach(function(logentry){
	    if ("line" in logentry) {
		emit(logentry["line"]);
            }
	});
    };
};
module.exports.reduce = "_count";

