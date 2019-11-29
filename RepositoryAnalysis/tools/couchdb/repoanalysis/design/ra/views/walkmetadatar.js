module.exports.map = function(doc) {
    if (("metadatasummary" in doc) &&
        ("manifestdate" in doc["metadatasummary"]) &&
        doc["reposManifestDate"] == doc["metadatasummary"]["manifestdate"]
       ) {
        emit(doc["metadatasummary"]["missing"],null);
    };
};
module.exports.reduce = "_count";
