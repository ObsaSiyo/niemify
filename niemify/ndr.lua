local lxp = require("lxp")
local lfs = require("lfs")

local separator = "\1"
local schema_name = "http://www.w3.org/2001/XMLSchema" .. separator .. "schema"
local target_attribute = "https://docs.oasis-open.org/niemopen/ns/specification/conformanceTargets/6.0/"
  .. separator .. "conformanceTargets"
local extension = "https://docs.oasis-open.org/niemopen/ns/specification/NDR/6.0/#ExtensionSchemaDocument"

local svrl = "http://purl.oclc.org/dsdl/svrl" .. separator
local pattern_count = 144 -- All active patterns emitted by the pinned extension profile.

local M = {
  target_id = extension,
  rules_revision = "33ed73c4b3f5e305b4c6cdb2d35e8ef09ced7817",
}

-- Select a profile, not a conformance result. CTAS uses the first matching
-- attribute in document order; NDR rule 9-2 checks its placement separately.
function M.extension_target(xml)
  local root, targets, has_dtd
  local parser = lxp.new({
    StartElement = function(_, name, attributes)
      root = root or name
      if targets == nil then targets = attributes[target_attribute] end
    end,
    StartDoctypeDecl = function(current)
      has_dtd = true
      current:stop()
    end,
  }, separator)
  local parsed, diagnostic, line, column = parser:parse(xml)
  if parsed then parsed, diagnostic, line, column = parser:parse() end
  if not parsed then
    -- LuaExpat closes the parser but can raise when finalizing invalid XML.
    pcall(parser.close, parser)
    if has_dtd then return nil, "DTD declarations are not allowed in the entry XSD" end
    return nil, ("Malformed entry XSD at line %d, column %d: %s"):format(line, column, diagnostic)
  end
  parser:close()

  if root ~= schema_name then return nil, "Entry XSD root must be an XML Schema schema element" end
  if not targets or not targets:find("[^ \t\r\n]") then
    return nil, "Missing NIEM 6.0 conformance target in the effective conformanceTargets attribute"
  end
  for target in targets:gmatch("[^ \t\r\n]+") do
    if target == extension then return target end
  end
  return nil, "Unsupported NIEM conformance target; expected " .. extension .. ", found: " .. targets
end

