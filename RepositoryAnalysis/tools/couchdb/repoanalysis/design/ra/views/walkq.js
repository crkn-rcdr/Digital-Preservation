module.exports.map = function(doc) {
    if (!("summary" in doc) ||
        !("manifestdate" in doc["summary"]) ||
        doc["manifestdate"] != doc["summary"]["manifestdate"]
       ) {
        emit(doc["manifestdate"],doc["metscount"]);
    };
};
module.exports.reduce = "_count";
