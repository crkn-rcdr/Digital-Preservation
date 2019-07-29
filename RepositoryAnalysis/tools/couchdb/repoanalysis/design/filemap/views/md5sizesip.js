module.exports.map = function(doc) {
    if ("sipfiles" in doc) {
	Object.keys(doc["sipfiles"]).forEach(function(file) {
	    emit(doc["sipfiles"][file],file);
	});
    };
};
module.exports.reduce = "_count";
