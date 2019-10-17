module.exports.map = function(doc) {
    if (("sipfiles" in doc) &&
	(Object.keys(doc.sipfiles).length > 0)) {

	//  Checks that string ends with the specific string...
        if (typeof String.prototype.endsWith != 'function') {
            String.prototype.endsWith = function (str) {
                return this.slice(-str.length) == str;
            };
        };

	// The length of the file is less than 10 bytes
	function smallfile(thisfile) {
	    return (parseInt(doc.sipfiles[thisfile][1]) < 10);
	}
	if (Object.keys(doc.sipfiles).some(smallfile)) {
	    emit(null,null);
	}
    };
};
module.exports.reduce = "_count";
