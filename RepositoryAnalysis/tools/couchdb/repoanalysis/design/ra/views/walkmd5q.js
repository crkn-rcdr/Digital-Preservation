module.exports.map = function(doc) {
    if ("summary" in doc  &&
	doc["summary"]["unique"] > 0 &&
	(
	    !("md5summary" in doc) ||
		doc["manifestdate"] != doc["md5summary"]["manifestdate"]
	)
       ) {
        emit(doc["manifestdate"],doc["metscount"]);
    };
};
module.exports.reduce = "_count";
