module.exports = {
  map: function(doc) {
      if ("jhove_container" in doc) {
	  emit(doc["jhove_container"],null);
      }
  },
  reduce: "_count"
};
