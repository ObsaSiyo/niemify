local ndr = require("niemify.ndr")

if arg[1] == "runner" then
  local fixture = assert(os.getenv("NDR_QUALIFIED_DIR"), "set NDR_QUALIFIED_DIR to the staged SCHEval fixture")
  local entry = fixture .. "/extension.xsd"
  local rules = fixture .. "/rules/sch/extTarget-6.0.sch"
  local catalog = fixture .. "/model/xsd/xml-catalog.xml"
  local function rejects_run(schema, selected_rules, message)
    local outcome, reason = ndr.run(schema, selected_rules, catalog)
    assert(outcome == nil and reason:find(message, 1, true), reason)
  end
  local scenario = assert(os.getenv("NDR_RUNNER_CASE"))
  if scenario == "missing" then
    rejects_run(entry, rules, "executable not found")
  elseif scenario == "interrupted" then
    rejects_run(entry, rules, "interrupted or timed out")
  elseif scenario == "unisolated" then
    rejects_run(entry, rules, "requires network-denied Linux")
  else
    assert(scenario == "qualified")
    rejects_run(entry, fixture .. "/missing.sch", "rules file is missing")
    rejects_run(entry, entry, "rule tree does not match")
    local clean, findings = ndr.run(entry, rules, catalog)
    assert(clean == "passed", findings)
    assert(#findings == 0)
    local negative, failures = ndr.run(fixture .. "/extension-rule9-94.xsd", rules, catalog)
    assert(negative == "failed", failures)
    assert(#failures == 1 and failures[1].id == "9-94" and failures[1].severity == "error")
  end
  print("SCHEval runner: " .. scenario .. " passed")
  return
end

if arg[1] == "report" then
  local open = '<r:schematron-output xmlns:r="http://purl.oclc.org/dsdl/svrl">'
  local close = '</r:schematron-output>'
  local function pattern(id)
    return '<r:active-pattern id="rule' .. id .. '"/><r:fired-rule context="xs:schema"/>'
  end
  local patterns = {}
  for i = 1, 142 do patterns[i] = pattern("1-" .. i) end
  local base = open .. table.concat(patterns) .. pattern("9-21")
  local last = pattern("9-94")
  local warning = '<r:successful-report role="warning"><r:text>Rule 9-21: Avoid comments.</r:text></r:successful-report>'
  local failure = '<r:failed-assert><r:text>Rule 9-94: An element must be nillable.</r:text></r:failed-assert>'
  local function check(xml, expected, id, severity)
    local status, findings = ndr.read_report(xml)
    assert(status == expected, status == nil and findings or status)
    assert(#findings == (id and 1 or 0))
    if id then
      assert(findings[1].id == id and findings[1].severity == severity)
      assert(findings[1].message:find("Rule " .. id .. ":", 1, true))
    end
  end

  check(base .. last .. close, "passed")
  check(base .. warning .. last .. close, "passed", "9-21", "warning")
  check(base .. last .. failure .. close, "failed", "9-94", "error")
  for _, xml in ipairs({
    open .. close,
    base .. close,
    base .. last .. failure,
    "log output\n" .. base .. last .. close,
    base .. warning:gsub('role="warning"', 'role="error"') .. last .. close,
    base .. last .. failure:gsub("9%-94", "9-21") .. close,
    base .. last .. failure:gsub("failed%-assert>", 'failed-assert role="warning">', 1) .. close,
    base .. last .. '<r:unknown/>' .. close,
  }) do
    local status, diagnostic = ndr.read_report(xml)
    assert(status == nil and type(diagnostic) == "string", "unexpected result from invalid SVRL")
  end

  -- Optional, local-only reports from the documented qualification run.
  if arg[2] then
    local file <close> = assert(io.open(arg[2], "rb"))
    local expected = {
      clean = { "passed" }, negative = { "failed", "9-94", "error" },
      warning = { "passed", "9-21", "warning" },
    }
    for name, xml in file:read("a"):gmatch("CASE (%w+)[^\n]*\n(.-)\n%-%-%-SVRL%-END%-%-%-\n") do
      if expected[name] then
        check(xml, table.unpack(expected[name]))
        expected[name] = nil
      else
        assert(ndr.read_report(xml) == nil)
      end
    end
    assert(next(expected) == nil, "qualification input is missing a required report")
  end
  print("NIEM 6 SVRL report classification passed")
  return
end

assert(arg[1] == "target", "Usage: lua5.4 tests/ndr.lua target|report [qualification-output]")

local target = "https://docs.oasis-open.org/niemopen/ns/specification/NDR/6.0/#ExtensionSchemaDocument"
local reference = "https://docs.oasis-open.org/niemopen/ns/specification/NDR/6.0/#ReferenceSchemaDocument"
local ctas = 'xmlns:claim="https://docs.oasis-open.org/niemopen/ns/specification/conformanceTargets/6.0/"'
local namespaces = 'xmlns="http://www.w3.org/2001/XMLSchema" ' .. ctas
local function schema(attributes, children)
  return '<schema ' .. namespaces .. ' ' .. attributes .. '>' .. (children or '') .. '</schema>'
end
local function claim(value) return 'claim:conformanceTargets="' .. value .. '"' end
local function rejects(xml, reason)
  local selected, diagnostic = ndr.extension_target(xml)
  assert(selected == nil and diagnostic and diagnostic:find(reason, 1, true), diagnostic or selected)
end

assert(ndr.extension_target(schema(claim(target))) == target)
assert(ndr.extension_target(schema(claim('urn:other&#x9;' .. target .. '&#xA;'))) == target)
assert(ndr.extension_target(schema('', '<annotation ' .. claim(target) .. '/>')) == target)
rejects(schema(claim(reference), '<annotation ' .. claim(target) .. '/>'), 'Unsupported NIEM conformance target')
rejects(schema(claim(target .. '-lookalike')), 'Unsupported NIEM conformance target')
rejects(schema('conformanceTargets="' .. target .. '"'), 'Missing NIEM 6.0 conformance target')
rejects(schema('xmlns:lookalike="urn:not-ctas" lookalike:conformanceTargets="' .. target .. '"'),
  'Missing NIEM 6.0 conformance target')
rejects(schema(claim('&#x9; ')), 'Missing NIEM 6.0 conformance target')
rejects(schema(''), 'Missing NIEM 6.0 conformance target')
rejects('<schema ' .. ctas .. ' ' .. claim(target) .. '/>', 'Entry XSD root must be an XML Schema schema element')
rejects(schema(claim(target)) .. '<trailing', 'Malformed entry XSD')
rejects('<!DOCTYPE schema>' .. schema(claim(target)), 'DTD declarations are not allowed')

print('NIEM 6 extension target selection and rejection cases passed')
