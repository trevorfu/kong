local config = require "kong.custom_plugins.apirouter.config"
local resty_redis = require "resty.redis"

local redis = {}

--[[
    先从连接池取连接,如果没有再建立连接.
    返回:
        false,出错信息.
        true,redis连接
--]]
function redis:get_connect()
  if ngx.ctx[redis] then
    return true, ngx.ctx[redis]
  end

  local client, errmsg = resty_redis:new()
  if not client then
    return false, "[redis] socket failed: " .. (errmsg or "nil")
  end

  client:set_timeout(10000)  --10秒

  local result, errmsg = client:connect(config.REDIS_HOST, config.REDIS_PORT)
  if not result then
    return false, errmsg
  end

  ngx.ctx[redis] = client
  return true, ngx.ctx[redis]
end

function redis:close()
  if ngx.ctx[redis] then
    ngx.ctx[redis]:set_keepalive(60000, 300)
    ngx.ctx[redis] = nil
  end
end

function redis:set(key, value)
  local ret, client = self:get_connect()
  if not ret then
    return false, client, nil
  end

  local result, errmsg = client:set(key, value)
  self:close()

  if not result then
    return false, nil, "[redis] set value failed: " .. (errmsg or "nil")
  end

  return true, result, nil
end

function redis:get(key)
  local ret, client = self:get_connect()
  if not ret then
    return false, client, nil
  end

  local result, errmsg = client:get(key)
  self:close()

  if errmsg then
    return false, nil, "[redis] get value failed: " .. (errmsg or "nil")
  else
    return true, result, nil
  end
end

return redis