module.exports.map = function(doc) {
    if ("METS" in doc && Array.isArray(doc.METS)) {
	var partial = 0;
	var full = 0;
	doc.METS.forEach(function(mets) {
	    if ((mets['path'].indexOf(".partial/metadata.xml")) != -1) {
		partial++;
	    } else {
		full++;
	    }
	});
	emit(["partial",partial], null);
	emit(["full",full], null);
    }
};
module.exports.reduce = "_count";
