local lfs = require("lfs")
local schema = require("niemify.schema")

local home = os.getenv("NIEMIFY_HOME")
assert(home, "NIEMIFY_HOME must be set for schema tests")
assert(lfs.attributes(home), "NIEMIFY_HOME must point to an existing test directory")

assert(schema.setup().activeSchema == "exchange-demo")
assert(schema.builtin()[1] == "exchange-demo")
local valid = '<ex:Exchange xmlns:ex="urn:niemify:exchange-demo"><ex:MessageId>m-1</ex:MessageId><ex:Sender>a</ex:Sender><ex:Recipient>b</ex:Recipient></ex:Exchange>'
assert(schema.validate(valid, "exchange-demo") == true)
local wrong = '<ex:Exchange xmlns:ex="urn:niemify:exchange-demo"><ex:MessageId>m-1</ex:MessageId></ex:Exchange>'
local ok = pcall(schema.validate, wrong, "exchange-demo")
assert(not ok, "well-formed but invalid XML must be rejected")

local custom = home .. "/custom.xsd"
local file = assert(io.open(custom, "w"))
file:write('<?xml version="1.0"?><xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:element name="Ping" type="xs:string"/></xs:schema>')
file:close()
assert(schema.upload("custom", custom).name == "custom")
assert(schema.switch("custom").name == "custom")
assert(schema.validate("<Ping>ok</Ping>") == true)

local replacement = home .. "/replacement.xsd"
local replacement_file = assert(io.open(replacement, "w"))
replacement_file:write('<?xml version="1.0"?><xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:element name="Pong" type="xs:string"/></xs:schema>')
replacement_file:close()
assert(schema.update("custom", replacement).path == replacement)
assert(schema.config().activeSchema == "custom")
assert(not pcall(schema.validate, "<Ping>ok</Ping>", "custom"))

return true
