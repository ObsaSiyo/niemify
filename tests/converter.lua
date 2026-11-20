local converter = require("niemify.converter")
local json = require("dkjson")

local function fail(message)
  error(message, 2)
end

local function equal(actual, expected, path)
  path = path or "$"
  if type(actual) ~= type(expected) then
    fail(path .. ": type mismatch")
  end
  if type(actual) ~= "table" then
    if actual ~= expected then
      fail(path .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
    return
  end
  for key, value in pairs(expected) do
    equal(actual[key], value, path .. "." .. tostring(key))
  end
  for key in pairs(actual) do
    if expected[key] == nil then
      fail(path .. ": unexpected key " .. tostring(key))
    end
  end
end

local function rejects(fn, pattern)
  local ok, err = pcall(fn)
  if ok or not tostring(err):match(pattern) then
    fail("expected error matching " .. pattern .. ", got " .. tostring(err))
  end
end

local source = '<?xml version="1.0"?><p:root xmlns:p="urn:test" id="7">before<a>A</a>between<a>B</a><![CDATA[after]]><!--note--></p:root>'
local document = converter.xml(source)
local root = document.elements[1]
assert(root.name == "p:root")
assert(root.attributes["xmlns:p"] == "urn:test")
assert(root.elements[1].type == "text")
assert(root.elements[2].name == "a")
assert(root.elements[4].elements[1].text == "B")
assert(root.elements[5].type == "cdata")
assert(root.elements[6].type == "comment")

local ordered = {
  declaration = { attributes = { version = "1.0", encoding = "UTF-8" } },
  elements = {
    {
      type = "element",
      name = "root",
      attributes = { id = "7" },
      elements = {
        { type = "text", text = "before" },
        { type = "element", name = "a", elements = { { type = "text", text = "A" } } },
        { type = "text", text = "between" },
        { type = "element", name = "a", elements = { { type = "text", text = "B" } } },
      },
    },
  },
}
equal(converter.xml(converter.json(ordered)), ordered)

local convenient = converter.json({ person = {
  ["$"] = { id = 3 },
  name = "Ada",
  phone = { "1", "2" },
} }, { namespace = "urn:person" })
assert(convenient:match("^<person") and convenient:match('xmlns="urn:person"'))
assert(convenient:match('<name>Ada</name>'))
assert(#convenient:gsub("<phone>", "") < #convenient) -- both phone siblings are emitted
assert(converter.json({ value = "ok" }, { rootElement = "result", namespace = { r = "urn:result" } }) == '<result xmlns:r="urn:result"><value>ok</value></result>')

local escaped = converter.xml('<r value="&lt;&amp;&quot;&#9;&#10;&#13;">&amp;amp; &lt; &#13;</r>')
assert(escaped.elements[1].attributes.value == '<&"\t\n\r')
assert(escaped.elements[1].elements[1].text == "&amp; < \r")
equal(converter.xml(converter.json(escaped)), escaped)

rejects(function() converter.xml("<root>") end, "Malformed XML")
rejects(function() converter.xml('<!DOCTYPE root [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><root>&xxe;</root>') end, "DTD")
rejects(function() converter.xml("<root>&xxe;</root>") end, "entity")
rejects(function() converter.json({ elements = {
  { type = "element", name = "a" },
  { type = "element", name = "b" },
} }) end, "exactly one root")
rejects(function() converter.xml('<r x="1" x="2"/>') end, "duplicate")
rejects(function() converter.json({ ["p:r"] = json.null }) end, "unbound")

return true
