module.exports.map = function(doc) {
    if (("md5summary" in doc) &&
        "dupfromaip" in doc["md5summary"] &&
	Array.isArray(doc["md5summary"]["dupfromaip"])
       ) {
	numaip = doc["md5summary"]["dupfromaip"].length;
	if (numaip >0) {
            emit(numaip,null);
	}
    };
};
module.exports.reduce = "_count";
