module.exports = {
  map: function(doc) {
    if ("status" in doc) {
      var pathsp = doc["_id"].split("/");
      var aip = pathsp.shift();
      var filename = pathsp.pop();

      var ntype = filename.match(/^[0-9]+\.[^\.]+$/) ? "seq" : "alpha";
      if (filename === "document.pdf") {
        ntype = filename;
      }

      var idsp = aip.split(".");
      var dep = idsp[0];
      var objid = idsp[1];
      if (dep === "oocihm" && objid.indexOf("lac_reel") === 0) {
        dep = "oocihm.lac_reel";
      }

      emit([ntype, dep], null);
    }
  },
  reduce: "_count"
};
