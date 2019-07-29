module.exports.map = function(doc) {
    if (("md5summary" in doc) &&
        "globaluniq" in doc["md5summary"]
       ) {
	numfiles = doc["md5summary"]["globaluniq"].length;
	if (numfiles >0) {
            emit(numfiles,null);
	}
    };
};
module.exports.reduce = "_count";
