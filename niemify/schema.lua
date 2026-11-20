local lfs = require("lfs")
local json = require("dkjson")

local source = debug.getinfo(1, "S").source
local module_dir = source:sub(1, 1) == "@" and source:sub(2):match("^(.*)[/\\][^/\\]+$") or "."
if module_dir:sub(1, 1) ~= "/" then module_dir = lfs.currentdir() .. "/" .. module_dir end
local builtin_paths = { ["exchange-demo"] = module_dir .. "/exchange-demo.xsd" }
local config_filename = "config.json"

local function join(a, b)
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end
local function absolute_path(path)
  if path:sub(1, 1) == "/" then return path end
  return join(lfs.currentdir(), path)
end

local function home_path()
  local configured = os.getenv("NIEMIFY_HOME")
  if configured and configured ~= "" then return configured end
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if not xdg or xdg == "" then
    xdg = os.getenv("HOME") and join(os.getenv("HOME"), ".config") or "."
  end
  return join(xdg, "niemify")
end

local function config_path() return join(home_path(), config_filename) end
local function lock_path() return config_path() .. ".lock" end

local function default_config()
  return { activeSchema = "exchange-demo", schemas = setmetatable({}, { __jsontype = "object" }) }
end

local function clone(value)
  if type(value) ~= "table" then return value end
  local result = setmetatable({}, getmetatable(value))
  for k, v in pairs(value) do result[k] = clone(v) end
  return result
end

local function ensure_name(name)
  if type(name) ~= "string" or name:match("^%s*$") then error("Schema name must be a non-empty string", 2) end
  name = name:match("^%s*(.-)%s*$")
  if name == "." or name == ".." or name:find("[/\\%z]", 1) then error("Invalid schema name: " .. name, 2) end
  return name
end

local function read_config()
  local file = io.open(config_path(), "r")
  if not file then return default_config() end
  local text = file:read("*a"); file:close()
  local value, _, err = json.decode(text)
  if not value or type(value) ~= "table" or err then error("Cannot read schema configuration " .. config_path() .. (err and (": " .. err) or ""), 2) end
  local result = default_config()
  if value.activeSchema ~= nil then
    if type(value.activeSchema) ~= "string" then
      error("Schema configuration activeSchema must be a name or null", 2)
    end
    result.activeSchema = value.activeSchema
  end
  if value.schemas ~= nil then
    if type(value.schemas) ~= "table" then error("Schema configuration schemas must be an object", 2) end
    for name, entry in pairs(value.schemas) do
      if type(name) ~= "string" or type(entry) ~= "table" or type(entry.path) ~= "string" then error('Schema registration "' .. tostring(name) .. '" must contain a path', 2) end
      result.schemas[name] = { path = absolute_path(entry.path) }
    end
  end
  return result
end

local function mkdir_p(path)
  path = absolute_path(path)
  local built = "/"
  for part in path:gmatch("[^/]+") do
    built = built == "/" and "/" .. part or built .. "/" .. part
    if not lfs.attributes(built) then
      local ok, err = lfs.mkdir(built)
      if not ok and not lfs.attributes(built) then error("Cannot create schema configuration directory: " .. tostring(err), 2) end
    end
  end
end

local function with_lock(fn)
  mkdir_p(home_path())
  local ok, err = lfs.mkdir(lock_path())
  if not ok then error("Cannot lock schema configuration: " .. tostring(err), 2) end
  local ok, a, b = pcall(fn)
  os.remove(join(lock_path(), config_filename))
  lfs.rmdir(lock_path())
  if not ok then error(a, 2) end
  return a, b
end

local function write_config(value)
  local encoded = json.encode(value, { indent = true })
  local temp = join(lock_path(), config_filename)
  do
    local file <close> = assert(io.open(temp, "wb"))
    assert(file:write(encoded, "\n"))
    assert(file:flush())
  end
  assert(os.rename(temp, config_path()))
end

