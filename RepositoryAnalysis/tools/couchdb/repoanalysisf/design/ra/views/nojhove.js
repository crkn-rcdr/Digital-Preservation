module.exports = {
  map: function(doc) {
      if (! ("jhove_container" in doc)) {
	  var pathsp = doc["_id"].split("/");
	  var aip = pathsp.shift();
	  emit(aip,null);
      }
  },
  reduce: "_count"
};