-- Only interpret a dedicated SVRL report from the pinned evaluator. The
-- process exit and identity of the evaluated input are checked by the caller.
function M.read_report(xml)
  local depth, count = 0, 0
  local seen, findings = {}, {}
  local last_pattern, fired, finding, text, invalid, failed
  local function reject(parser)
    invalid = true
    parser:stop()
  end

  local parser = lxp.new({
    StartDoctypeDecl = reject,
    StartElement = function(current, name, attributes)
      depth = depth + 1
      if depth == 1 then
        if name ~= svrl .. "schematron-output" then reject(current) end
      elseif depth == 2 then
        if name == svrl .. "active-pattern" then
          local id = attributes.id
          -- The pinned 9-32 pattern has a title but no ID.
          if not id and attributes.name == "Association type derived from structures:AssociationType" then
            id = "rule9-32"
          end
          if not id or not id:match("^rule%d+%-%d+[a-z]?$") or seen[id] then return reject(current) end
          seen[id], last_pattern, fired = true, id, false
          count = count + 1
        elseif name == svrl .. "fired-rule" then
          if not last_pattern or not attributes.context then return reject(current) end
          fired = true
        elseif name == svrl .. "failed-assert" or name == svrl .. "successful-report" then
          local mandatory = name == svrl .. "failed-assert"
          local role = attributes.role
          if not fired or (mandatory and role ~= nil) or (not mandatory and role ~= "warning") then
            return reject(current)
          end
          finding = { severity = mandatory and "error" or "warning", location = attributes.location }
        elseif name ~= svrl .. "ns-prefix-in-attribute-values" then
          reject(current)
        end
      elseif depth == 3 and finding and not text and name == svrl .. "text" then
        text = {}
      else
        reject(current)
      end
    end,
    CharacterData = function(current, value)
      if depth == 3 and text then
        text[#text + 1] = value
      elseif value:find("%S") then
        reject(current)
      end
    end,
    EndElement = function(current)
      if depth == 2 and finding then
        local message = text and table.concat(text):match("^%s*(.-)%s*$")
        local id = message and message:match("^Rule (%d+%-%d+):%s*%S")
        if not id or last_pattern:gsub("[a-z]$", "") ~= "rule" .. id then return reject(current) end
        finding.id, finding.message = id, message
        findings[#findings + 1] = finding
        failed = failed or finding.severity == "error"
        finding, text = nil, nil
      end
      depth = depth - 1
    end,
  }, separator)
  local parsed = parser:parse(xml)
  if parsed then parsed = parser:parse() end
  if not parsed then
    pcall(parser.close, parser)
    return nil, invalid and "Unexpected SVRL structure or diagnostic" or "Malformed or truncated SVRL"
  end
  parser:close()
  if count ~= pattern_count or last_pattern ~= "rule9-94" then
    return nil, "Incomplete SVRL for the pinned NIEM 6 extension profile"
  end
  return failed and "failed" or "passed", findings
end

local rules_name = "extTarget-6.0.sch"
local rules_hash = "60067e43742bd93aad7ff70c7a72d4fb356a99fc95ac3893f5b06ffe73475c0e"
local report_limit = 4 * 1024 * 1024

local function quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function absolute(path)
  if path:sub(1, 1) == "/" then return path end
  return lfs.currentdir() .. "/" .. path
end

local function read_file(path, limit)
  local file <close> = io.open(path, "rb")
  if not file then return nil end
  local value = file:read(limit + 1)
  if value and #value <= limit then return value end
end

local function isolated()
  local status = read_file("/proc/self/status", 65536)
  local interfaces = read_file("/proc/self/net/dev", 65536)
  if not status or not interfaces or not status:match("\nNoNewPrivs:%s*1\n")
    or not status:match("\nCapBnd:%s*0+\n") or not status:match("\nCapEff:%s*0+\n") then
    return false
  end
  local loopback
  for name in interfaces:gmatch("\n[ \t]*([^%s:]+):") do
    if name ~= "lo" then return false end
    loopback = true
  end
  return loopback == true
end

local function collect_files(root, relative, files)
  for name in lfs.dir(root .. "/" .. relative) do
    if name ~= "." and name ~= ".." then
      local path = relative .. "/" .. name
      local mode = lfs.symlinkattributes(root .. "/" .. path, "mode")
      if mode == "directory" then
        if not collect_files(root, path, files) then return false end
      elseif mode == "file" then
        files[#files + 1] = path
      else
        return false
      end
    end
  end
  return true
end

local function pinned_rules(path)
  local root, name = path:match("^(.*)/sch/([^/]+)$")
  if name ~= rules_name or lfs.symlinkattributes(root .. "/sch", "mode") ~= "directory" then return false end
  local files = {}
  local ok, collected = pcall(collect_files, root, "sch", files)
  if not ok or not collected then return false end
  table.sort(files)
  for i, file in ipairs(files) do files[i] = quote(file) end
  local pipe = io.popen("cd " .. quote(root) .. " && sha256sum -- " .. table.concat(files, " ")
    .. " | sha256sum", "r")
  if not pipe then return false end
  local digest = pipe:read("l")
  local closed = pipe:close()
  return closed and digest and digest:match("^%x+") == rules_hash
end

-- Caller explicitly opts in and supplies trusted local inputs. SCHEval on
-- PATH must be the qualified distribution; never launch it on a networked host.
function M.run(entry, rules, catalog)
  if not isolated() then return nil, "SCHEval requires network-denied Linux with no capabilities and no new privileges" end
  if not os.execute("command -v scheval >/dev/null 2>&1") then return nil, "SCHEval executable not found on PATH" end
  if not rules or lfs.attributes(rules, "mode") ~= "file" then return nil, "Pinned NIEM rules file is missing" end
  rules = absolute(rules)
  if not pinned_rules(rules) then return nil, "NIEM rule tree does not match the pinned extension profile" end
  if lfs.attributes(entry, "mode") ~= "file" then return nil, "Entry XSD is not a local file" end
  local xml = read_file(entry, report_limit)
  if not xml then return nil, "Cannot read entry XSD or it exceeds the size limit" end
  local target, reason = M.extension_target(xml)
  if not target then return nil, reason end
  if catalog and lfs.attributes(catalog, "mode") ~= "file" then return nil, "SCHEval catalog is not a local file" end

  local pipe = io.popen("mktemp -d /tmp/niemify-ndr.XXXXXXXX", "r")
  if not pipe then return nil, "Unable to create SCHEval report directory" end
  local directory = pipe:read("l")
  if not pipe:close() or not directory then return nil, "Unable to create SCHEval report directory" end
  local report, diagnostics = directory .. "/report.xml", directory .. "/stderr"
  local command = "limiter=timeout; if command -v gnutimeout >/dev/null 2>&1; then limiter=gnutimeout; fi; "
    .. 'ulimit -f 4096 && "$limiter" --kill-after=2s 30s scheval --svrl --schema ' .. quote(rules)
    .. (catalog and " --catalog " .. quote(absolute(catalog)) or "")
    .. " --output " .. quote(report) .. " " .. quote(absolute(entry)) .. " >/dev/null 2>" .. quote(diagnostics)
    .. "; printf '%s\\n' \"$?\""
  local evaluator = io.popen(command, "r")
  local code
  if evaluator then
    code = tonumber(evaluator:read("l"))
    evaluator:close()
  end
  local ok = code == 0
  local output = ok and read_file(report, report_limit)
  local detail = not ok and read_file(diagnostics, 4096)
  os.remove(report)
  os.remove(diagnostics)
  lfs.rmdir(directory)
  if not ok then
    if code == 124 or code == 137 or code == 143 then
      return nil, "SCHEval evaluation was interrupted or timed out"
    end
    return nil, "SCHEval execution failed (exit " .. tostring(code) .. ")"
      .. (detail and (": " .. detail:gsub("%s+$", "")) or "")
  end
  if not output then return nil, "SCHEval did not produce a complete report within the size limit" end
  return M.read_report(output)
end

return M
