local json = require('dkjson')
local lfs = require('lfs')
local root = lfs.currentdir()
local executable = assert(os.getenv('OPENPENCIL_HEADLESS_BUN'), 'OPENPENCIL_HEADLESS_BUN is unset')
local cli = assert(os.getenv('OPENPENCIL_HEADLESS_CLI'), 'OPENPENCIL_HEADLESS_CLI is unset')
local M = {}

local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function read(path, limit)
  local f <close> = assert(io.open(path, 'rb'))
  local data = f:read(limit + 1) or ''
  if #data > limit then error('OpenPencil output exceeds the size limit; select a smaller node or lower the scale.', 0) end
  return data
end
local function write(path, data)
  local f <close> = assert(io.open(path, 'wb'))
  assert(f:write(data))
end

local function file_path(relative, writing)
  if type(relative) ~= 'string' or relative == '' or relative:sub(1, 1) == '/' or relative:find('[\\%c]') or relative:find('//', 1, true) then
    error('Use a project-relative design path.', 0)
  end
  local pieces = {}
  for part in relative:gmatch('[^/]+') do
    if part == '.' or part == '..' then error('Design paths cannot contain . or .. segments.', 0) end
    pieces[#pieces + 1] = part
  end
  local name = pieces[#pieces]
  if relative:sub(-1) == '/' or (not name:match('%.fig$') and (writing or not name:match('%.pen$'))) then
    error(writing and 'Output must end in .fig.' or 'Design input must end in .fig or .pen.', 0)
  end
  local path = root
  for i, part in ipairs(pieces) do
    path = path .. '/' .. part
    local mode = lfs.symlinkattributes(path, 'mode')
    if i < #pieces then
      if mode ~= 'directory' then error('Design parent directory is missing or is a symlink: ' .. relative, 0) end
    elseif writing then
      if mode then error('Design output already exists: ' .. relative, 0) end
    elseif mode ~= 'file' then
      error('Design input is missing or is a symlink: ' .. relative, 0)
    end
  end
  return path
end

local function scratch(parent, fn)
  local seed = os.tmpname()
  os.remove(seed)
  local path = parent and (parent .. '/.open-pencil-' .. assert(seed:match('[^/]+$'))) or seed
  if not os.execute('umask 077; /bin/mkdir ' .. quote(path)) then error('Cannot create a design staging directory.', 0) end
  local ok, result = pcall(fn, path)
  for entry in lfs.dir(path) do
    if entry ~= '.' and entry ~= '..' then os.remove(path .. '/' .. entry) end
  end
  lfs.rmdir(path)
  if not ok then error(result, 0) end
  return result
end

local function run(work, ...)
  local args = { quote(executable), quote(cli) }
  for _, arg in ipairs({ ... }) do args[#args + 1] = quote(tostring(arg)) end
  local out, err = work .. '/stdout', work .. '/stderr'
  local ok = os.execute(table.concat(args, ' ') .. ' >' .. quote(out) .. ' 2>' .. quote(err))
  if not ok then
    local details = read(err, 65536):match('^%s*(.-)%s*$')
    if details == '' then details = read(out, 65536):match('^%s*(.-)%s*$') end
    error(details ~= '' and details or 'OpenPencil headless CLI failed.', 0)
  end
  return read(out, 1024 * 1024)
end

local function preview(work, input, node, scale)
  local png, encoded = work .. '/preview.png', work .. '/preview.base64'
  local args = { 'export', input, '--format', 'png', '--font-policy', 'strict', '--output', png, '--scale', scale or 1 }
  if node then args[#args + 1] = '--node'; args[#args + 1] = node end
  run(work, table.unpack(args))
  local size = assert(lfs.attributes(png, 'size'))
  if size > 6 * 1024 * 1024 then error('Preview is too large; choose a smaller node or a lower scale.', 0) end
  assert(os.execute('/usr/bin/base64 <' .. quote(png) .. ' >' .. quote(encoded)))
  return { type = 'image', mimeType = 'image/png', data = (read(encoded, 9 * 1024 * 1024):gsub('%s', '')) }
end

local function text(value) return { type = 'text', text = value } end
local layout = { type = 'string', description = 'OpenPencil JSX, e.g. <Frame name="Preview" w={320} h={160} bg="#183048" />.' }
local input = { type = 'string', description = 'Project-relative path to an existing .fig or .pen file.' }
local output = { type = 'string', description = 'Project-relative path to a new .fig file. Existing files are never overwritten.' }
local node = { type = 'string', description = 'Optional node ID. Omit to preview the first page.' }
local scale = { type = 'number', minimum = 0.1, maximum = 2, description = 'PNG scale, default 1.' }
local depth = { type = 'integer', minimum = 1, maximum = 8, description = 'Tree depth, default 2.' }

local function tool(name, description, properties, required)
  return { name = name, description = description, inputSchema = {
    type = 'object', properties = properties, required = required, additionalProperties = false,
  } }
end
M.tools = {
  tool('create_design', 'Create a new .fig file from JSX without launching OpenPencil. Displays the PNG preview inline in OMP.',
    { output = output, jsx = layout, scale = scale }, { 'output', 'jsx' }),
  tool('edit_design', 'Render JSX into an existing design and save a new .fig copy; the source is unchanged. Displays the PNG preview inline in OMP.',
    { file = input, output = output, jsx = layout, replace_id = { type = 'string', description = 'Optional existing node ID to replace; otherwise appends to the first page.' }, scale = scale }, { 'file', 'output', 'jsx' }),
  tool('preview_design', 'Render an existing design as a PNG shown inline in OMP without opening the desktop app.',
    { file = input, node = node, scale = scale }, { 'file' }),
  tool('inspect_design', 'Inspect the first page of a design and return its tree and node IDs.',
    { file = input, depth = depth }, { 'file' }),
}

local entries = {}
for _, spec in ipairs(M.tools) do entries[spec.name] = spec.inputSchema end

function M.call(name, args)
  local spec = entries[name]
  if not spec then return nil end
  if type(args) ~= 'table' or args == json.null then error('Tool arguments must be an object.', 0) end
  for key, value in pairs(args) do
    local rule = spec.properties[key]
    if not rule then error('Unknown tool argument: ' .. tostring(key), 0) end
    if rule.type == 'string' then
      if type(value) ~= 'string' or value == '' or (key == 'jsx' and #value > 250000) then error('Invalid ' .. key, 0) end
    else
      if type(value) ~= 'number' or value < rule.minimum or value > rule.maximum or (rule.type == 'integer' and value % 1 ~= 0) then
        error('Invalid ' .. key, 0)
      end
    end
  end
  for _, key in ipairs(spec.required) do if args[key] == nil then error('Missing argument: ' .. key, 0) end end
  if args.node and not args.node:match('^[%w_][%w_:%-]*$') then error('Invalid node ID.', 0) end
  local source = args.file and file_path(args.file, false)
  local destination = args.output and file_path(args.output, true)
  local parent = destination and destination:match('^(.*)/[^/]+$')
  return scratch(parent, function(work)
    if name == 'inspect_design' then
      local tree = run(work, 'tool', 'call', 'get_page_tree', source, '--args', json.encode({ depth = args.depth or 2 }), '--json')
      return { content = { text(tree) } }
    end
    if name == 'preview_design' then return { content = { preview(work, source, args.node, args.scale) } } end
    if not source then
      source = work .. '/blank.pen'
      write(source, '{"version":"2.10","children":[]}')
    end
    local staged, params = work .. '/design.fig', work .. '/render.json'
    write(params, assert(json.encode({ jsx = args.jsx, replace_id = args.replace_id })))
    run(work, 'tool', 'call', 'render', source, '--args-file', params, '--output', staged, '--json')
    local image = preview(work, staged, nil, args.scale)
    assert(lfs.link(staged, destination))
    return { content = { text('Saved ' .. args.output), image } }
  end)
end

return M
