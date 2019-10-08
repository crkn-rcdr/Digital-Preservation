module.exports.map = function(doc) {
    if (("md5summary" in doc) &&
        "globaluniq" in doc["md5summary"]
       ) {
	//  Checks that string ends with the specific string...
	if (typeof String.prototype.endsWith != 'function') {
	    String.prototype.endsWith = function (str) {
		return this.slice(-str.length) == str;
	    };
	};
	function filterPDF(filename) {
	    return ! filename.endsWith('.pdf');
	};
	nopdf = doc["md5summary"]["globaluniq"].filter(filterPDF);
	numfiles = nopdf.length;
	if (numfiles >0) {
            emit(numfiles,null);
	}
    };
};
module.exports.reduce = "_count";
