local lxp = require("lxp")
local json = require("dkjson")

local M = {}
local NULL = json.null

local array_mt = json.array_mt or { __jsontype = "array" }
local object_mt = json.object_mt or { __jsontype = "object" }

local function array(value)
  return setmetatable(value or {}, array_mt)
end

local function object(value)
  return setmetatable(value or {}, object_mt)
end

local function is_null(value)
  return value == nil or value == NULL
end

local function is_array(value)
  if type(value) ~= "table" then
    return false
  end
  local mt = getmetatable(value)
  if mt and mt.__jsontype then
    return mt.__jsontype == "array"
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
  end
  if count == 0 then
    return false
  end
  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end
  return true
end

local function is_object(value)
  return type(value) == "table" and value ~= NULL and not is_array(value)
end

local function scalar(value)
  if is_null(value) then
    return ""
  end
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" then
    return tostring(value)
  end
  error("XML values must be scalar", 0)
end

local function sort_keys(value)
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(left, right)
    local lt, rt = type(left), type(right)
    if lt ~= rt then
      return lt == "number"
    end
    if lt == "number" then
      return left < right
    end
    return tostring(left) < tostring(right)
  end)
  return keys
end

local function xml_name(value)
  if type(value) ~= "string" then
    value = tostring(value)
  end
  if value == "" or value:find("[%s\"'<>&/=?]", 1) then
    error("Invalid XML name", 0)
  end
  return value
end

local function escape_text(value)
  return scalar(value)
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub("\r", "&#13;")
end

