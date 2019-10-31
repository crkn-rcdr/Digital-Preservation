module.exports = {
  map: function(doc) {
      emit([doc['md5'],doc['length']],null);
  },
  reduce: "_count"
};
