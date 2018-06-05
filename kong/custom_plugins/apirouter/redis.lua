local resty_redis = require "resty.redis"

local redis = {}

--[[
    先从连接池取连接,如果没有再建立连接.
    返回:
        false,出错信息.
        true,redis连接
--]]
function redis:get_connect(conf)
  if ngx.ctx[redis] then
    return true, ngx.ctx[redis]
  end

  local client, errmsg = resty_redis:new()
  if not client then
    return false, "[redis] socket failed: " .. (errmsg or "nil")
  end

  client:set_timeout(conf.redis_timeout)

  local ok, err = client:connect(conf.redis_host, conf.redis_port)
  if not ok then
    return false, err
  end
  
  if conf.redis_password and conf.redis_password ~= "" then
    local ok, err = client:auth(conf.redis_password)
    if not ok then
      return false, err
    end
  end
  
  if conf.redis_database ~= nil and conf.redis_database > 0 then
    local ok, err = client:select(conf.redis_database)
    if not ok then
      return false, err
    end
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

function redis:set(conf, key, value)
  local ok, client = self:get_connect(conf)
  if not ok then
    return false, client, nil
  end

  local ok, err = client:set(key, value)
  -- set expire 1 week
  client:expire(key, 604800)
  self:close()

  if not ok then
    return false, nil, "[redis] set value failed: " .. (err or "nil")
  end

  return true, ok, nil
end

function redis:get(conf, key)
  local ok, client = self:get_connect(conf)
  if not ok then
    return false, client, nil
  end

  local ok, err = client:get(key)
  self:close()

  if err then
    return false, nil, "[redis] get value failed: " .. (err or "nil")
  else
    return true, ok, nil
  end
end

return redis