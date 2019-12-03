module.exports.map = function(doc) {
    if ("metadatasummary" in doc &&
        ("message" in doc["metadatasummary"]) &&
	(doc["metadatasummary"]["message"] !== '')
       ) {
	emit([doc["metadatasummary"]["status"],doc["metadatasummary"]["message"]]);
    };
};
module.exports.reduce = "_count";

