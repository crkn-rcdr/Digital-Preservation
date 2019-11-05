module.exports.map = function(doc) {
    if (("jhovesummary" in doc) &&
        ("manifestdate" in doc["jhovesummary"]) &&
        doc["reposManifestDate"] == doc["jhovesummary"]["manifestdate"]
       ) {
        emit(doc["jhovesummary"]["missing"],null);
    };
};
module.exports.reduce = "_count";
