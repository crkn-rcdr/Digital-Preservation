module.exports.map = function(doc) {
    if (("md5summary" in doc) &&
        ("manifestdate" in doc["md5summary"]) &&
        doc["manifestdate"] == doc["md5summary"]["manifestdate"]
       ) {
        emit(doc["md5summary"]["md5dup"],null);
    };
};
module.exports.reduce = "_count";
