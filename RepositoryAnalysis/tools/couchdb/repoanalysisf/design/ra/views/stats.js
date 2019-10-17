module.exports = {
  map: function(doc) {
    if ("status" in doc) {
      var idsp = doc["_id"].split(".");
      var dep = idsp.shift();
      var ext = idsp.pop();
      if (dep === "oocihm" && idsp[0].indexOf("lac_reel") === 0) {
        dep = "oocihm.lac_reel";
      }
      var errormsg = doc.errormsg;
      if (typeof errormsg === "string") {
        if (errormsg.indexOf("Invalid DateTime length:") === 0) {
          errormsg = "Invalid DateTime length";
        } else if (errormsg.indexOf("IFD offset not word-aligned:") === 0) {
          errormsg = "IFD offset not word-aligned";
        } else if (errormsg.indexOf("Value offset not word-aligned:") === 0) {
          errormsg = "Value offset not word-aligned";
        } else if (errormsg.indexOf("Invalid DateTime digit:") === 0) {
          errormsg = "Invalid DateTime digit";
        }
      }
      emit([doc.status, doc.format, ext, dep, errormsg], null);
    }
  },
  reduce: "_count"
};
