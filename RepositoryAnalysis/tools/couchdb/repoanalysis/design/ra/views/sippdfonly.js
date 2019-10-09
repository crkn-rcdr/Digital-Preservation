module.exports.map = function(doc) {
    if (("sipfiles" in doc) &&
	(Object.keys(doc.sipfiles).length > 0)) {

	//  Checks that string ends with the specific string...
        if (typeof String.prototype.endsWith != 'function') {
            String.prototype.endsWith = function (str) {
                return this.slice(-str.length) == str;
            };
        };

	function notPDF(thisfile) {
	    return ! thisfile.endsWith('.pdf');
	}
	if (! Object.keys(doc.sipfiles).some(notPDF)) {
	    emit(null,null);
	}
    };
};
module.exports.reduce = "_count";
