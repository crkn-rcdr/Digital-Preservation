module.exports.map = function(doc) {
    if ("metscount" in doc) {
	emit(doc["metscount"],null);
    };
};
module.exports.reduce = "_count";
