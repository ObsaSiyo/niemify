local json = require('dkjson')
local headless = os.getenv('OPENPENCIL_MCP_MODE') == 'headless' and dofile('.omp/open-pencil-headless.lua')
local desktop = not headless and dofile('.omp/open-pencil-transport.lua')
local object = { __jsontype = 'object' }
local versions = { ['2024-11-05'] = true, ['2025-03-26'] = true, ['2025-06-18'] = true, ['2025-11-25'] = true }
local version = '2025-11-25'
local launch_tool = {
  name = 'launch_desktop',
  description = 'Launch the OpenPencil macOS app and wait for its MCP connection. Does not create or modify documents.',
  inputSchema = { type = 'object', properties = setmetatable({}, object), additionalProperties = false },
}

local function emit(message)
  message.jsonrpc = '2.0'
  io.write(assert(json.encode(message)), '\n')
  io.flush()
end

local function rpc_error(code, message)
  return { code = code, message = message }
end

local function tool_result(message, failed)
  return { content = { { type = 'text', text = message } }, isError = failed }
end

local function handle(request)
  if type(request) ~= 'table' or request.jsonrpc ~= '2.0' or type(request.method) ~= 'string' then
    return nil, rpc_error(-32600, 'Invalid Request')
  end
  local method = request.method
  local params = request.params or setmetatable({}, object)
  if type(params) ~= 'table' or params == json.null then return nil, rpc_error(-32602, 'Invalid params') end
  if method == 'initialize' then
    local requested = params.protocolVersion
    if versions[requested] then version = requested end
    local tools = headless and setmetatable({}, object) or { listChanged = true }
    return { protocolVersion = version, capabilities = { tools = tools },
      serverInfo = { name = headless and 'open-pencil-headless-lua' or 'open-pencil-lua', version = '1.0.0' } }
  elseif method == 'ping' then
    return setmetatable({}, object)
  elseif headless then
    if method == 'tools/list' then return { tools = headless.tools } end
    if method == 'tools/call' then
      local ok, result = pcall(headless.call, params.name, params.arguments)
      if not ok then return tool_result(tostring(result), true) end
      if result then return result end
      return nil, rpc_error(-32602, 'Unknown headless tool')
    end
    return nil, rpc_error(-32601, 'Method not found')
  elseif method == 'tools/call' and params.name == launch_tool.name then
    if params.arguments ~= nil and (type(params.arguments) ~= 'table' or params.arguments == json.null
        or next(params.arguments) ~= nil or (getmetatable(params.arguments) or {}).__jsontype == 'array') then
      return nil, rpc_error(-32602, 'launch_desktop takes no arguments')
    end
    local ok, message = pcall(desktop.launch)
    return tool_result(tostring(message), not ok), nil, ok
  elseif method == 'tools/list' or method == 'tools/call' then
    local ok, result, err, offline = pcall(desktop.forward, version, method, params)
    if not ok then
      if method == 'tools/call' then return tool_result(tostring(result), true) end
      io.stderr:write('OpenPencil discovery: ', tostring(result), '\n')
      return { tools = { launch_tool } }
    end
    if method == 'tools/list' then
      if err then return nil, err end
      if offline then return { tools = { launch_tool } } end
      if not params.cursor then table.insert(result.tools, 1, launch_tool) end
      return result
    end
    if offline then return tool_result('OpenPencil desktop MCP is offline. Call launch_desktop first.', true) end
    return result, err
  end
  return nil, rpc_error(-32601, 'Method not found')
end

for line in io.lines() do
  local request, stop, decode_error = json.decode(line, 1, json.null)
  local valid = not decode_error and not line:sub(stop or 1):find('%S')
  local id = type(request) == 'table' and request.id or nil
  local notification = valid and id == nil and type(request) == 'table'
    and request.jsonrpc == '2.0' and type(request.method) == 'string'
  if not notification then
    local result, err, changed
    if valid then
      local ok
      ok, result, err, changed = pcall(handle, request)
      if not ok then
        io.stderr:write('OpenPencil bridge: ', tostring(result), '\n')
        result, err = nil, rpc_error(-32603, 'Internal bridge error')
      end
    else
      err = rpc_error(-32700, 'Parse error')
    end
    emit({ id = id or json.null, result = result, error = err })
    if changed then emit({ method = 'notifications/tools/list_changed' }) end
  end
end

if desktop then desktop.close() end
