module.exports.map = function(doc) {
    var attach = 0;
    if ("METS" in doc && Array.isArray(doc.METS)) {
	attach = doc.METS.length;
    }
    emit(attach, null);
};
module.exports.reduce = "_count";