local function serialize_attributes(value)
  if not is_object(value) then
    error("XML attributes must be an object", 0)
  end
  local parts = {}
  for _, key in ipairs(sort_keys(value)) do
    local name = xml_name(key)
    local escaped = escape_text(value[key])
      :gsub("\"", "&quot;")
      :gsub("\t", "&#9;")
      :gsub("\n", "&#10;")
    parts[#parts + 1] = " " .. name .. "=\"" .. escaped .. "\""
  end
  return table.concat(parts)
end

local function serialize_node(node)
  if not is_object(node) then
    error("Invalid XML node", 0)
  end
  local kind = node.type
  if kind == "element" then
    local tag = xml_name(node.name)
    local start = "<" .. tag
    if node.attributes ~= nil then
      start = start .. serialize_attributes(node.attributes)
    end
    if node.elements == nil then
      return start .. "/>"
    end
    if not is_array(node.elements) then
      error("XML children must be an array", 0)
    end
    local children = {}
    for index = 1, #node.elements do
      children[index] = serialize_node(node.elements[index])
    end
    return start .. ">" .. table.concat(children) .. "</" .. tag .. ">"
  elseif kind == "text" then
    return escape_text(node.text)
  elseif kind == "cdata" then
    local value = scalar(node.cdata)
    if value:find("]]>", 1, true) then
      error("Invalid CDATA section", 0)
    end
    return "<![CDATA[" .. value .. "]]>"
  elseif kind == "comment" then
    local value = scalar(node.comment)
    if value:find("--", 1, true) or value:sub(-1) == "-" then
      error("Invalid XML comment", 0)
    end
    return "<!--" .. value .. "-->"
  elseif kind == "instruction" then
    local value = scalar(node.instruction)
    if value:find("?>", 1, true) then
      error("Invalid XML processing instruction", 0)
    end
    local target = xml_name(node.name)
    return "<?" .. target .. (value ~= "" and (" " .. value) or "") .. "?>"
  end
  error("Unsupported XML node type: " .. tostring(kind), 0)
end

local function append(parent, node)
  parent.elements = parent.elements or array()
  parent.elements[#parent.elements + 1] = node
end

local function parse_pass(source, namespace_separator, collect)
  local document = { elements = array() }
  local stack = { document }
  local cdata = nil

  local function current()
    return stack[#stack]
  end

  local callbacks = {
    StartDoctypeDecl = function()
      error("DTD and external entities are not allowed", 0)
    end,
    XmlDecl = function(_, version, encoding, standalone)
      if collect then
        local attrs = { version = version }
        if encoding ~= nil then
          attrs.encoding = "UTF-8"
        end
        if standalone ~= nil then
          attrs.standalone = standalone and "yes" or "no"
        end
        document.declaration = { attributes = object(attrs) }
      end
    end,
    StartElement = function(_, name, attrs)
      if collect then
        local node = { type = "element", name = name }
        if attrs ~= nil and next(attrs) ~= nil then
          local copy = {}
          for _, key in ipairs(attrs) do
            copy[key] = attrs[key]
          end
          node.attributes = object(copy)
        end
        append(current(), node)
        stack[#stack + 1] = node
      end
    end,
    EndElement = function()
      if collect then
        if #stack <= 1 then
          error("Malformed XML: unexpected closing element", 0)
        end
        stack[#stack] = nil
      end
    end,
    CharacterData = function(_, text)
      if not collect or #stack <= 1 or text == "" then
        return
      end
      if cdata ~= nil then
        cdata[#cdata + 1] = text
        return
      end
      local parent = current()
      local previous = parent.elements and parent.elements[#parent.elements]
      if previous and previous.type == "text" then
        previous.text = previous.text .. text
      else
        append(parent, { type = "text", text = text })
      end
    end,
    StartCdataSection = function()
      if collect then
        cdata = {}
      end
    end,
    EndCdataSection = function()
      if collect then
        local value = cdata and table.concat(cdata) or ""
        if #stack > 1 then
          append(current(), { type = "cdata", cdata = value })
        end
        cdata = nil
      end
    end,
    Comment = function(_, text)
      if collect then
        append(current(), { type = "comment", comment = text })
      end
    end,
    ProcessingInstruction = function(_, target, body)
      if collect then
        append(current(), { type = "instruction", name = target, instruction = body or "" })
      end
    end,
  }

  local parser = lxp.new(callbacks, namespace_separator)
  local ok, result, err = pcall(function()
    local parsed, parse_error = parser:parse(source)
    if not parsed then
      error(parse_error or "parser rejected input", 0)
    end
    local finished, finish_error = parser:parse()
    if not finished then
      error(finish_error or "parser rejected input", 0)
    end
    local closed, close_error = parser:close()
    if not closed then
      error(close_error or "parser rejected input", 0)
    end
    return true
  end)
  if not ok then
    error("Malformed XML: " .. tostring(result), 0)
  end
  if not result then
    error("Malformed XML: parser rejected input", 0)
  end
  if collect and #stack ~= 1 then
    error("Malformed XML: unclosed element", 0)
  end
  return document
end

local function parse_xml(source)
  if type(source) ~= "string" or source:match("^%s*$") then
    error("XML input must be a non-empty string", 0)
  end
  local document = parse_pass(source, nil, true)
  -- Expat's namespace-aware mode validates QName bindings and expanded-name
  -- collisions. The first pass intentionally retains the original prefixes.
  parse_pass(source, "\1", false)
  local roots = 0
  for index = 1, #document.elements do
    if is_object(document.elements[index]) and document.elements[index].type == "element" then
      roots = roots + 1
    end
  end
  if roots ~= 1 then
    error("XML document must have exactly one root element", 0)
  end
  return document
end

local function from_object(tag, value)
  tag = xml_name(tag)
  if not is_object(value) then
    if is_null(value) then
      return { type = "element", name = tag }
    end
    return { type = "element", name = tag, elements = array({ { type = "text", text = scalar(value) } }) }
  end

  local node = { type = "element", name = tag }
  local children = array()
  for _, key in ipairs(sort_keys(value)) do
    local child = value[key]
    key = tostring(key)
    if key == "$" or key == "@" or key == "_attributes" then
      if not is_object(child) then
        error("XML attributes must be an object", 0)
      end
      node.attributes = node.attributes or object()
      for _, attr in ipairs(sort_keys(child)) do
        node.attributes[tostring(attr)] = child[attr]
      end
    elseif key == "_text" or key == "#text" then
      children[#children + 1] = { type = "text", text = scalar(child) }
    else
      if is_array(child) then
        for index = 1, #child do
          children[#children + 1] = from_object(key, child[index])
        end
      else
        children[#children + 1] = from_object(key, child)
      end
    end
  end
  if #children > 0 then
    node.elements = children
  end
  return node
end

local function decode_json(input)
  if type(input) ~= "string" then
    return input
  end
  local value, position, decode_error = json.decode(input, 1, NULL)
  if decode_error ~= nil then
    error("Invalid JSON: " .. tostring(decode_error), 0)
  end
  if position ~= nil and input:sub(position):match("%S") then
    error("Invalid JSON: trailing data", 0)
  end
  return value
end

local function document_from_json(input, options)
  local value = decode_json(input)
  if not is_object(value) then
    error("JSON input must be an object", 0)
  end

  local document_like = false
  if is_array(value.elements) then
    for index = 1, #value.elements do
      local node = value.elements[index]
      if is_object(node) and node.type ~= nil then
        document_like = true
        break
      end
    end
  end
  if options.rootElement == nil and document_like then
    return value
  end

  local keys = sort_keys(value)
  if options.rootElement == nil and #keys ~= 1 then
    error("JSON input must contain exactly one root element (or specify rootElement)", 0)
  end
  local root
  if options.rootElement == nil then
    root = from_object(keys[1], value[keys[1]])
  else
    root = from_object(options.rootElement, value)
  end

  if options.namespace ~= nil then
    local namespaces
    if type(options.namespace) == "string" then
      namespaces = { [""] = options.namespace }
    elseif is_object(options.namespace) then
      namespaces = options.namespace
    else
      error("namespace must be a URI or prefix map", 0)
    end
    root.attributes = root.attributes or object()
    for _, prefix in ipairs(sort_keys(namespaces)) do
      local uri = namespaces[prefix]
      local attr = tostring(prefix) == "" and "xmlns" or "xmlns:" .. tostring(prefix)
      root.attributes[attr] = uri
    end
  end
  return { elements = array({ root }) }
end

local function render_xml(document)
  if not is_object(document) or not is_array(document.elements) then
    error("XML document must contain an elements array", 0)
  end
  local roots = 0
  for index = 1, #document.elements do
    local node = document.elements[index]
    if is_object(node) and node.type == "element" then
      roots = roots + 1
    end
  end
  if roots ~= 1 then
    error("XML document must have exactly one root element", 0)
  end
  local declaration = ""
  if document.declaration ~= nil then
    if not is_object(document.declaration) then
      error("Invalid XML declaration", 0)
    end
    local attrs = document.declaration.attributes
    if not is_object(attrs) or type(attrs.version) ~= "string" then error("Invalid XML declaration", 0) end
    declaration = '<?xml version="' .. escape_text(attrs.version):gsub('"', "&quot;") .. '"'
    if attrs.encoding ~= nil then declaration = declaration .. ' encoding="UTF-8"' end
    if attrs.standalone ~= nil then
      if attrs.standalone ~= "yes" and attrs.standalone ~= "no" then error("Invalid XML standalone value", 0) end
      declaration = declaration .. ' standalone="' .. attrs.standalone .. '"'
    end
    declaration = declaration .. "?>"
  end
  local parts = {}
  for index = 1, #document.elements do
    parts[index] = serialize_node(document.elements[index])
  end
  return declaration .. table.concat(parts)
end

local function validate_if_requested(xml, options)
  if options.validate == true or options.schema ~= nil then
    local schema = require("niemify.schema")
    schema.validate(xml, options.schema)
  end
end

function M.convert(input, input_type, options)
  input_type = input_type or "xml"
  options = options or {}
  if not is_object(options) then
    error("Options must be an object", 0)
  end
  local kind = string.lower(tostring(input_type))
  if kind == "xml" then
    local document = parse_xml(input)
    validate_if_requested(input, options)
    return document
  elseif kind == "json" then
    local document = document_from_json(input, options)
    local xml = render_xml(document)
    -- Validate generated output without constructing a second document tree.
    parse_pass(xml, "\1", false)
    validate_if_requested(xml, options)
    return xml
  end
  error('Input type must be "xml" or "json"', 0)
end

function M.xml(input, options)
  return M.convert(input, "xml", options)
end

function M.json(input, options)
  return M.convert(input, "json", options)
end

function M.validate(input, input_type, options)
  M.convert(input, input_type, options)
  return true
end

return M
