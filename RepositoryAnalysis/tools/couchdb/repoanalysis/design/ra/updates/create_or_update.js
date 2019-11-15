module.exports = function(doc, req) {
    var created = false;
    if (!doc) {
	if ("id" in req && req["id"]) {
	    doc = { _id: req["id"] };
	    created = true;
	} else {
	    return [null, "Cannot create a new document without an id"];
	}
    }

    if (! "body" in req) {
	return [null, "Request body required\n"];
    }

    var body;
    try {
	body = JSON.parse(req.body);
    } catch (e) {
	return [null, "Request body is not valid JSON:\n" + e.message];
    }

    ["summary", "revfiles", "sipfiles","metscount","manifestdate","md5summary","jhovesummary"].forEach(function(key) {
	if (body[key]) {
	    doc[key] = body[key];
	}
    });

    if (created) {
	return [doc, "Document " + doc["_id"] + " created"];
    } else {
	return [doc, "Document " + doc["_id"] + " updated"];
    }
};
