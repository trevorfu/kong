local mysql = require "kong.custom_plugins.apirouter.mysql"
local redis = require "kong.custom_plugins.apirouter.redis"

local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"

local get_headers = ngx.req.get_headers
local fmt = string.format

local get_limit_key = function(api_id, date, uid)
  return fmt("apirouter:limit:%s:%s:%s", api_id, date, uid)
end

local get_total_key = function(date, uid)
  return fmt("apirouter:limit:total:%s:%s", date, uid)
end

local ApiRouterHandler = BasePlugin:extend()
ApiRouterHandler.PRIORITY = 3000

local KEY_PREFIX = "apirouter"

function ApiRouterHandler:new()
  ApiRouterHandler.super.new(self, "apirouter")
end

function ApiRouterHandler:init_worker()
  ApiRouterHandler.super.init_worker(self)
end

function ApiRouterHandler:certificate()
  ApiRouterHandler.super.certificate(self)
end

function ApiRouterHandler:rewrite()
  ApiRouterHandler.super.rewrite(self)
end

function ApiRouterHandler:access(conf)
  ApiRouterHandler.super.access(self)
  -- get token from header[user-key]
  local token = get_headers()[conf.key_names]
  if token == nil or token == "" then
    ngx.log(ngx.ERR, "[apirouter] token can't be nil.")
    return responses.send(403, "API Access Forbidden")
  end
  -- verify token by redis & mysql
  local key = KEY_PREFIX .. "_" .. token

  local ok, result, err = redis:get(conf, key)
  if err then
    ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    return responses.send(503, "Service Unavailable - RT")
  end

  local current_date = os.date("%Y%m%d")
  local api_id = ngx.ctx.api.name -- ngx.ctx.api.id
  local count_key, total_key
  
  if not ok or ok == false or tostring(result) == "userdata: NULL" then
    local sql = "select user_id from t_user_api where api_token = '" .. token .. "'"
    local ok, user_table, sqlstate = mysql:query(conf, sql)
    if ok == false then
      ngx.log(ngx.ERR, "[apirouter] access mysql failed: ", tostring(user_table))
      return responses.send(503, "Service Unavailable - MQ")
    end

    if not user_table or table.getn(user_table) ~= 1 or not user_table[1]["user_id"] then
      ngx.log(ngx.ERR, "[apirouter] get token failed: ", token)
      return responses.send(401, "Token Unauthorized")
    else
      local uid = user_table[1]["user_id"]
      count_key = get_limit_key(api_id,current_date,uid) 
      total_key = get_total_key(current_date,uid) 
      
      -- TODO set redis key
      local ok, result, err = redis:set(conf, key, uid)
      if not ok or ok == false then
        ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
      end
    end
  else
    local uid = tostring(result)
    count_key = get_limit_key(api_id,current_date,uid)
	total_key = get_total_key(current_date,uid) 
  end
  
  -- TODO check total limit 2000 
  local ok, count = self:check_total_limit(conf, total_key)
  if not ok or ok == false then
    ngx.log(ngx.ERR, "[apirouter] check total limit failed: ", tostring(count))
    return responses.send(503, "Service Unavailable - RL")
  end
  
  local times = tonumber(count)
  if (times >= 2000) then
    ngx.log(ngx.ERR, "[apirouter] api invoke times limited: ", token)
    return responses.send(430, "API Total Request Limited")
  end
  
  -- TODO check api limit 500
  local ok, count = self:check_apicall_limit(conf, count_key)
  if not ok or ok == false then
    ngx.log(ngx.ERR, "[apirouter] check limit failed: ", tostring(count))
    return responses.send(503, "Service Unavailable - RL")
  end
  
  local times = tonumber(count)
  if (times >= conf.limit_times) then
    ngx.log(ngx.ERR, "[apirouter] api invoke times limited: ", token)
    return responses.send(429, "API Request Limited")
  end

  self:increase_count(conf, count_key, total_key)
end

function ApiRouterHandler:increase_count(conf, count_key, total_key)
  local ok, count, err = redis:get(conf, count_key)
  if err then
    ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    return responses.send(503, "Service Unavailable - RL")
  end

  local count_value = tostring(count)
  if (count_value == "userdata: NULL") then
    local ok, result, err = redis:set(conf, count_key, 1)
    if not ok or ok == false then
      ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    end
  else
    local ok, result, err = redis:set(conf, count_key, tonumber(count) + 1)
    if not ok or ok == false then
      ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    end
  end
  
  local ok, count, err = redis:get(conf, total_key)
  if err then
    ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    return responses.send(503, "Service Unavailable - RL")
  end

  local count_value = tostring(count)
  if (count_value == "userdata: NULL") then
    local ok, result, err = redis:set(conf, total_key, 1)
    if not ok or ok == false then
      ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    end
  else
    local ok, result, err = redis:set(conf, total_key, tonumber(count) + 1)
    if not ok or ok == false then
      ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    end
  end
end

function ApiRouterHandler:check_total_limit(conf, total_key)
  local ok, count, err = redis:get(conf, total_key)
  if err then
    ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    return false, "http internal server error"
  end

  local count_value = tostring(count)
  if not count_value then
    return true, "0"
  end

  if (count_value ~= "userdata: NULL") then
    return true, count_value
  end

  return true, "0"
end

function ApiRouterHandler:check_apicall_limit(conf, count_key)
  local ok, count, err = redis:get(conf, count_key)
  if err then
    ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    return false, "http internal server error"
  end

  local count_value = tostring(count)
  if not count_value then
    return true, "0"
  end

  if (count_value ~= "userdata: NULL") then
    return true, count_value
  end

  return true, "0"
end

function ApiRouterHandler:header_filter()
  ApiRouterHandler.super.header_filter(self)
end

function ApiRouterHandler:body_filter()
  ApiRouterHandler.super.body_filter(self)
end

function ApiRouterHandler:log()
  ApiRouterHandler.super.log(self)
end

return ApiRouterHandler