local function ensure_source(path)
  if type(path) ~= "string" or path:match("^%s*$") then error("Schema path must be a non-empty string", 2) end
  local absolute = absolute_path(path)
  local attr = lfs.attributes(absolute)
  if not attr then error("Schema file not found: " .. path, 2) end
  if attr.mode ~= "file" then error("Schema path is not a file: " .. path, 2) end
  if not absolute:lower():match("%.xsd$") then error("Schema file must have an .xsd extension: " .. path, 2) end
  local file = io.open(absolute, "r")
  if not file then error("Schema file is not readable: " .. path, 2) end
  file:close()
  return absolute
end

local function builtin()
  return { "exchange-demo" }
end

local function schema_path(name)
  local selected = name
  if selected == nil then selected = read_config().activeSchema end
  if not selected or selected == "" then error("No active schema is selected", 2) end
  selected = ensure_name(selected)
  if builtin_paths[selected] then
    if not lfs.attributes(builtin_paths[selected]) then error("Built-in schema is missing: " .. selected, 2) end
    return builtin_paths[selected]
  end
  local registration = read_config().schemas[selected]
  if not registration then error("Unknown schema: " .. selected, 2) end
  if not lfs.attributes(registration.path) then error("Registered schema file is missing: " .. registration.path, 2) end
  return registration.path
end

local function entry(name, path)
  return { name = name, path = path, builtin = builtin_paths[name] ~= nil }
end

local M = {}
function M.setup()
  return with_lock(function() local c = read_config(); write_config(c); return clone(c) end)
end
function M.config() return clone(read_config()) end
function M.builtin() return builtin() end
function M.list()
  local c = read_config(); local result = builtin(); local names = {}
  for name in pairs(c.schemas) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do result[#result + 1] = name end
  return result
end
function M.switch(name)
  name = ensure_name(name); local path = schema_path(name)
  return with_lock(function() local c = read_config(); c.activeSchema = name; write_config(c); return entry(name, path) end)
end
local function register(name, path, replacing)
  name = ensure_name(name)
  if builtin_paths[name] then error("Cannot replace built-in schema: " .. name, 2) end
  path = ensure_source(path)
  return with_lock(function()
    local c = read_config()
    if not replacing and c.schemas[name] then error("Schema is already registered: " .. name, 2) end
    if replacing and not c.schemas[name] then error("Cannot update unknown schema: " .. name, 2) end
    c.schemas[name] = { path = path }; write_config(c); return entry(name, path)
  end)
end
function M.upload(name, path) return register(name, path, false) end
function M.update(name, path) return register(name, path, true) end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end
function M.validate(xml, schema)
  if type(xml) ~= "string" then error("XML input must be a string", 2) end
  if xml:match("<!DOCTYPE[%s>]") then error("XML validation does not process DTD declarations", 2) end
  local filename = schema_path(schema)
  local schema_file = assert(io.open(filename, "r")); local schema_source = schema_file:read("*a"); schema_file:close()
  if schema_source:match("<!DOCTYPE[%s>]") then error("Schema validation does not process DTD declarations", 2) end
  local input, errors = os.tmpname(), os.tmpname()
  local ran, ok, code, details = pcall(function()
    do
      local file <close> = assert(io.open(input, "wb"))
      assert(file:write(xml))
      assert(file:flush())
    end
    local command = "xmllint --nonet --nocatalogs --noout --schema " .. shell_quote(filename) .. " " .. shell_quote(input) .. " 2>" .. shell_quote(errors)
    local success, _, status = os.execute(command)
    local diagnostics <close> = assert(io.open(errors, "rb"))
    return success, status, assert(diagnostics:read("a"))
  end)
  os.remove(input); os.remove(errors)
  if not ran then error(ok, 2) end
  if code == 127 then error("XML validation requires the xmllint executable", 2) end
  if not ok or code ~= 0 then error("XML does not conform to schema \"" .. (schema or "active") .. "\"" .. (details ~= "" and (": " .. details:gsub("%s+$", "")) or ""), 2) end
  return true
end

M.schemaPath = schema_path
return M
