local mysql = require "kong.custom_plugins.apirouter.mysql"
local redis = require "kong.custom_plugins.apirouter.redis"
local config = require "kong.custom_plugins.apirouter.config"

local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"

local get_headers = ngx.req.get_headers

local ApiRouterHandler = BasePlugin:extend()
ApiRouterHandler.PRIORITY = 3000

local KEY_PREFIX = "apirouter"

function ApiRouterHandler:new()
  ApiRouterHandler.super.new(self, "apirouter")
end

function ApiRouterHandler:init_worker(config)
  ApiRouterHandler.super.init_worker(self)
end

function ApiRouterHandler:certificate(config)
  ApiRouterHandler.super.certificate(self)
end

function ApiRouterHandler:rewrite(config)
  ApiRouterHandler.super.rewrite(self)
end

function ApiRouterHandler:access(conf)
  ApiRouterHandler.super.access(self)

  local token = get_headers()["user-key"]
  if token == nil then
    ngx.log(ngx.ERR, "[apirouter] token can't be nil.")
    return responses.send_HTTP_FORBIDDEN()
  end

  local key = KEY_PREFIX .. "_" .. token

  local is_true, result, errmsg = redis:get(key)
  if errmsg then
    ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(errmsg))
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(errmsg)
  end

  local current_date = os.date("%Y%m%d")

  if not is_true or is_true == false or tostring(result) == "userdata: NULL" then
    local sql = "select user_id from t_user_api where api_token = '" .. token .. "'"
    local is_true, user_table, sqlstate = mysql:query(sql)
    if is_true == false then
      ngx.log(ngx.ERR, "[apirouter] access mysql failed: ", tostring(is_true))
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(is_true)
    end

    if not user_table or table.getn(user_table) ~= 1 or not user_table[1]["user_id"] then
      ngx.log(ngx.ERR, "[apirouter] get token failed: ", tostring(errmsg))
      return responses.send_HTTP_FORBIDDEN()
    else
      local uid = user_table[1]["user_id"]
      local count_key = KEY_PREFIX .. "_" .. current_date .. "_" .. uid

      local is_true, errmsg = self:check_apicall_limit(count_key)
      if not is_true or is_true == false then
        ngx.log(ngx.ERR, "[apirouter] check limit failed: ", tostring(errmsg))
        return responses.send_HTTP_FORBIDDEN()
      end

      local is_true, result, errmsg = redis:set(key, uid)
      if not is_true or is_true == false then
        ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(errmsg))
      end

      self:increase_count(count_key)
    end
  else
    local uid = tostring(result)
    local count_key = KEY_PREFIX .. "_" .. current_date .. "_" .. uid

    local is_true, errmsg = self:check_apicall_limit(count_key)
    if not is_true or is_true == false then
      ngx.log(ngx.ERR, "[apirouter] check limit failed: ", tostring(errmsg))
      return responses.send_HTTP_FORBIDDEN()
    end

    self:increase_count(count_key)
  end
end

function ApiRouterHandler:increase_count(count_key)
  local is_true, count, errmsg = redis:get(count_key)
  if errmsg then
    ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(errmsg))
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(errmsg)
  end

  local count_value = tostring(count)
  if (count_value == "userdata: NULL") then
    local is_true, result, errmsg = redis:set(count_key, 1)
    if not is_true or is_true == false then
      ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(errmsg))
    end
  else
    local is_true, result, err = redis:set(count_key, tonumber(count) + 1)
    if not is_true or is_true == false then
      ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(err))
    end
  end
end

function ApiRouterHandler:check_apicall_limit(count_key)
  local is_true, count, errmsg = redis:get(count_key)
  if errmsg then
    ngx.log(ngx.ERR, "[apirouter] access redis failed: ", tostring(errmsg))
    return false, "http internal server error"
  end

  local count_value = tostring(count)
  if not count_value then
    return true, nil
  end

  if (count_value ~= "userdata: NULL") then
    if (tonumber(count_value) < config.DAILY_API_CALL_LIMIT) then
      return true, nil
    else
      return false, "the api call times greater than daily limits"
    end
  end

  return true, nil
end

function ApiRouterHandler:header_filter(config)
  ApiRouterHandler.super.header_filter(self)
end

function ApiRouterHandler:body_filter(config)
  ApiRouterHandler.super.body_filter(self)
end

function ApiRouterHandler:log(config)
  ApiRouterHandler.super.log(self)
end

return ApiRouterHandler