module.exports.map = function(doc) {
    if ("summary" in doc &&
	"revfiles" in doc["summary"] &&
        doc["summary"]["revfiles"] > 0
       ) {
	emit(null,null);
    };
};
module.exports.reduce = "_count";
