module.exports.map = function(doc) {
    if ("summary" in doc &&
	"revfiles" in doc["summary"] &&
        doc["summary"]["revfiles"] == 0 &&
        "METS" in doc && Array.isArray(doc.METS) &&
        doc.METS.length > 0
       ) {
	emit(null,null);
    };
};
module.exports.reduce = "_count";
