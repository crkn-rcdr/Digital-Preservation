module.exports = {
  map: function(doc) {
    if ("METS" in doc && Array.isArray(doc.METS)) {
      var md5 = {};
      doc.METS.forEach(function(mets) {
        if (mets.md5 in md5) {
          md5[mets.md5]++;
        } else {
          md5[mets.md5] = 1;
        }
      });
      var dups = 0;
      Object.keys(md5).forEach(function(key) {
        if (md5[key] > 1) {
          dups++;
        }
      });
      if (dups > 0) {
        emit(dups, null);
      }
    }
  },
  reduce: "_count"
};
