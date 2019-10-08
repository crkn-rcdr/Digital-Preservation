module.exports.map = function(doc) {
    if (("md5summary" in doc) &&
        "revdupfromaip" in doc["md5summary"] &&
	Array.isArray(doc["md5summary"]["revdupfromaip"])
       ) {
	numaip = doc["md5summary"]["revdupfromaip"].length;
	if (numaip >0) {
            emit(numaip,null);
	}
    };
};
module.exports.reduce = "_count";
