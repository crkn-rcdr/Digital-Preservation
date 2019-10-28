module.exports = {
  map: function(doc) {
      if ("jhove_error" in doc) {
	  emit(null,null);
      }
  },
  reduce: "_count"
};
