module.exports.map = function(doc) {
    if (("md5summary" in doc) &&
        "revduplicates" in doc["md5summary"]
       ) {
	nummd5 = Object.keys(doc["md5summary"]["revduplicates"]).length;
	if (nummd5 >0) {
            emit(nummd5,null);
	}
    };
};
module.exports.reduce = "_count";
