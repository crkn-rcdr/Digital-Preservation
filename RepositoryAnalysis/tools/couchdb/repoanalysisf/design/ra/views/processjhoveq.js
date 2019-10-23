module.exports = {
  map: function(doc) {
      if ("jhove_last_modified" in doc && (
	  ! ("jhove_processed" in doc) ||
	      (doc["jhove_last_modified"] !== doc["jhove_processed"]))) {
	  emit(null,null);
      }
  },
  reduce: "_count"
};
