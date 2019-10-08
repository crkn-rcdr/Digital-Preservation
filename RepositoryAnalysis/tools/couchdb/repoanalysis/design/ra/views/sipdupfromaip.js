module.exports.map = function(doc) {
    if (("md5summary" in doc) &&
        "sipdupfromaip" in doc["md5summary"] &&
	Array.isArray(doc["md5summary"]["sipdupfromaip"])
       ) {
	numaip = doc["md5summary"]["sipdupfromaip"].length;
	if (numaip >0) {
            emit(numaip,null);
	}
    };
};
module.exports.reduce = "_count";
