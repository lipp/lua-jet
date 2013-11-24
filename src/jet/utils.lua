local noop = function() end

local is_empty_table = function(t)
  return pairs(t)(t) == nil
end

--- creates and returns an error table conforming to
-- JSON-RPC Invalid params.
local invalid_params = function(data)
  local err = {
    code = -32602,
    message = 'Invalid params',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Response Timeout.
local response_timeout = function(data)
  local err = {
    code = -32001,
    message = 'Response Timeout',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Internal Error.
local internal_error = function(data)
  local err = {
    code = -32603,
    message = 'Internal error',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Parse Error.
local parse_error = function(data)
  local err = {
    code = -32700,
    message = 'Parse error',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Method not Found.
local method_not_found = function(method)
  local err = {
    code = -32601,
    message = 'Method not found',
    data = method
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Invalid request.
local invalid_request = function(data)
  local err = {
    code = -32600,
    message = 'Invalid Request',
    data = data
  }
  return err
end

return {
  noop = noop,
  is_empty_table = is_empty_table,
  internal_error = internal_error,
  invalid_request = invalid_request,
  invalid_params = invalid_params,
  method_not_found = method_not_found,
  parse_error = parse_error,
  response_timeout = response_timeout
}

