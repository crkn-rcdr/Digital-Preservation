module.exports = {
  map: function(doc) {
      if (! ("jhove_container" in doc)) {
	  emit(null,null);
      }
  },
  reduce: "_count"
};
