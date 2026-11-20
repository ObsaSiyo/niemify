local json = require('dkjson')
local object = setmetatable({}, { __jsontype = 'object' })
local M = {}
local session, seq = nil, 0

local function decode(body)
  local value, _, err = json.decode(body, 1, json.null)
  if err then error('Desktop MCP returned invalid JSON', 0) end
  return value
end

local function config_string(value)
  return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
end

local function read(path)
  local file <close> = io.open(path, 'rb')
  return file and file:read('a') or ''
end

local function endpoints()
  local home = os.getenv('HOME')
  local dir = home and home .. '/Library/Application Support/OpenPencil'
  local path = os.getenv('OPENPENCIL_MCP_DISCOVERY_PATH') or (dir and dir .. '/mcp.json')
  local discovery = path and json.decode(read(path)) or nil
  if type(discovery) ~= 'table' then discovery = {} end
  local override = os.getenv('OPENPENCIL_MCP_SOCKET')
  if override == '' then override = nil end
  local sock = override or discovery.socketPath or (dir and dir .. '/mcp.sock')
  local token = os.getenv('OPENPENCIL_MCP_AUTH_TOKEN') or discovery.authToken
  if token == '' then token = nil end
  if token ~= nil and (type(token) ~= 'string' or token:find('%c')) then error('Invalid desktop MCP authentication token', 0) end
  local choices = {}
  if type(sock) == 'string' and sock:sub(1, 1) == '/' and not sock:find('%c') then
    choices[#choices + 1] = { socket = sock, origin = 'http://localhost', token = token }
  end
  local port = discovery.httpPort
  if not override and math.type(port) == 'integer' and port >= 1 and port <= 65535 then
    choices[#choices + 1] = { origin = 'http://127.0.0.1:' .. port, token = token }
  end
  return choices
end

local function http(endpoint, method, route, body, state)
  local output, headers = os.tmpname(), os.tmpname()
  local ok, status, data, response_headers = pcall(function()
    local pipe = assert(io.popen('/usr/bin/curl -q --config - >/dev/null 2>/dev/null', 'w'))
    local function option(key, value)
      if value then pipe:write(key, ' = ', config_string(value), '\n') else pipe:write(key, '\n') end
    end
    option('silent'); option('noproxy', '*'); option('http1.1')
    option('max-time', route == '/health' and '1' or '35')
    option('request', method); option('url', endpoint.origin .. route)
    option('output', output); option('dump-header', headers)
    if endpoint.socket then option('unix-socket', endpoint.socket) end
    if endpoint.token then option('header', 'Authorization: Bearer ' .. endpoint.token) end
    option('header', 'Accept: application/json, text/event-stream')
    if state then
      option('header', 'Mcp-Session-Id: ' .. state.id)
      option('header', 'MCP-Protocol-Version: ' .. state.version)
    end
    if body then
      option('header', 'Content-Type: application/json')
      option('data-binary', assert(json.encode(body)))
    end
    if not pipe:close() then return nil end
    local raw_headers = read(headers)
    return tonumber(raw_headers:match('^HTTP/%S+ (%d+)')), read(output), raw_headers
  end)
  os.remove(output); os.remove(headers)
  if not ok then error(status, 0) end
  return status, data, response_headers
end

local function health(require_document)
  for _, endpoint in ipairs(endpoints()) do
    local status, body = http(endpoint, 'GET', '/health')
    local info = status == 200 and json.decode(body)
    if type(info) == 'table' and (info.status == 'ok' or (not require_document and info.status == 'no_app')) then
      return endpoint
    end
  end
end

local function request(state, endpoint, method, params, notification)
  local message = { jsonrpc = '2.0', method = method, params = params or object }
  if not notification then seq = seq + 1; message.id = seq end
  local status, body, headers = http(endpoint, 'POST', '/mcp', message, state)
  if status == 401 then error('Desktop MCP authentication failed. Check Settings → MCP and OPENPENCIL_MCP_AUTH_TOKEN.', 0) end
  if not status then error('Lost connection to OpenPencil desktop MCP; request outcome is unknown.', 0) end
  if status == 404 and state then return nil, nil, headers, true end
  if notification and status == 202 then return end
  local reply = decode(body)
  if type(reply) ~= 'table' or reply.id ~= message.id or (reply.result == nil and reply.error == nil) then
    error('Unexpected desktop MCP response (HTTP ' .. status .. ')', 0)
  end
  return reply.result, reply.error, headers
end

local function connect(version)
  local endpoint = health(false)
  if not endpoint then return nil end
  local result, err, headers = request(nil, endpoint, 'initialize', {
    protocolVersion = version, capabilities = object, clientInfo = { name = 'open-pencil-lua', version = '1.0.0' },
  })
  if err then error(err.message or 'Could not initialize desktop MCP', 0) end
  local id
  for key, value in headers:gmatch('\n([^:\r\n]+):[ \t]*([^\r\n]+)') do
    if key:lower() == 'mcp-session-id' then id = value; break end
  end
  if not id or id:find('%c') or type(result.protocolVersion) ~= 'string' or result.protocolVersion:find('%c') then
    error('Desktop MCP returned an invalid session', 0)
  end
  local state = { endpoint = endpoint, id = id, version = result.protocolVersion }
  request(state, endpoint, 'notifications/initialized', nil, true)
  return state
end

function M.forward(version, method, params)
  session = session or connect(version)
  if not session then return nil, nil, true end
  local ok, result, err, _, expired = pcall(request, session, session.endpoint, method, params)
  if not ok then session = nil; error(result, 0) end
  if expired then
    session = connect(version)
    if not session then return nil, nil, true end
    result, err, _, expired = request(session, session.endpoint, method, params)
    if expired then error('Desktop MCP session expired; retry the command.', 0) end
  end
  return result, err
end

function M.launch()
  if health(true) then return 'OpenPencil desktop MCP is already connected.' end
  local ok, _, status = os.execute('/usr/bin/open -b net.dannote.open-pencil >&2')
  if not ok then error('macOS could not launch OpenPencil (exit ' .. tostring(status) .. '). Check that the desktop app is installed.', 0) end
  local deadline = os.time() + 12
  repeat
    if health(true) then return 'OpenPencil desktop MCP is connected.' end
    if os.time() >= deadline then break end
    os.execute('/bin/sleep 1')
  until false
  error('OpenPencil MCP did not connect to the desktop. Check Settings → MCP in the desktop app.', 0)
end

function M.close()
  if session then pcall(http, session.endpoint, 'DELETE', '/mcp', nil, session) end
end

return M
