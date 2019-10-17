module.exports = function(doc, req) {
  if ("form" in req) {
    var updatedoc = req.form;
    if (!doc) {
      if ("id" in req && req["id"]) {
        if ("nocreate" in updatedoc) {
          return [null, '{"return": "no create"}\n'];
        } else {
          // create empty document with id
          doc = {};
          doc["_id"] = req["id"];
        }
      } else {
        return [null, '{"error": "Missing ID"}\n'];
      }
    }
    if ("doc" in updatedoc) {
      // This parameter sent as JSON encoded string
      var newdoc = JSON.parse(updatedoc["doc"]);

      // newdoc will replace the old document, but needs these fields
      newdoc["_id"] = doc["_id"];
      newdoc["_rev"] = doc["_rev"];
      return [newdoc, '{"return": "update"}\n'];
    }
  }
  return [null, '{"return": "no update"}\n'];
};
